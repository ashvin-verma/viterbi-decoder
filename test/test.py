# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


def encode_k3(state, bit_in):
    """Golden reference for K=3 encoder (G0=7, G1=5)"""
    new_state = (bit_in << 2) | (state >> 1)
    g0 = bin(new_state & 0b111).count('1') % 2
    g1 = bin(new_state & 0b101).count('1') % 2
    return (g0 << 1) | g1, (state & 0x3) >> 1 | (bit_in << 1)


@cocotb.test()
async def test_encoder_mode0_k3(dut):
    """Test Mode 0: Small K=3 encoder"""
    dut._log.info("Start K=3 encoder test (Mode 0)")

    # Access the DUT instance within tb
    encoder = dut.dut

    clock = Clock(encoder.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    encoder.rst_n.value = 0
    encoder.ui_in.value = 0
    encoder.uio_in.value = 0
    encoder.ena.value = 1

    await ClockCycles(encoder.clk, 5)
    encoder.rst_n.value = 1
    await ClockCycles(encoder.clk, 2)

    # Set mode to 0 (K=3 small encoder)
    encoder.ui_in.value = 0b00_000000  # mode=00
    await ClockCycles(encoder.clk, 1)

    # Test encoding a sequence
    test_bits = [1, 0, 1, 1, 0, 0, 1, 0]
    state = 0

    for i, bit in enumerate(test_bits):
        # Calculate expected output
        expected_sym, state = encode_k3(state, bit)
        
        # Drive input
        encoder.ui_in.value = 0b00_000001 | (bit << 1)  # mode=00, in_valid=1, in_bit
        await RisingEdge(encoder.clk)
        
        # Check output (convert LogicArray to int before bitwise operations)
        out_value = int(encoder.uo_out.value)
        out_valid = out_value & 0x1
        out_sym = (out_value >> 1) & 0x3
        
        if out_valid != 1:
            raise AssertionError(f"Bit {i}: out_valid={out_valid}, expected 1")
        if out_sym != expected_sym:
            raise AssertionError(f"Bit {i}: out_sym={out_sym:02b}, expected {expected_sym:02b}")
        
        # Deassert in_valid
        encoder.ui_in.value = 0b00_000000
        await RisingEdge(encoder.clk)

    dut._log.info("K=3 encoder test passed")


@cocotb.test()
async def test_encoder_mode2_uart(dut):
    """Test Mode 2: UART encoder basic functionality"""
    dut._log.info("Start UART encoder test (Mode 2)")

    # Access the DUT instance within tb
    encoder = dut.dut

    clock = Clock(encoder.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    encoder.rst_n.value = 0
    encoder.ui_in.value = 0
    encoder.uio_in.value = 0
    encoder.ena.value = 1

    await ClockCycles(encoder.clk, 5)
    encoder.rst_n.value = 1
    await ClockCycles(encoder.clk, 2)

    # Set mode to 2 (UART encoder)
    encoder.ui_in.value = 0b10_000000  # mode=10
    await ClockCycles(encoder.clk, 2)

    # Send a byte
    test_byte = 0xA5
    encoder.uio_in.value = test_byte
    encoder.ui_in.value = 0b10_000001  # mode=10, in_valid=1
    await RisingEdge(encoder.clk)
    
    encoder.ui_in.value = 0b10_000000  # Deassert in_valid
    await ClockCycles(encoder.clk, 2)

    # Wait for output valid (with timeout)
    timeout = 100
    for _ in range(timeout):
        out_value = int(encoder.uo_out.value)
        if out_value & 0x1:  # out_valid
            dut._log.info(f"Output received: 0x{out_value:02x}")
            break
        await RisingEdge(encoder.clk)
    else:
        raise AssertionError("No output received within timeout")

    dut._log.info("UART encoder test passed")

