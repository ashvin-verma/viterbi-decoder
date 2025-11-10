# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


async def _send_symbol(dut, sym):
    """Wait for ready, drive a single symbol for one cycle, then release."""
    while not dut.rx_sym_ready.value:
        await RisingEdge(dut.clk)

    dut.rx_sym.value = sym & 0x3
    dut.rx_sym_valid.value = 1
    await RisingEdge(dut.clk)
    dut.rx_sym_valid.value = 0

    # Wait for the core to finish its sweep before sending the next symbol
    while not dut.rx_sym_ready.value:
        await RisingEdge(dut.clk)


@cocotb.test()
async def test_viterbi_core_smoke(dut):
    dut._log.info("Start Viterbi core smoke test")

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset and default inputs
    dut.rst.value = 1
    dut.rx_sym_valid.value = 0
    dut.rx_sym.value = 0
    dut.force_state0.value = 0

    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0

    # The controller should expose ready once reset is released.
    for _ in range(20):
        await RisingEdge(dut.clk)
        if dut.rx_sym_ready.value:
            break
    else:
        raise AssertionError("rx_sym_ready never asserted after reset")

    # Feed a short sequence of symbols (placeholder data)
    symbols = [0, 1, 2, 3]
    for sym in symbols:
        await _send_symbol(dut, sym)

    # Force traceback after a few more idle cycles
    await ClockCycles(dut.clk, 5)
    dut.force_state0.value = 1
    await ClockCycles(dut.clk, 1)
    dut.force_state0.value = 0

    await ClockCycles(dut.clk, 40)
    dut._log.info("Smoke test completed")
