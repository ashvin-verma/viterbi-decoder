# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.triggers import ClockCycles, RisingEdge


def encode_k3(bits):
    """Encode bits with K=3, G0=7, G1=5 (LSB insertion)
    Matches the Verilog decoder's expected symbol format.
    """
    state = 0
    symbols = []
    for bit in bits:
        r = (state << 1) | bit
        g0 = bin(r & 0b111).count('1') % 2  # XOR of all 3 bits
        g1 = bin(r & 0b101).count('1') % 2  # XOR of bits 2 and 0
        symbols.append((g0 << 1) | g1)
        state = ((state << 1) | bit) & 0b11
    return symbols


def safe_int(val):
    """Safely convert LogicArray to int, treating X/Z as 0"""
    try:
        return int(val)
    except ValueError:
        return 0


@cocotb.test()
async def test_viterbi_decode_short(dut):
    """Test Viterbi decoder with a short 8-bit pattern"""
    dut._log.info("=== Viterbi Decoder Functional Test (8-bit) ===")

    # Use tb.v's clock - don't create a new clock driver
    decoder = dut.dut
    clk = dut.clk  # Use top-level clock from tb.v

    # Reset - long enough for gate-level
    decoder.rst_n.value = 0
    decoder.ui_in.value = 0
    decoder.uio_in.value = 0
    decoder.ena.value = 1
    await ClockCycles(clk, 20)
    decoder.rst_n.value = 1
    await ClockCycles(clk, 20)

    # Test pattern: simple sequence
    test_bits = [1, 0, 1, 1, 0, 1, 0, 0]
    symbols = encode_k3(test_bits)

    dut._log.info(f"Input bits:  {test_bits}")
    dut._log.info(f"Symbols:     {[f'{s:02b}' for s in symbols]}")

    # Feed symbols to decoder
    for i, sym in enumerate(symbols):
        # Wait for rx_ready (uo_out[0])
        timeout = 0
        while timeout < 100:
            out_val = safe_int(decoder.uo_out.value)
            if out_val & 0x1:
                break
            await RisingEdge(clk)
            timeout += 1

        if timeout >= 100:
            raise AssertionError(f"Timeout waiting for rx_ready at symbol {i}")

        # Send symbol: ui_in = {3'b0, read_ack, start, sym[1:0], valid}
        decoder.ui_in.value = (sym << 1) | 0x1
        await RisingEdge(clk)
        decoder.ui_in.value = 0
        await ClockCycles(clk, 3)

    dut._log.info("All symbols sent, starting decode...")

    # Start decoding (ui_in[3] = start)
    decoder.ui_in.value = 0x08
    await RisingEdge(clk)
    decoder.ui_in.value = 0
    await ClockCycles(clk, 5)

    # Wait for busy (uo_out[3]) to go low
    timeout = 0
    while timeout < 500:
        out_val = safe_int(decoder.uo_out.value)
        busy = (out_val >> 3) & 0x1
        if not busy:
            break
        await RisingEdge(clk)
        timeout += 1

    if timeout >= 500:
        raise AssertionError("Timeout waiting for decode to complete")

    dut._log.info(f"Decode completed in {timeout} cycles")
    await ClockCycles(clk, 10)

    # Read decoded bits
    decoded = []
    for i in range(len(test_bits)):
        # Wait for out_valid (uo_out[1])
        timeout = 0
        while timeout < 100:
            out_val = safe_int(decoder.uo_out.value)
            out_valid = (out_val >> 1) & 0x1
            if out_valid:
                break
            await RisingEdge(clk)
            timeout += 1

        if timeout >= 100:
            dut._log.warning(f"Timeout waiting for out_valid at bit {i}")
            break

        # Read bit (uo_out[2])
        out_val = safe_int(decoder.uo_out.value)
        out_bit = (out_val >> 2) & 0x1
        decoded.append(out_bit)

        # Acknowledge (ui_in[4] = read_ack)
        decoder.ui_in.value = 0x10
        await RisingEdge(clk)
        decoder.ui_in.value = 0
        await ClockCycles(clk, 3)

    dut._log.info(f"Decoded:     {decoded}")

    # Verify
    errors = sum(1 for a, b in zip(test_bits, decoded) if a != b)
    dut._log.info(f"Bit errors:  {errors}/{len(test_bits)}")

    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} bit errors")

    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_decode_16bit(dut):
    """Test Viterbi decoder with 16-bit pattern"""
    dut._log.info("=== Viterbi Decoder Functional Test (16-bit) ===")

    decoder = dut.dut
    clk = dut.clk

    # Reset
    decoder.rst_n.value = 0
    decoder.ui_in.value = 0
    decoder.uio_in.value = 0
    decoder.ena.value = 1
    await ClockCycles(clk, 20)
    decoder.rst_n.value = 1
    await ClockCycles(clk, 20)

    # 16-bit test pattern: alternating with some runs
    test_bits = [1, 0, 1, 0, 1, 1, 0, 0, 1, 1, 1, 0, 0, 0, 1, 0]
    symbols = encode_k3(test_bits)

    dut._log.info(f"Input bits ({len(test_bits)}): {test_bits}")

    # Feed symbols
    for i, sym in enumerate(symbols):
        timeout = 0
        while timeout < 100:
            if safe_int(decoder.uo_out.value) & 0x1:
                break
            await RisingEdge(clk)
            timeout += 1

        decoder.ui_in.value = (sym << 1) | 0x1
        await RisingEdge(clk)
        decoder.ui_in.value = 0
        await ClockCycles(clk, 3)

    # Start decode
    decoder.ui_in.value = 0x08
    await RisingEdge(clk)
    decoder.ui_in.value = 0
    await ClockCycles(clk, 5)

    # Wait for completion
    timeout = 0
    while timeout < 1000:
        if not ((safe_int(decoder.uo_out.value) >> 3) & 0x1):
            break
        await RisingEdge(clk)
        timeout += 1

    dut._log.info(f"Decode completed in {timeout} cycles")
    await ClockCycles(clk, 10)

    # Read output
    decoded = []
    for i in range(len(test_bits)):
        timeout = 0
        while timeout < 100:
            if (safe_int(decoder.uo_out.value) >> 1) & 0x1:
                break
            await RisingEdge(clk)
            timeout += 1

        if timeout >= 100:
            break

        decoded.append((safe_int(decoder.uo_out.value) >> 2) & 0x1)
        decoder.ui_in.value = 0x10
        await RisingEdge(clk)
        decoder.ui_in.value = 0
        await ClockCycles(clk, 3)

    dut._log.info(f"Decoded ({len(decoded)}): {decoded}")

    errors = sum(1 for a, b in zip(test_bits, decoded) if a != b)
    dut._log.info(f"Bit errors: {errors}/{len(test_bits)}")

    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} bit errors")

    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_all_zeros(dut):
    """Test with all-zero input (edge case)"""
    dut._log.info("=== Viterbi Decoder Test (All Zeros) ===")

    decoder = dut.dut
    clk = dut.clk

    # Reset
    decoder.rst_n.value = 0
    decoder.ui_in.value = 0
    decoder.uio_in.value = 0
    decoder.ena.value = 1
    await ClockCycles(clk, 20)
    decoder.rst_n.value = 1
    await ClockCycles(clk, 20)

    # All zeros
    test_bits = [0] * 8
    symbols = encode_k3(test_bits)

    dut._log.info(f"Input: {test_bits}, Symbols: {symbols}")

    # Feed symbols
    for sym in symbols:
        while not (safe_int(decoder.uo_out.value) & 0x1):
            await RisingEdge(clk)
        decoder.ui_in.value = (sym << 1) | 0x1
        await RisingEdge(clk)
        decoder.ui_in.value = 0
        await ClockCycles(clk, 3)

    # Start decode
    decoder.ui_in.value = 0x08
    await RisingEdge(clk)
    decoder.ui_in.value = 0

    # Wait for completion
    for _ in range(500):
        if not ((safe_int(decoder.uo_out.value) >> 3) & 0x1):
            break
        await RisingEdge(clk)

    await ClockCycles(clk, 10)

    # Read output
    decoded = []
    for _ in range(len(test_bits)):
        for _ in range(100):
            if (safe_int(decoder.uo_out.value) >> 1) & 0x1:
                break
            await RisingEdge(clk)
        decoded.append((safe_int(decoder.uo_out.value) >> 2) & 0x1)
        decoder.ui_in.value = 0x10
        await RisingEdge(clk)
        decoder.ui_in.value = 0
        await ClockCycles(clk, 3)

    dut._log.info(f"Decoded: {decoded}")

    errors = sum(1 for a, b in zip(test_bits, decoded) if a != b)
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")

    dut._log.info("=== TEST PASSED ===")
