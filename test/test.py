# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
import random
import numpy as np
from commpy.channelcoding import Trellis, conv_encode as commpy_conv_encode, viterbi_decode as commpy_viterbi_decode

# ===========================================================================
# Design parameters (must match hardened RTL in project.v)
# ===========================================================================
K = 5
M = K - 1           # = 4
D = 24
G0_OCT = 0o23       # 10011
G1_OCT = 0o35       # 11101

# commpy trellis for independent golden reference
_memory = np.array([M])
_g_matrix = np.array([[G0_OCT, G1_OCT]])
_trellis = Trellis(_memory, _g_matrix)

# ===========================================================================
# DUT I/O helpers (shadow register to avoid reading X/Z)
# ===========================================================================
_ui_in_shadow = 0


def _set_rx_sym_valid(dut, val):
    global _ui_in_shadow
    if val:
        _ui_in_shadow |= 1
    else:
        _ui_in_shadow &= ~1
    dut.ui_in.value = _ui_in_shadow


def _set_rx_sym(dut, sym):
    global _ui_in_shadow
    _ui_in_shadow = (_ui_in_shadow & ~0x6) | ((sym & 0x3) << 1)
    dut.ui_in.value = _ui_in_shadow


def _set_force_state0(dut, val):
    global _ui_in_shadow
    if val:
        _ui_in_shadow |= 0x8
    else:
        _ui_in_shadow &= ~0x8
    dut.ui_in.value = _ui_in_shadow


def _safe_int(val):
    try:
        return int(val)
    except ValueError:
        return 0


def _get_rx_sym_ready(dut):
    return (_safe_int(dut.uo_out.value) >> 2) & 1


def _get_dec_bit_valid(dut):
    return _safe_int(dut.uo_out.value) & 1


def _get_dec_bit(dut):
    return (_safe_int(dut.uo_out.value) >> 1) & 1


# ===========================================================================
# Python convolutional encoder (matches RTL expected_bits convention)
# ===========================================================================
def _parity(x):
    p = 0
    while x:
        p ^= (x & 1)
        x >>= 1
    return p


def conv_encode(bits):
    """Encode info bits with K=5 convolutional code, appending M tail zeros.

    Returns list of 2-bit symbols: sym = (c0 << 1) | c1
    where c0 = parity(reg & G0), c1 = parity(reg & G1),
    and reg = {state, bit_in} (MSB = oldest state bit, LSB = new input).
    """
    mask = (1 << M) - 1
    state = 0
    syms = []
    for b in list(bits) + [0] * M:
        reg = (b & 1) | (state << 1)
        c0 = _parity(reg & G0_OCT)
        c1 = _parity(reg & G1_OCT)
        syms.append((c0 << 1) | c1)
        state = ((state << 1) | (b & 1)) & mask
    return syms


# ===========================================================================
# DUT interaction helpers
# ===========================================================================
async def _send_symbol(dut, sym):
    """Wait for ready, drive one symbol for one cycle, wait for ready again."""
    for _ in range(200):
        await RisingEdge(dut.clk)
        if _get_rx_sym_ready(dut):
            break
    else:
        raise AssertionError("rx_sym_ready never asserted")

    _set_rx_sym(dut, sym)
    _set_rx_sym_valid(dut, 1)
    await RisingEdge(dut.clk)
    _set_rx_sym_valid(dut, 0)

    for _ in range(200):
        await RisingEdge(dut.clk)
        if _get_rx_sym_ready(dut):
            break


async def _reset(dut):
    """Reset the DUT and wait for ready."""
    global _ui_in_shadow
    _ui_in_shadow = 0

    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    for _ in range(50):
        await RisingEdge(dut.clk)
        if _get_rx_sym_ready(dut):
            break
    else:
        raise AssertionError("rx_sym_ready never asserted after reset")


async def _collect_decoded(dut, decoded_list, stop_event):
    """Background coroutine: sample dec_bit on every rising edge when valid."""
    while not stop_event.is_set():
        await RisingEdge(dut.clk)
        if _get_dec_bit_valid(dut):
            decoded_list.append(_get_dec_bit(dut))


async def _run_frame(dut, info_bits, inject_errors=None):
    """Encode info_bits, send through DUT, collect decoded output.

    inject_errors: optional dict {symbol_index: bit_position} to flip coded bits.
    Returns list of decoded bits (length may vary).
    """
    symbols = conv_encode(info_bits)

    # Apply bit errors if requested
    if inject_errors:
        for sym_idx, bit_pos in inject_errors.items():
            if 0 <= sym_idx < len(symbols):
                symbols[sym_idx] ^= (1 << bit_pos)

    # Append D-1 flush symbols (all-zero) to push all info bits through
    flush_count = D - 1
    symbols += [0] * flush_count

    # Start background collector
    import asyncio
    decoded = []
    stop = asyncio.Event()
    collector = cocotb.start_soon(_collect_decoded(dut, decoded, stop))

    # Send all symbols
    for sym in symbols:
        await _send_symbol(dut, sym)

    # Wait a few extra cycles for final traceback to complete
    await ClockCycles(dut.clk, 50)

    stop.set()
    await ClockCycles(dut.clk, 2)

    return decoded


# ===========================================================================
# Tests
# ===========================================================================

@cocotb.test()
async def test_viterbi_core_smoke(dut):
    """FSM doesn't hang: send a few symbols, verify ready cycles properly."""
    global _ui_in_shadow
    _ui_in_shadow = 0

    dut._log.info("Start Viterbi core smoke test")

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1

    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    for _ in range(50):
        await RisingEdge(dut.clk)
        if _get_rx_sym_ready(dut):
            break
    else:
        raise AssertionError("rx_sym_ready never asserted after reset")

    dut._log.info("rx_sym_ready asserted - core is ready")

    symbols = [0, 1, 2, 3]
    for sym in symbols:
        await _send_symbol(dut, sym)

    await ClockCycles(dut.clk, 5)
    _set_force_state0(dut, 1)
    await ClockCycles(dut.clk, 1)
    _set_force_state0(dut, 0)

    await ClockCycles(dut.clk, 40)
    dut._log.info("Smoke test completed")


@cocotb.test()
async def test_encoder_vs_commpy(dut):
    """Cross-validate our Python encoder against commpy (no DUT interaction)."""
    random.seed(42)
    N = 32
    info_bits = [random.randint(0, 1) for _ in range(N)]

    our_symbols = conv_encode(info_bits)

    commpy_coded = commpy_conv_encode(np.array(info_bits), _trellis, termination='term')
    commpy_symbols = []
    for i in range(0, len(commpy_coded), 2):
        commpy_symbols.append((int(commpy_coded[i]) << 1) | int(commpy_coded[i + 1]))

    assert len(our_symbols) == len(commpy_symbols), \
        f"Length mismatch: ours={len(our_symbols)}, commpy={len(commpy_symbols)}"
    for i, (ours, theirs) in enumerate(zip(our_symbols, commpy_symbols)):
        assert ours == theirs, f"Symbol {i}: ours={ours:02b}, commpy={theirs:02b}"

    dut._log.info(f"Encoder cross-validation PASSED: {len(our_symbols)} symbols match")


@cocotb.test()
async def test_all_zeros(dut):
    """Trivial sanity: all-zero input should decode to all zeros."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    N = 16
    info_bits = [0] * N
    decoded = await _run_frame(dut, info_bits)

    dut._log.info(f"All-zeros: decoded {len(decoded)} bits")

    errors = sum(1 for i in range(min(N, len(decoded))) if decoded[i] != info_bits[i])
    assert errors == 0, f"All-zeros: {errors} decode errors (expected 0)"
    dut._log.info("All-zeros PASSED")


@cocotb.test()
async def test_all_ones(dut):
    """Trivial sanity: all-one input should decode to all ones."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    N = 16
    info_bits = [1] * N
    decoded = await _run_frame(dut, info_bits)

    dut._log.info(f"All-ones: decoded {len(decoded)} bits")

    errors = sum(1 for i in range(min(N, len(decoded))) if decoded[i] != info_bits[i])
    assert errors == 0, f"All-ones: {errors} decode errors (expected 0)"
    dut._log.info("All-ones PASSED")


@cocotb.test()
async def test_noiseless_roundtrip(dut):
    """Core correctness: 32 random bits, encode -> DUT -> compare, 0 errors."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    random.seed(123)
    N = 32
    info_bits = [random.randint(0, 1) for _ in range(N)]
    decoded = await _run_frame(dut, info_bits)

    dut._log.info(f"Noiseless roundtrip: decoded {len(decoded)} bits (need {N})")
    assert len(decoded) >= N, f"Not enough decoded bits: got {len(decoded)}, need {N}"

    errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
    if errors > 0:
        for i in range(N):
            if i < len(decoded) and decoded[i] != info_bits[i]:
                dut._log.error(f"  Bit {i}: expected {info_bits[i]}, got {decoded[i]}")
    assert errors == 0, f"Noiseless roundtrip: {errors}/{N} errors"
    dut._log.info("Noiseless roundtrip PASSED")


@cocotb.test()
async def test_commpy_golden_comparison(dut):
    """Definitive golden test: DUT output matches commpy's Viterbi decoder."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    random.seed(999)
    N = 32
    info_bits = [random.randint(0, 1) for _ in range(N)]

    # Encode with our encoder
    symbols = conv_encode(info_bits)

    # Get commpy's decode of the same coded stream
    coded_flat = []
    for sym in symbols:
        coded_flat.extend([(sym >> 1) & 1, sym & 1])
    commpy_decoded = commpy_viterbi_decode(
        np.array(coded_flat, dtype=float), _trellis,
        tb_depth=D, decoding_type='hard'
    )

    # Verify commpy matches original (sanity)
    commpy_match = all(int(commpy_decoded[i]) == info_bits[i] for i in range(N))
    assert commpy_match, "commpy itself didn't decode correctly (test infrastructure bug)"

    # Get DUT's decode
    decoded = await _run_frame(dut, info_bits)
    assert len(decoded) >= N, f"Not enough DUT decoded bits: {len(decoded)} < {N}"

    # Both should match
    dut_errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
    assert dut_errors == 0, f"DUT vs golden: {dut_errors}/{N} errors"

    # DUT should also match commpy
    cross_errors = sum(1 for i in range(N) if decoded[i] != int(commpy_decoded[i]))
    assert cross_errors == 0, f"DUT vs commpy: {cross_errors}/{N} mismatches"

    dut._log.info("Commpy golden comparison PASSED")


@cocotb.test()
async def test_single_error_correction(dut):
    """Flip 1 coded bit: decoder should correct it (d_free=7, t=3)."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    random.seed(200)
    N = 32
    info_bits = [random.randint(0, 1) for _ in range(N)]

    # Inject 1 error at symbol 10, bit 0
    decoded = await _run_frame(dut, info_bits, inject_errors={10: 0})
    assert len(decoded) >= N, f"Not enough decoded bits: {len(decoded)} < {N}"

    errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
    dut._log.info(f"Single error correction: {errors}/{N} decode errors")
    assert errors == 0, f"Single error not corrected: {errors} errors"
    dut._log.info("Single error correction PASSED")


@cocotb.test()
async def test_double_error_correction(dut):
    """Flip 2 well-separated coded bits: should still correct (d_free=7)."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    random.seed(201)
    N = 32
    info_bits = [random.randint(0, 1) for _ in range(N)]

    # Inject 2 errors separated by 10 symbols
    decoded = await _run_frame(dut, info_bits, inject_errors={8: 0, 18: 1})
    assert len(decoded) >= N, f"Not enough decoded bits: {len(decoded)} < {N}"

    errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
    dut._log.info(f"Double error correction: {errors}/{N} decode errors")
    assert errors == 0, f"Double errors not corrected: {errors} errors"
    dut._log.info("Double error correction PASSED")


@cocotb.test()
async def test_triple_error_correction(dut):
    """Flip 3 well-separated coded bits: K=5 d_free=7 should correct all 3.

    This test would FAIL with K=3 (d_free=5, corrects <=2), proving the upgrade value.
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    random.seed(202)
    N = 32
    info_bits = [random.randint(0, 1) for _ in range(N)]

    # Inject 3 errors well-separated (>5K symbols apart each)
    decoded = await _run_frame(dut, info_bits, inject_errors={5: 0, 15: 1, 25: 0})
    assert len(decoded) >= N, f"Not enough decoded bits: {len(decoded)} < {N}"

    errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
    dut._log.info(f"Triple error correction: {errors}/{N} decode errors")
    assert errors == 0, f"Triple errors not corrected: {errors} errors"
    dut._log.info("Triple error correction PASSED (K=5 advantage demonstrated)")


@cocotb.test()
async def test_error_beyond_capacity(dut):
    """Flip 6 coded bits in a burst: decoder MUST produce errors (expected failure)."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    random.seed(203)
    N = 32
    info_bits = [random.randint(0, 1) for _ in range(N)]

    # Encode then flip both bits of 3 consecutive symbols (6 bit errors in burst)
    symbols = conv_encode(info_bits)
    symbols[10] ^= 0x3
    symbols[11] ^= 0x3
    symbols[12] ^= 0x3

    flush_count = D - 1
    symbols += [0] * flush_count

    import asyncio
    decoded = []
    stop = asyncio.Event()
    collector = cocotb.start_soon(_collect_decoded(dut, decoded, stop))

    for sym in symbols:
        await _send_symbol(dut, sym)

    await ClockCycles(dut.clk, 50)
    stop.set()
    await ClockCycles(dut.clk, 2)

    assert len(decoded) >= N, f"Not enough decoded bits: {len(decoded)} < {N}"
    errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
    dut._log.info(f"Beyond capacity (6 burst errors): {errors}/{N} decode errors")
    assert errors > 0, "6-bit burst should overwhelm decoder (d_free=7, t=3)"
    dut._log.info(f"Correctly produced {errors} errors (decoder limit confirmed)")


@cocotb.test()
async def test_multiple_frames(dut):
    """Send 3 back-to-back frames with reset between them, all decode clean."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    for frame_idx in range(3):
        await _reset(dut)

        random.seed(300 + frame_idx)
        N = 16
        info_bits = [random.randint(0, 1) for _ in range(N)]
        decoded = await _run_frame(dut, info_bits)

        assert len(decoded) >= N, \
            f"Frame {frame_idx}: not enough bits ({len(decoded)} < {N})"

        errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
        dut._log.info(f"Frame {frame_idx}: {errors}/{N} errors")
        assert errors == 0, f"Frame {frame_idx}: {errors} decode errors"

    dut._log.info("Multiple frames PASSED (3/3 clean)")


@cocotb.test()
async def test_long_frame(dut):
    """128-bit frame: stress survivor memory wrapping (circular buffer D=24)."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    random.seed(500)
    N = 128
    info_bits = [random.randint(0, 1) for _ in range(N)]
    decoded = await _run_frame(dut, info_bits)

    dut._log.info(f"Long frame: decoded {len(decoded)} bits (need {N})")
    assert len(decoded) >= N, f"Not enough decoded bits: {len(decoded)} < {N}"

    errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
    assert errors == 0, f"Long frame: {errors}/{N} errors"
    dut._log.info(f"Long frame PASSED ({N} bits, 0 errors)")


@cocotb.test()
async def test_wrong_polynomial_expected_failure(dut):
    """Feed symbols encoded with wrong polynomials: decoder MUST produce errors."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    random.seed(600)
    N = 32
    info_bits = [random.randint(0, 1) for _ in range(N)]

    # Encode with wrong polynomials (swapped G0/G1)
    mask = (1 << M) - 1
    state = 0
    wrong_syms = []
    for b in list(info_bits) + [0] * M:
        reg = (b & 1) | (state << 1)
        # Swap c0/c1 to create wrong encoding
        c0 = _parity(reg & G1_OCT)  # wrong: using G1 for c0
        c1 = _parity(reg & G0_OCT)  # wrong: using G0 for c1
        wrong_syms.append((c0 << 1) | c1)
        state = ((state << 1) | (b & 1)) & mask

    flush_count = D - 1
    wrong_syms += [0] * flush_count

    import asyncio
    decoded = []
    stop = asyncio.Event()
    collector = cocotb.start_soon(_collect_decoded(dut, decoded, stop))

    for sym in wrong_syms:
        await _send_symbol(dut, sym)

    await ClockCycles(dut.clk, 50)
    stop.set()
    await ClockCycles(dut.clk, 2)

    assert len(decoded) >= N, f"Not enough decoded bits: {len(decoded)} < {N}"
    errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
    dut._log.info(f"Wrong polynomial: {errors}/{N} decode errors")
    assert errors > 0, "Swapped polynomials should produce decode errors"
    dut._log.info(f"Correctly detected polynomial mismatch ({errors} errors)")


@cocotb.test()
async def test_throughput(dut):
    """Verify per-symbol cycle count stays within budget."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    random.seed(700)
    N = 32
    info_bits = [random.randint(0, 1) for _ in range(N)]
    symbols = conv_encode(info_bits)

    # Measure clock cycles to send all symbols
    cycle_start = 0
    for _ in range(10):
        await RisingEdge(dut.clk)
    # Count cycles from first symbol to last symbol accepted
    total_syms = len(symbols)
    cycle_count = 0

    for sym in symbols:
        sym_cycles = 0
        # Wait for ready
        for _ in range(200):
            await RisingEdge(dut.clk)
            cycle_count += 1
            sym_cycles += 1
            if _get_rx_sym_ready(dut):
                break

        _set_rx_sym(dut, sym)
        _set_rx_sym_valid(dut, 1)
        await RisingEdge(dut.clk)
        cycle_count += 1
        _set_rx_sym_valid(dut, 0)

        for _ in range(200):
            await RisingEdge(dut.clk)
            cycle_count += 1
            if _get_rx_sym_ready(dut):
                break

    cycles_per_sym = cycle_count / total_syms
    # Budget: S(=16) sweep + D(=24) traceback + overhead ~= 50 cycles max
    max_cycles = 60
    dut._log.info(f"Throughput: {cycle_count} cycles for {total_syms} symbols "
                  f"= {cycles_per_sym:.1f} cycles/sym (budget: {max_cycles})")
    assert cycles_per_sym < max_cycles, \
        f"Too slow: {cycles_per_sym:.1f} cycles/sym exceeds {max_cycles} budget"
    dut._log.info("Throughput PASSED")
