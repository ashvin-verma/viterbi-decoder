# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


def encode_k3(bits):
    """Encode bits with K=3, G0=7, G1=5 (LSB insertion)"""
    state = 0
    symbols = []
    for bit in bits:
        r = (state << 1) | bit
        g0 = bin(r & 0b111).count('1') % 2
        g1 = bin(r & 0b101).count('1') % 2
        symbols.append((g0 << 1) | g1)
        state = ((state << 1) | bit) & 0b11
    return symbols


def safe_int(val):
    """Safely convert LogicArray to int, treating X/Z as 0"""
    try:
        return int(val)
    except ValueError:
        # Contains X or Z values, return 0
        return 0


@cocotb.test()
async def test_viterbi_decoder(dut):
    """Test Viterbi decoder K=3"""
    dut._log.info("Start Viterbi decoder test")

    # Access the DUT instance within tb
    decoder = dut.dut

    clock = Clock(decoder.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset - longer for gate-level sim
    decoder.rst_n.value = 0
    decoder.ui_in.value = 0
    decoder.uio_in.value = 0
    decoder.ena.value = 1

    await ClockCycles(decoder.clk, 10)  # Longer reset for GL
    decoder.rst_n.value = 1
    await ClockCycles(decoder.clk, 10)  # Wait for signals to settle

    # Test pattern
    test_bits = [1, 0, 1, 1, 0, 1, 0, 0]  # 8 bits
    symbols = encode_k3(test_bits)

    dut._log.info(f"Test bits: {test_bits}")
    dut._log.info(f"Encoded symbols: {symbols}")

    # Feed symbols to decoder
    for sym in symbols:
        # Wait for rx_ready
        for _ in range(100):
            out_val = safe_int(decoder.uo_out.value)
            if out_val & 0x1:  # rx_ready
                break
            await RisingEdge(decoder.clk)

        # Send symbol: ui_in = {3'b0, read_ack, start, sym[1:0], valid}
        decoder.ui_in.value = (sym << 1) | 0x1  # sym + valid
        await RisingEdge(decoder.clk)
        decoder.ui_in.value = 0
        await ClockCycles(decoder.clk, 2)

    # Start decoding
    decoder.ui_in.value = 0x08  # start=1
    await RisingEdge(decoder.clk)
    decoder.ui_in.value = 0
    await ClockCycles(decoder.clk, 2)

    # Wait for busy to clear
    for _ in range(1000):
        out_val = safe_int(decoder.uo_out.value)
        if not (out_val & 0x08):  # busy bit clear
            break
        await RisingEdge(decoder.clk)

    await ClockCycles(decoder.clk, 5)  # Extra settle time

    # Read decoded bits
    decoded = []
    for _ in range(len(test_bits)):
        # Wait for out_valid
        for _ in range(200):
            out_val = safe_int(decoder.uo_out.value)
            if out_val & 0x02:  # out_valid
                break
            await RisingEdge(decoder.clk)

        out_val = safe_int(decoder.uo_out.value)
        out_bit = (out_val >> 2) & 0x1
        decoded.append(out_bit)

        # Acknowledge
        decoder.ui_in.value = 0x10  # read_ack
        await RisingEdge(decoder.clk)
        decoder.ui_in.value = 0
        await ClockCycles(decoder.clk, 2)

    dut._log.info(f"Decoded bits: {decoded}")

    # Check results
    errors = sum(1 for a, b in zip(test_bits, decoded) if a != b)
    if errors > 0:
        raise AssertionError(f"Decode error: {errors} bits wrong")

    dut._log.info("Viterbi decoder test passed!")
