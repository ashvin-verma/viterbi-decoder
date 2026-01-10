# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.triggers import ClockCycles, RisingEdge
import os

# Check for gate-level simulation
GL_TEST = os.environ.get('GATES', 'no') == 'yes'
TIMEOUT_MULT = 100 if GL_TEST else 1  # GL needs much longer timeouts


def encode_k5(bits):
    """Encode bits with K=5, G0=23 (octal), G1=35 (octal)
    Standard convolutional code, rate 1/2.
    """
    # G0 = 23 octal = 10011 binary
    # G1 = 35 octal = 11101 binary
    state = 0
    symbols = []
    for bit in bits:
        r = (state << 1) | bit
        g0 = bin(r & 0b10011).count('1') % 2  # G0 = 23 octal
        g1 = bin(r & 0b11101).count('1') % 2  # G1 = 35 octal
        symbols.append((g0 << 1) | g1)
        state = ((state << 1) | bit) & 0b1111  # Keep 4 bits (K-1)
    return symbols


def pack_symbols_to_byte(symbols):
    """Pack 4 x 2-bit symbols into a byte.
    symbols[0] -> bits [1:0], symbols[1] -> bits [3:2], etc.
    """
    if len(symbols) < 4:
        symbols = symbols + [0] * (4 - len(symbols))
    return (symbols[0] & 0x3) | ((symbols[1] & 0x3) << 2) | \
           ((symbols[2] & 0x3) << 4) | ((symbols[3] & 0x3) << 6)


def safe_int(val):
    """Safely convert LogicArray to int, treating X/Z as 0"""
    try:
        return int(val)
    except ValueError:
        return 0


async def run_uart_decode_test(dut, test_bits, test_name):
    """Run decode test using UART byte mode.
    Returns (decoded_bits, errors) tuple.

    Interface:
    - ui_in[0] = byte_valid
    - ui_in[3] = start
    - ui_in[4] = read_ack
    - uo_out[0] = byte_in_ready
    - uo_out[1] = byte_out_valid
    - uo_out[3] = busy
    - uo_out[4] = frame_done
    - uio_in[7:0] = input byte (4 symbols packed)
    - uio_out[7:0] = output byte (8 decoded bits)
    """
    clk = dut.clk

    # Reset - GL simulation needs more time for reset propagation
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1
    await ClockCycles(clk, 20 * TIMEOUT_MULT)
    dut.rst_n.value = 1
    await ClockCycles(clk, 50 * TIMEOUT_MULT)  # Wait for state to settle

    symbols = encode_k5(test_bits)
    dut._log.info(f"{test_name}: {len(test_bits)} bits -> {len(symbols)} symbols")

    # Pack symbols into bytes (4 symbols per byte)
    symbol_bytes = []
    for i in range(0, len(symbols), 4):
        chunk = symbols[i:i+4]
        symbol_bytes.append(pack_symbols_to_byte(chunk))

    # Feed symbol bytes
    for i, sym_byte in enumerate(symbol_bytes):
        # Wait for byte_in_ready (uo_out[0])
        timeout = 0
        max_timeout = 200 * TIMEOUT_MULT
        while timeout < max_timeout:
            if safe_int(dut.uo_out.value) & 0x1:
                break
            await RisingEdge(clk)
            timeout += 1
        if timeout >= max_timeout:
            raise AssertionError(f"Timeout waiting for byte_in_ready at byte {i}")

        # Send byte
        dut.uio_in.value = sym_byte
        dut.ui_in.value = 0x01  # byte_valid
        await RisingEdge(clk)
        dut.ui_in.value = 0
        await ClockCycles(clk, 2)

    # Wait for symbols to be processed
    await ClockCycles(clk, 20)

    # Start decode
    dut.ui_in.value = 0x08  # start
    await RisingEdge(clk)
    dut.ui_in.value = 0
    await ClockCycles(clk, 5)

    # Wait for busy to go low (K=5 with 16 states)
    timeout = 0
    max_timeout = 20000 * TIMEOUT_MULT  # K=5 ACS cycles
    while timeout < max_timeout:
        if not ((safe_int(dut.uo_out.value) >> 3) & 0x1):
            break
        await RisingEdge(clk)
        timeout += 1

    if timeout >= max_timeout:
        raise AssertionError("Timeout waiting for decode to complete")

    dut._log.info(f"Decode completed in {timeout} cycles")
    await ClockCycles(clk, 10)

    # Read output bytes
    decoded = []
    num_output_bytes = (len(test_bits) + 7) // 8

    for byte_idx in range(num_output_bytes):
        # Wait for byte_out_valid (uo_out[1])
        timeout = 0
        while timeout < 1000 * TIMEOUT_MULT:
            if (safe_int(dut.uo_out.value) >> 1) & 0x1:
                break
            await RisingEdge(clk)
            timeout += 1

        if timeout >= 1000 * TIMEOUT_MULT:
            dut._log.warning(f"Timeout waiting for output byte {byte_idx}")
            break

        # Read output byte from uio_out
        out_byte = safe_int(dut.uio_out.value)

        # Unpack 8 bits (LSB first)
        for bit_idx in range(8):
            if len(decoded) < len(test_bits):
                decoded.append((out_byte >> bit_idx) & 0x1)

        # Acknowledge: ui_in[4] = read_ack
        dut.ui_in.value = 0x10
        await RisingEdge(clk)
        dut.ui_in.value = 0
        await ClockCycles(clk, 5)

    # Count errors
    errors = sum(1 for a, b in zip(test_bits, decoded) if a != b)
    errors += abs(len(test_bits) - len(decoded))
    return decoded, errors


@cocotb.test()
async def test_viterbi_k5_8bit(dut):
    """Test K=7 Viterbi decoder with 8-bit pattern"""
    dut._log.info(f"=== K=5 Viterbi Decoder Test (8-bit) {'[GL]' if GL_TEST else ''} ===")
    test_bits = [1, 0, 1, 1, 0, 1, 0, 0]
    decoded, errors = await run_uart_decode_test(dut, test_bits, "8-bit")
    dut._log.info(f"Input:   {test_bits}")
    dut._log.info(f"Decoded: {decoded}")
    dut._log.info(f"Errors:  {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_k5_all_zeros(dut):
    """Test K=7 with all zeros"""
    dut._log.info("=== K=5 Viterbi Decoder Test (All Zeros) ===")
    test_bits = [0] * 8
    decoded, errors = await run_uart_decode_test(dut, test_bits, "All Zeros")
    dut._log.info(f"Errors: {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_k5_all_ones(dut):
    """Test K=7 with all ones"""
    dut._log.info("=== K=5 Viterbi Decoder Test (All Ones) ===")
    test_bits = [1] * 8
    decoded, errors = await run_uart_decode_test(dut, test_bits, "All Ones")
    dut._log.info(f"Errors: {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_k5_alternating(dut):
    """Test K=7 with alternating pattern"""
    dut._log.info("=== K=5 Viterbi Decoder Test (Alternating) ===")
    test_bits = [1, 0, 1, 0, 1, 0, 1, 0]
    decoded, errors = await run_uart_decode_test(dut, test_bits, "Alternating")
    dut._log.info(f"Errors: {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_k5_16bit(dut):
    """Test K=7 with 16-bit pattern"""
    dut._log.info("=== K=5 Viterbi Decoder Test (16-bit) ===")
    test_bits = [1, 0, 1, 0, 1, 1, 0, 0, 1, 1, 1, 0, 0, 0, 1, 0]
    decoded, errors = await run_uart_decode_test(dut, test_bits, "16-bit")
    dut._log.info(f"Errors: {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_k5_32bit(dut):
    """Test K=7 with 32-bit pattern (full frame)"""
    dut._log.info("=== K=5 Viterbi Decoder Test (32-bit Full Frame) ===")
    base = [1, 0, 1, 1, 0, 1, 0, 0]
    test_bits = base * 4
    decoded, errors = await run_uart_decode_test(dut, test_bits, "32-bit")
    dut._log.info(f"Decoded {len(decoded)} bits, Errors: {errors}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")
