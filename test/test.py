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


async def run_decode_test(dut, test_bits, test_name):
    """Helper function to run a complete decode test sequence.
    Returns (decoded_bits, errors) tuple.
    """
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

    symbols = encode_k3(test_bits)
    dut._log.info(f"{test_name}: {len(test_bits)} bits")

    # Feed symbols
    for i, sym in enumerate(symbols):
        timeout = 0
        while timeout < 100:
            if safe_int(decoder.uo_out.value) & 0x1:
                break
            await RisingEdge(clk)
            timeout += 1
        if timeout >= 100:
            raise AssertionError(f"Timeout waiting for rx_ready at symbol {i}")

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
    while timeout < 2000:
        if not ((safe_int(decoder.uo_out.value) >> 3) & 0x1):
            break
        await RisingEdge(clk)
        timeout += 1

    if timeout >= 2000:
        raise AssertionError("Timeout waiting for decode to complete")

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
            dut._log.warning(f"Timeout at bit {i}, got {len(decoded)} bits")
            break

        decoded.append((safe_int(decoder.uo_out.value) >> 2) & 0x1)
        decoder.ui_in.value = 0x10
        await RisingEdge(clk)
        decoder.ui_in.value = 0
        await ClockCycles(clk, 3)

    errors = sum(1 for a, b in zip(test_bits, decoded) if a != b)
    return decoded, errors


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


@cocotb.test()
async def test_viterbi_all_ones(dut):
    """Test with all-one input (matches C golden model)"""
    dut._log.info("=== Viterbi Decoder Test (All Ones 8-bit) ===")
    test_bits = [1] * 8
    decoded, errors = await run_decode_test(dut, test_bits, "All Ones")
    dut._log.info(f"Input:   {test_bits}")
    dut._log.info(f"Decoded: {decoded}")
    dut._log.info(f"Errors:  {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_alternating_10(dut):
    """Test alternating 10101010 pattern (matches C golden model)"""
    dut._log.info("=== Viterbi Decoder Test (Alternating 10) ===")
    test_bits = [1, 0, 1, 0, 1, 0, 1, 0]
    decoded, errors = await run_decode_test(dut, test_bits, "Alternating 10")
    dut._log.info(f"Input:   {test_bits}")
    dut._log.info(f"Decoded: {decoded}")
    dut._log.info(f"Errors:  {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_alternating_01(dut):
    """Test alternating 01010101 pattern (matches C golden model)"""
    dut._log.info("=== Viterbi Decoder Test (Alternating 01) ===")
    test_bits = [0, 1, 0, 1, 0, 1, 0, 1]
    decoded, errors = await run_decode_test(dut, test_bits, "Alternating 01")
    dut._log.info(f"Input:   {test_bits}")
    dut._log.info(f"Decoded: {decoded}")
    dut._log.info(f"Errors:  {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_single_one_start(dut):
    """Test single 1 at start (matches C golden model)"""
    dut._log.info("=== Viterbi Decoder Test (Single 1 at Start) ===")
    test_bits = [1, 0, 0, 0, 0, 0, 0, 0]
    decoded, errors = await run_decode_test(dut, test_bits, "Single 1 Start")
    dut._log.info(f"Input:   {test_bits}")
    dut._log.info(f"Decoded: {decoded}")
    dut._log.info(f"Errors:  {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_single_one_end(dut):
    """Test single 1 at end (matches C golden model)"""
    dut._log.info("=== Viterbi Decoder Test (Single 1 at End) ===")
    test_bits = [0, 0, 0, 0, 0, 0, 0, 1]
    decoded, errors = await run_decode_test(dut, test_bits, "Single 1 End")
    dut._log.info(f"Input:   {test_bits}")
    dut._log.info(f"Decoded: {decoded}")
    dut._log.info(f"Errors:  {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_burst_1100(dut):
    """Test burst pattern 11001100 (matches C golden model)"""
    dut._log.info("=== Viterbi Decoder Test (Burst 1100) ===")
    test_bits = [1, 1, 0, 0, 1, 1, 0, 0]
    decoded, errors = await run_decode_test(dut, test_bits, "Burst 1100")
    dut._log.info(f"Input:   {test_bits}")
    dut._log.info(f"Decoded: {decoded}")
    dut._log.info(f"Errors:  {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_transition(dut):
    """Test transition pattern 00011100 (matches C golden model)"""
    dut._log.info("=== Viterbi Decoder Test (Transition 0->1->0) ===")
    test_bits = [0, 0, 0, 1, 1, 1, 0, 0]
    decoded, errors = await run_decode_test(dut, test_bits, "Transition")
    dut._log.info(f"Input:   {test_bits}")
    dut._log.info(f"Decoded: {decoded}")
    dut._log.info(f"Errors:  {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_32bit_zeros(dut):
    """Test 32-bit all zeros (full frame, matches C golden model)"""
    dut._log.info("=== Viterbi Decoder Test (32-bit All Zeros) ===")
    test_bits = [0] * 32
    decoded, errors = await run_decode_test(dut, test_bits, "32-bit Zeros")
    dut._log.info(f"Decoded {len(decoded)} bits, Errors: {errors}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_32bit_ones(dut):
    """Test 32-bit all ones (full frame, matches C golden model)"""
    dut._log.info("=== Viterbi Decoder Test (32-bit All Ones) ===")
    test_bits = [1] * 32
    decoded, errors = await run_decode_test(dut, test_bits, "32-bit Ones")
    dut._log.info(f"Decoded {len(decoded)} bits, Errors: {errors}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_32bit_pattern(dut):
    """Test 32-bit repeating pattern (full frame, matches C golden model)"""
    dut._log.info("=== Viterbi Decoder Test (32-bit Repeating Pattern) ===")
    # Repeating 10110100 pattern
    base = [1, 0, 1, 1, 0, 1, 0, 0]
    test_bits = base * 4  # 32 bits
    decoded, errors = await run_decode_test(dut, test_bits, "32-bit Pattern")
    dut._log.info(f"Decoded {len(decoded)} bits, Errors: {errors}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_32bit_prbs(dut):
    """Test 32-bit PRBS pattern (matches C golden model)"""
    dut._log.info("=== Viterbi Decoder Test (32-bit PRBS) ===")
    # Generate PRBS with 3-bit LFSR
    lfsr = 0x7
    test_bits = []
    for _ in range(32):
        test_bits.append(lfsr & 1)
        newbit = ((lfsr >> 2) ^ (lfsr >> 1)) & 1
        lfsr = ((lfsr << 1) | newbit) & 0x7
    decoded, errors = await run_decode_test(dut, test_bits, "32-bit PRBS")
    dut._log.info(f"Decoded {len(decoded)} bits, Errors: {errors}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")
