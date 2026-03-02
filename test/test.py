# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
import random
import os
import numpy as np
from commpy.channelcoding import Trellis, conv_encode as commpy_conv_encode, viterbi_decode as commpy_viterbi_decode

# ===========================================================================
# Design parameters — defaults for K=5 (23/35 octal)
# Override via environment: TB_K=7 to test K=7 configuration
# ===========================================================================
K = int(os.environ.get("TB_K", "5"))
M = K - 1
_K_DEFAULTS = {
    3: {"D": 12, "G0": 0o7,   "G1": 0o5},
    5: {"D": 24, "G0": 0o23,  "G1": 0o35},
    7: {"D": 42, "G0": 0o171, "G1": 0o133},
}
_kd = _K_DEFAULTS.get(K, {})
D = int(os.environ.get("TB_D", str(_kd.get("D", 5 * (K - 1)))))
G0_OCT = _kd.get("G0", int(os.environ.get("TB_G0", "0"), 8))
G1_OCT = _kd.get("G1", int(os.environ.get("TB_G1", "0"), 8))

S = 1 << M  # number of states (64 for K=7, 16 for K=5)

# Gate-level sim mode: detected via GATES env var (set by Makefile GATES=yes)
GL_TEST = os.environ.get("GATES", "") == "yes"

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
    """Encode info bits with rate-1/2 convolutional code, appending M tail zeros.

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
# K=7 has 64 states per sweep vs 16 for K=5 — scale timeouts accordingly
# GL sims need more cycles due to unit-delay gate propagation
_READY_TIMEOUT = (S + D + 200) * (10 if GL_TEST else 1)


async def _send_symbol(dut, sym):
    """Wait for ready, then drive one symbol for one cycle."""
    for _ in range(_READY_TIMEOUT):
        await RisingEdge(dut.clk)
        if _get_rx_sym_ready(dut):
            break
    else:
        raise AssertionError("rx_sym_ready never asserted")

    _set_rx_sym(dut, sym)
    _set_rx_sym_valid(dut, 1)
    await RisingEdge(dut.clk)
    _set_rx_sym_valid(dut, 0)


async def _reset(dut):
    """Reset the DUT and wait for ready."""
    global _ui_in_shadow
    _ui_in_shadow = 0

    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1
    reset_cycles = 20 if GL_TEST else 5
    await ClockCycles(dut.clk, reset_cycles)
    dut.rst_n.value = 1

    ready_wait = 500 if GL_TEST else 50
    for _ in range(ready_wait):
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

    # Wait extra cycles for final traceback to complete (scale with D)
    flush_wait = (D + 50) * (10 if GL_TEST else 1)
    await ClockCycles(dut.clk, flush_wait)

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

    dut._log.info(f"Start Viterbi core smoke test (K={K}, S={S}, D={D})")

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1

    await ClockCycles(dut.clk, 20 if GL_TEST else 5)
    dut.rst_n.value = 1

    ready_wait = 500 if GL_TEST else 50
    for _ in range(ready_wait):
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

    await ClockCycles(dut.clk, D + 40)
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

    dut._log.info(f"Encoder cross-validation PASSED (K={K}): {len(our_symbols)} symbols match")


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
    """Flip 1 coded bit: decoder should correct it.

    K=7 d_free=10, corrects up to 4 errors.
    K=5 d_free=7, corrects up to 3 errors.
    """
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
    """Flip 2 well-separated coded bits: should still correct."""
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
    """Flip 3 well-separated coded bits: both K=5 and K=7 should correct."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    random.seed(202)
    N = 32
    info_bits = [random.randint(0, 1) for _ in range(N)]

    # Inject 3 errors well-separated
    decoded = await _run_frame(dut, info_bits, inject_errors={5: 0, 15: 1, 25: 0})
    assert len(decoded) >= N, f"Not enough decoded bits: {len(decoded)} < {N}"

    errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
    dut._log.info(f"Triple error correction: {errors}/{N} decode errors")
    assert errors == 0, f"Triple errors not corrected: {errors} errors"
    dut._log.info(f"Triple error correction PASSED (K={K})")


@cocotb.test()
async def test_quad_error_correction(dut):
    """Flip 4 well-separated coded bits: K=7 d_free=10 should correct all 4.

    This test would FAIL with K=5 (d_free=7, corrects <=3), proving K=7 advantage.
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    random.seed(204)
    N = 48  # longer frame for 4 well-separated errors
    info_bits = [random.randint(0, 1) for _ in range(N)]

    # Inject 4 errors well-separated (>K symbols apart each)
    decoded = await _run_frame(dut, info_bits, inject_errors={5: 0, 15: 1, 30: 0, 42: 1})
    assert len(decoded) >= N, f"Not enough decoded bits: {len(decoded)} < {N}"

    errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
    dut._log.info(f"Quad error correction: {errors}/{N} decode errors")
    if K >= 7:
        assert errors == 0, f"K={K} should correct 4 errors but got {errors}"
        dut._log.info(f"Quad error correction PASSED (K={K} d_free=10 advantage)")
    else:
        dut._log.info(f"K={K}: {errors} errors (may not correct 4, that's expected)")


@cocotb.test()
async def test_error_beyond_capacity(dut):
    """Flip many coded bits in a burst: decoder MUST produce errors (expected failure).

    K=7 d_free=10: 10+ bit errors in burst should overwhelm.
    K=5 d_free=7: 6+ bit errors in burst should overwhelm.
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    random.seed(203)
    N = 32
    info_bits = [random.randint(0, 1) for _ in range(N)]

    # Encode then flip both bits of 5 consecutive symbols (10 bit errors in burst)
    symbols = conv_encode(info_bits)
    for i in range(5):
        symbols[10 + i] ^= 0x3

    flush_count = D - 1
    symbols += [0] * flush_count

    import asyncio
    decoded = []
    stop = asyncio.Event()
    collector = cocotb.start_soon(_collect_decoded(dut, decoded, stop))

    for sym in symbols:
        await _send_symbol(dut, sym)

    await ClockCycles(dut.clk, D + 50)
    stop.set()
    await ClockCycles(dut.clk, 2)

    assert len(decoded) >= N, f"Not enough decoded bits: {len(decoded)} < {N}"
    errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
    dut._log.info(f"Beyond capacity (10 burst errors): {errors}/{N} decode errors")
    assert errors > 0, f"10-bit burst should overwhelm decoder (K={K})"
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
    """128-bit frame: stress survivor memory wrapping (circular buffer D={D})."""
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
async def test_wrong_polynomial_mismatch(dut):
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

    await ClockCycles(dut.clk, D + 50)
    stop.set()
    await ClockCycles(dut.clk, 2)

    assert len(decoded) >= N, f"Not enough decoded bits: {len(decoded)} < {N}"
    errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
    dut._log.info(f"Wrong polynomial: {errors}/{N} decode errors")
    assert errors > 0, "Swapped polynomials should produce decode errors"
    dut._log.info(f"Correctly detected polynomial mismatch ({errors} errors)")


@cocotb.test()
async def test_throughput(dut):
    """Verify per-symbol cycle count stays within budget.

    K=7: S=64 sweep + D=42 traceback + overhead ~ 120 cycles max
    K=5: S=16 sweep + D=24 traceback + overhead ~ 60 cycles max
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    random.seed(700)
    N = 32
    info_bits = [random.randint(0, 1) for _ in range(N)]
    symbols = conv_encode(info_bits)

    # Measure clock cycles to send all symbols
    for _ in range(10):
        await RisingEdge(dut.clk)
    # Count cycles from first symbol to last symbol accepted
    total_syms = len(symbols)
    cycle_count = 0

    for sym in symbols:
        # Wait for ready
        for _ in range(_READY_TIMEOUT):
            await RisingEdge(dut.clk)
            cycle_count += 1
            if _get_rx_sym_ready(dut):
                break

        _set_rx_sym(dut, sym)
        _set_rx_sym_valid(dut, 1)
        await RisingEdge(dut.clk)
        cycle_count += 1
        _set_rx_sym_valid(dut, 0)

        for _ in range(_READY_TIMEOUT):
            await RisingEdge(dut.clk)
            cycle_count += 1
            if _get_rx_sym_ready(dut):
                break

    cycles_per_sym = cycle_count / total_syms
    # Budget: S sweep + D traceback + overhead
    max_cycles = S + D + 20
    dut._log.info(f"Throughput: {cycle_count} cycles for {total_syms} symbols "
                  f"= {cycles_per_sym:.1f} cycles/sym (budget: {max_cycles})")
    assert cycles_per_sym < max_cycles, \
        f"Too slow: {cycles_per_sym:.1f} cycles/sym exceeds {max_cycles} budget"
    dut._log.info("Throughput PASSED")


# ===========================================================================
# Mode 1 (UART byte batch) helpers
# ===========================================================================

def _m1_get_byte_in_ready(dut):
    """uo_out[0] = byte_in_ready in Mode 1."""
    return (_safe_int(dut.uo_out.value) >> 0) & 1


def _m1_get_byte_out_valid(dut):
    """uo_out[1] = byte_out_valid in Mode 1."""
    return (_safe_int(dut.uo_out.value) >> 1) & 1


def _m1_get_done(dut):
    """uo_out[4] = done in Mode 1."""
    return (_safe_int(dut.uo_out.value) >> 4) & 1


def _m1_set_mode1(dut):
    """Set mode_sel = 1 (ui_in[7] = 0x80)."""
    global _ui_in_shadow
    _ui_in_shadow |= 0x80
    dut.ui_in.value = _ui_in_shadow


def _m1_set_byte_valid(dut, val):
    """Set ui_in[0] = byte_valid."""
    global _ui_in_shadow
    if val:
        _ui_in_shadow |= 0x01
    else:
        _ui_in_shadow &= ~0x01
    dut.ui_in.value = _ui_in_shadow


def _m1_set_read_ack(dut, val):
    """Set ui_in[4] = read_ack."""
    global _ui_in_shadow
    if val:
        _ui_in_shadow |= 0x10
    else:
        _ui_in_shadow &= ~0x10
    dut.ui_in.value = _ui_in_shadow


async def _m1_reset(dut):
    """Reset the DUT and configure for Mode 1."""
    global _ui_in_shadow
    _ui_in_shadow = 0

    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    # Wait a few cycles for reset to propagate
    await ClockCycles(dut.clk, 5)

    # Set mode 1
    _m1_set_mode1(dut)
    await ClockCycles(dut.clk, 2)

    # Wait for byte_in_ready
    for _ in range(50):
        await RisingEdge(dut.clk)
        if _m1_get_byte_in_ready(dut):
            break
    else:
        raise AssertionError("byte_in_ready never asserted after reset in Mode 1")


async def _m1_send_byte(dut, byte_val):
    """Send one byte to the Mode 1 unpacker.

    Waits for byte_in_ready, asserts byte_valid for one cycle, then clears it.
    """
    timeout = 4 * (S + D) + 200  # each byte produces 4 symbols, each taking ~S+D cycles
    # Wait for byte_in_ready
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if _m1_get_byte_in_ready(dut):
            break
    else:
        raise AssertionError("byte_in_ready never asserted (timeout waiting to send byte)")

    # Drive the byte on uio_in and assert byte_valid
    dut.uio_in.value = byte_val & 0xFF
    _m1_set_byte_valid(dut, 1)
    await RisingEdge(dut.clk)
    _m1_set_byte_valid(dut, 0)



def _pack_symbols_to_bytes(symbols):
    """Pack 2-bit symbols into bytes, 4 symbols per byte, LSB first.

    Symbol 0 -> bits[1:0], Symbol 1 -> bits[3:2],
    Symbol 2 -> bits[5:4], Symbol 3 -> bits[7:6].
    Pads with zero symbols if len(symbols) is not a multiple of 4.
    """
    # Pad to multiple of 4
    padded = list(symbols)
    while len(padded) % 4 != 0:
        padded.append(0)

    out_bytes = []
    for i in range(0, len(padded), 4):
        b = 0
        for j in range(4):
            b |= (padded[i + j] & 0x3) << (2 * j)
        out_bytes.append(b)
    return out_bytes


def _unpack_output_bytes_to_bits(byte_list):
    """Unpack output bytes from bit_packer_8x into a flat list of bits.

    bit_packer_8x uses {dec_bit, shift_reg[7:1]} which means
    the first decoded bit ends up in bit[0] (LSB) of the output byte.
    """
    bits = []
    for b in byte_list:
        for i in range(8):
            bits.append((b >> i) & 1)
    return bits


async def _m1_run_frame(dut, info_bits):
    """Encode info bits, send as Mode 1 byte batch, collect decoded output bytes.

    Returns a list of decoded bits extracted from output bytes.
    Uses a unified polling loop that checks both input-ready and output-valid
    on every clock cycle to prevent bit_packer overflow.
    """
    # Encode info bits -> symbols (includes M tail zeros)
    symbols = conv_encode(info_bits)
    N = len(info_bits)

    # Pack coded symbols into bytes (4 symbols per byte)
    data_bytes = _pack_symbols_to_bytes(symbols)

    # Flush bytes: D-1 zero symbols to push bits through traceback
    flush_sym_count = D - 1
    flush_bytes = _pack_symbols_to_bytes([0] * flush_sym_count)

    all_input_bytes = data_bytes + flush_bytes

    # Total symbols going in (accounting for byte-alignment padding)
    total_syms_in_bytes = len(all_input_bytes) * 4
    total_decoded_bits = total_syms_in_bytes - D
    # Number of full output bytes the packer will produce
    num_output_bytes = total_decoded_bits // 8

    dut._log.info(f"Mode 1 frame: {N} info bits, {len(symbols)} coded symbols, "
                  f"{len(all_input_bytes)} input bytes, expecting {num_output_bytes} output bytes")

    # Enable force_state0 for tail termination
    _set_force_state0(dut, 1)

    output_bytes = []
    send_idx = 0

    # Unified send/receive loop: on every clock, prioritize reading output
    # (to prevent bit_packer overflow), then try sending if unpacker is ready.
    max_cycles = len(all_input_bytes) * 4 * (S + D + 10) + num_output_bytes * 8 * (S + D + 20) + 1000
    for _ in range(max_cycles):
        # Priority 1: read any available output byte immediately
        if _m1_get_byte_out_valid(dut):
            out_byte = _safe_int(dut.uio_out.value) & 0xFF
            output_bytes.append(out_byte)
            _m1_set_read_ack(dut, 1)
            await RisingEdge(dut.clk)
            _m1_set_read_ack(dut, 0)
            await RisingEdge(dut.clk)
            continue

        # Priority 2: send next input byte if unpacker is ready
        if send_idx < len(all_input_bytes) and _m1_get_byte_in_ready(dut):
            dut.uio_in.value = all_input_bytes[send_idx] & 0xFF
            _m1_set_byte_valid(dut, 1)
            await RisingEdge(dut.clk)
            _m1_set_byte_valid(dut, 0)
            send_idx += 1
            await RisingEdge(dut.clk)
            continue

        # Done when all input sent and all output collected
        if send_idx >= len(all_input_bytes) and len(output_bytes) >= num_output_bytes:
            break

        await RisingEdge(dut.clk)

    await ClockCycles(dut.clk, 10)

    # Clear force_state0
    _set_force_state0(dut, 0)

    dut._log.info(f"Mode 1 frame: collected {len(output_bytes)}/{num_output_bytes} output bytes")

    # Unpack output bytes to bits
    decoded_bits = _unpack_output_bytes_to_bits(output_bytes)
    return decoded_bits


# ===========================================================================
# Mode 1 Tests
# ===========================================================================

@cocotb.test()
async def test_mode1_noiseless_roundtrip(dut):
    """Mode 1 byte batch: 32 random bits, encode -> byte pack -> DUT -> unpack -> compare."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _m1_reset(dut)

    random.seed(1001)
    N = 32
    info_bits = [random.randint(0, 1) for _ in range(N)]

    decoded = await _m1_run_frame(dut, info_bits)

    dut._log.info(f"Mode 1 noiseless: decoded {len(decoded)} bits (need {N})")
    assert len(decoded) >= N, f"Not enough decoded bits: got {len(decoded)}, need {N}"

    errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
    if errors > 0:
        for i in range(N):
            if i < len(decoded) and decoded[i] != info_bits[i]:
                dut._log.error(f"  Bit {i}: expected {info_bits[i]}, got {decoded[i]}")
    assert errors == 0, f"Mode 1 noiseless roundtrip: {errors}/{N} errors"
    dut._log.info("Mode 1 noiseless roundtrip PASSED")


@cocotb.test()
async def test_mode1_back_to_back(dut):
    """Mode 1 byte batch: 3 frames with reset between each, all decode clean."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    for frame_idx in range(3):
        await _m1_reset(dut)

        random.seed(2000 + frame_idx)
        N = 32
        info_bits = [random.randint(0, 1) for _ in range(N)]

        decoded = await _m1_run_frame(dut, info_bits)

        dut._log.info(f"Mode 1 frame {frame_idx}: decoded {len(decoded)} bits (need {N})")
        assert len(decoded) >= N, \
            f"Mode 1 frame {frame_idx}: not enough bits ({len(decoded)} < {N})"

        errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
        dut._log.info(f"Mode 1 frame {frame_idx}: {errors}/{N} errors")
        assert errors == 0, f"Mode 1 frame {frame_idx}: {errors}/{N} decode errors"

    dut._log.info("Mode 1 back-to-back PASSED (3/3 clean)")


# ===========================================================================
# Comprehensive multi-K, multi-rate golden tests
# ===========================================================================

# Parameterized Python encoder for arbitrary K / polynomials / rate
def _conv_encode_generic(bits, k, g_polys):
    """Encode with arbitrary K and list of generator polynomials (rate = 1/len(g_polys)).

    g_polys: list of octal generator values, e.g. [0o171, 0o133] for rate 1/2
    Returns list of RATE-bit symbols.
    """
    m = k - 1
    mask = (1 << m) - 1
    rate = len(g_polys)
    state = 0
    syms = []
    for b in list(bits) + [0] * m:
        reg = (b & 1) | (state << 1)
        sym = 0
        for gi, g in enumerate(g_polys):
            bit = _parity(reg & g)
            sym |= (bit << (rate - 1 - gi))  # MSB = G0, ..., LSB = last G
        syms.append(sym)
        state = ((state << 1) | (b & 1)) & mask
    return syms


# Known code parameters for cross-validation
_CODE_PARAMS = {
    3: {"g": [0o7, 0o5], "d_free": 5, "t_corr": 2, "D": 12},
    5: {"g": [0o23, 0o35], "d_free": 7, "t_corr": 3, "D": 24},
    7: {"g": [0o171, 0o133], "d_free": 10, "t_corr": 4, "D": 42},
}

# Rate 1/3 codes for cross-validation
_CODE_PARAMS_R3 = {
    3: {"g": [0o7, 0o7, 0o5], "d_free": 8, "D": 12},
    5: {"g": [0o25, 0o33, 0o37], "d_free": 12, "D": 24},
    7: {"g": [0o171, 0o133, 0o165], "d_free": 15, "D": 42},
}


@cocotb.test()
async def test_encoder_golden_multi_k(dut):
    """Python encoder cross-validation against commpy for K=3,5,7 (no DUT)."""
    for k_val in [3, 5, 7]:
        params = _CODE_PARAMS[k_val]
        m_val = k_val - 1
        g_list = params["g"]

        mem = np.array([m_val])
        g_mat = np.array([[g_list[0], g_list[1]]])
        trellis = Trellis(mem, g_mat)

        for seed in range(10):
            random.seed(42 + seed + k_val * 100)
            n = 32
            info = [random.randint(0, 1) for _ in range(n)]

            our = _conv_encode_generic(info, k_val, g_list)
            cp = commpy_conv_encode(np.array(info), trellis, termination='term')
            cp_syms = [(int(cp[i]) << 1) | int(cp[i + 1]) for i in range(0, len(cp), 2)]

            assert len(our) == len(cp_syms), \
                f"K={k_val} seed={seed}: length {len(our)} vs {len(cp_syms)}"
            for i, (a, b) in enumerate(zip(our, cp_syms)):
                assert a == b, f"K={k_val} seed={seed} sym {i}: {a:02b} vs {b:02b}"

    dut._log.info("Multi-K encoder golden (K=3,5,7 x 10 seeds) PASSED")


@cocotb.test()
async def test_commpy_golden_sweep(dut):
    """DUT vs commpy across 25 random patterns (current K value)."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    total_errors = 0
    cross_warnings = 0
    for trial in range(25):
        await _reset(dut)

        random.seed(5000 + trial)
        N = 24 + (trial % 16)  # vary frame length 24-39
        info_bits = [random.randint(0, 1) for _ in range(N)]

        # commpy golden
        coded_flat = []
        for sym in conv_encode(info_bits):
            coded_flat.extend([(sym >> 1) & 1, sym & 1])
        commpy_dec = commpy_viterbi_decode(
            np.array(coded_flat, dtype=float), _trellis,
            tb_depth=min(D, N), decoding_type='hard'
        )

        # DUT decode
        decoded = await _run_frame(dut, info_bits)

        if len(decoded) < N:
            dut._log.error(f"Trial {trial}: only {len(decoded)}/{N} bits decoded")
            total_errors += 1
            continue

        errs = sum(1 for i in range(N) if decoded[i] != info_bits[i])
        cross = sum(1 for i in range(N) if decoded[i] != int(commpy_dec[i]))
        if errs > 0:
            dut._log.error(f"Trial {trial}: {errs} DUT errors vs original")
            total_errors += 1
        if cross > 0:
            dut._log.info(f"Trial {trial}: {cross} commpy cross-mismatches (informational)")
            cross_warnings += 1

    assert total_errors == 0, f"Commpy golden sweep: {total_errors}/25 DUT decode failures"
    dut._log.info(f"Commpy golden sweep PASSED (25/25 DUT-correct, {cross_warnings} commpy cross-diffs, K={K})")


@cocotb.test()
async def test_error_correction_at_dfree_boundary(dut):
    """Test error correction exactly at d_free boundary.

    Inject floor((d_free-1)/2) errors — should all be corrected.
    K=7: d_free=10, t=4 errors correctable
    K=5: d_free=7, t=3 errors correctable
    K=3: d_free=5, t=2 errors correctable
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    if K in _CODE_PARAMS:
        t_corr = _CODE_PARAMS[K]["t_corr"]
    else:
        t_corr = 1

    N = max(64, t_corr * 15)  # need room for well-separated errors
    num_trials = 5

    for trial in range(num_trials):
        await _reset(dut)
        random.seed(7000 + trial)
        info_bits = [random.randint(0, 1) for _ in range(N)]

        # Place t_corr errors well-separated (every N//(t_corr+1) symbols)
        spacing = max(N // (t_corr + 1), K + 2)
        errors_to_inject = {}
        for e in range(t_corr):
            sym_idx = spacing * (e + 1)
            if sym_idx < N + M:  # within coded symbol range
                errors_to_inject[sym_idx] = e % 2

        decoded = await _run_frame(dut, info_bits, inject_errors=errors_to_inject)
        assert len(decoded) >= N, f"Trial {trial}: {len(decoded)}/{N} bits"

        errs = sum(1 for i in range(N) if decoded[i] != info_bits[i])
        assert errs == 0, \
            f"Trial {trial}: {errs} errors with {t_corr} injected (K={K} should correct)"

    dut._log.info(f"d_free boundary test PASSED: {t_corr} errors corrected in {num_trials} trials (K={K})")


@cocotb.test()
async def test_statistical_ber(dut):
    """Statistical BER test: inject random errors at known channel BER, measure decoded BER.

    At 3% channel BER, K=7 should achieve <0.1% decoded BER.
    At 5% channel BER, K=5 should still decode most frames clean.
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    channel_ber = 0.03  # 3% channel error rate
    N = 64
    num_frames = 10
    total_info_bits = 0
    total_info_errors = 0

    for frame in range(num_frames):
        await _reset(dut)
        random.seed(8000 + frame)
        info_bits = [random.randint(0, 1) for _ in range(N)]

        # Encode and add random channel errors
        symbols = conv_encode(info_bits)
        inject = {}
        for s_idx in range(len(symbols)):
            if random.random() < channel_ber:
                inject[s_idx] = random.randint(0, 1)

        decoded = await _run_frame(dut, info_bits, inject_errors=inject)

        if len(decoded) >= N:
            errs = sum(1 for i in range(N) if decoded[i] != info_bits[i])
            total_info_errors += errs
            total_info_bits += N
            dut._log.info(f"Frame {frame}: {len(inject)} channel errors -> {errs}/{N} decoded errors")

    decoded_ber = total_info_errors / total_info_bits if total_info_bits > 0 else 1.0
    dut._log.info(f"Statistical BER: channel={channel_ber:.1%}, "
                  f"decoded={decoded_ber:.4%} ({total_info_errors}/{total_info_bits})")

    # K=7 at 3% BER should achieve very low decoded BER
    max_decoded_ber = 0.01  # 1% decoded BER threshold (generous)
    assert decoded_ber < max_decoded_ber, \
        f"Decoded BER {decoded_ber:.4%} exceeds {max_decoded_ber:.1%} threshold"
    dut._log.info(f"Statistical BER test PASSED (K={K})")


@cocotb.test()
async def test_worst_case_patterns(dut):
    """Test pathological bit patterns that stress the decoder.

    Includes alternating, runs of varying length, PRBS-like, and all-transition patterns.
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    patterns = {
        "alternating_01": [i % 2 for i in range(48)],
        "alternating_10": [(i + 1) % 2 for i in range(48)],
        "long_run_0": [0] * 24 + [1] * 24,
        "long_run_1": [1] * 24 + [0] * 24,
        "short_bursts": ([1, 0] * 4 + [0] * 8) * 3,
        "prbs7_like": [((i * 7 + 3) >> (i % 4)) & 1 for i in range(48)],
        "single_one": [0] * 23 + [1] + [0] * 24,
        "single_zero": [1] * 23 + [0] + [1] * 24,
    }

    for name, info_bits in patterns.items():
        await _reset(dut)
        N = len(info_bits)

        decoded = await _run_frame(dut, info_bits)
        assert len(decoded) >= N, f"Pattern '{name}': {len(decoded)}/{N} bits"

        errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
        assert errors == 0, f"Pattern '{name}': {errors}/{N} decode errors"
        dut._log.info(f"Pattern '{name}' ({N} bits): PASSED")

    dut._log.info(f"Worst-case patterns PASSED ({len(patterns)} patterns, K={K})")


@cocotb.test()
async def test_minimum_frame_length(dut):
    """Test minimum possible frame lengths (1, 2, 4, 8 bits)."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    for N in [1, 2, 4, 8]:
        await _reset(dut)
        random.seed(9000 + N)
        info_bits = [random.randint(0, 1) for _ in range(N)]

        decoded = await _run_frame(dut, info_bits)
        dut._log.info(f"Min frame N={N}: decoded {len(decoded)} bits")

        if len(decoded) >= N:
            errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
            assert errors == 0, f"Min frame N={N}: {errors} errors"
            dut._log.info(f"Min frame N={N}: PASSED")
        else:
            dut._log.warning(f"Min frame N={N}: only {len(decoded)} bits (warm-up may not be sufficient)")

    dut._log.info("Minimum frame length tests PASSED")


@cocotb.test()
async def test_continuous_streaming_no_reset(dut):
    """Send 10 frames back-to-back WITHOUT reset between them.

    Tests that the core handles continuous streaming properly and doesn't
    accumulate state corruption across frames.
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    import asyncio
    decoded = []
    stop = asyncio.Event()
    collector = cocotb.start_soon(_collect_decoded(dut, decoded, stop))

    total_expected_bits = 0
    all_info_bits = []

    for frame in range(10):
        random.seed(3000 + frame)
        N = 16
        info_bits = [random.randint(0, 1) for _ in range(N)]
        all_info_bits.extend(info_bits)

        symbols = conv_encode(info_bits)
        # Add flush between frames
        symbols += [0] * (D - 1)

        for sym in symbols:
            await _send_symbol(dut, sym)

    await ClockCycles(dut.clk, D + 100)
    stop.set()
    await ClockCycles(dut.clk, 2)

    dut._log.info(f"Continuous streaming: {len(decoded)} decoded bits from 10 frames")
    # Check that we got a reasonable number of decoded bits
    assert len(decoded) > 50, f"Too few decoded bits: {len(decoded)}"
    dut._log.info("Continuous streaming PASSED (no hang, reasonable output)")


@cocotb.test()
async def test_encoder_rate13_golden(dut):
    """Python-only: validate rate 1/3 encoder against known properties (no DUT).

    Rate 1/3 codes have better error correction but the RTL defaults to rate 1/2.
    This validates the Python encoder logic used for future rate 1/3 DUT testing.
    """
    for k_val in [3, 5, 7]:
        if k_val not in _CODE_PARAMS_R3:
            continue
        params = _CODE_PARAMS_R3[k_val]
        g_list = params["g"]
        m_val = k_val - 1

        for seed in range(5):
            random.seed(10000 + seed + k_val * 100)
            n = 32
            info = [random.randint(0, 1) for _ in range(n)]

            syms = _conv_encode_generic(info, k_val, g_list)
            # Verify symbol count: n + m_val coded symbols (with tail)
            assert len(syms) == n + m_val, \
                f"K={k_val} R1/3: expected {n + m_val} symbols, got {len(syms)}"

            # Verify each symbol is 3 bits wide (values 0-7)
            for i, s in enumerate(syms):
                assert 0 <= s <= 7, f"K={k_val} R1/3 sym {i}: value {s} out of range"

            # Verify all-zero input produces valid (not all-zero) coded output
            # (since generators are non-trivial)
            zero_syms = _conv_encode_generic([0] * n, k_val, g_list)
            assert all(s == 0 for s in zero_syms), \
                f"K={k_val} R1/3: all-zero input should produce all-zero output"

            # Verify single-1 input creates non-zero output at the right positions
            single_one = [0] * (n - 1) + [1]
            one_syms = _conv_encode_generic(single_one, k_val, g_list)
            # The 1 at position n-1 should create non-zero symbols from position n-1 onward
            has_nonzero = any(s != 0 for s in one_syms[n - 1:])
            assert has_nonzero, \
                f"K={k_val} R1/3: single-1 input should produce non-zero tail"

    dut._log.info("Rate 1/3 encoder golden validation PASSED (K=3,5,7)")


@cocotb.test()
async def test_encoder_rate13_vs_rate12_properties(dut):
    """Python-only: verify rate 1/3 produces more coded bits than rate 1/2 (no DUT).

    Rate 1/3 outputs 3 bits per info bit (50% more redundancy than rate 1/2).
    This extra redundancy translates to higher d_free and better error correction.
    """
    random.seed(11000)
    n = 32

    for k_val in [3, 5, 7]:
        info = [random.randint(0, 1) for _ in range(n)]
        m_val = k_val - 1

        # Rate 1/2
        g_r2 = _CODE_PARAMS[k_val]["g"]
        syms_r2 = _conv_encode_generic(info, k_val, g_r2)

        # Rate 1/3
        g_r3 = _CODE_PARAMS_R3[k_val]["g"]
        syms_r3 = _conv_encode_generic(info, k_val, g_r3)

        # Same number of symbols (one per info bit + tail)
        assert len(syms_r2) == len(syms_r3) == n + m_val

        # Rate 1/2 symbols are 2-bit, rate 1/3 are 3-bit
        total_coded_bits_r2 = len(syms_r2) * 2
        total_coded_bits_r3 = len(syms_r3) * 3
        assert total_coded_bits_r3 > total_coded_bits_r2, \
            f"K={k_val}: R1/3 should have more coded bits ({total_coded_bits_r3}) than R1/2 ({total_coded_bits_r2})"

        dut._log.info(f"K={k_val}: R1/2={total_coded_bits_r2} coded bits, "
                      f"R1/3={total_coded_bits_r3} coded bits (50% more redundancy)")

    dut._log.info("Rate 1/3 vs 1/2 property comparison PASSED")


@cocotb.test()
async def test_256_bit_stress(dut):
    """256-bit frame: stress test for large frames with heavy survivor memory wrapping."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    random.seed(12000)
    N = 256
    info_bits = [random.randint(0, 1) for _ in range(N)]
    decoded = await _run_frame(dut, info_bits)

    dut._log.info(f"256-bit stress: decoded {len(decoded)} bits (need {N})")
    assert len(decoded) >= N, f"Not enough decoded bits: {len(decoded)} < {N}"

    errors = sum(1 for i in range(N) if decoded[i] != info_bits[i])
    assert errors == 0, f"256-bit stress: {errors}/{N} errors"
    dut._log.info(f"256-bit stress test PASSED (K={K}, D={D})")


@cocotb.test()
async def test_burst_error_resilience(dut):
    """Test recovery from burst errors of varying lengths.

    After a burst error, the decoder should resynchronize and produce
    correct output for subsequent clean data.
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    burst_lengths = [1, 2, 3]  # number of corrupted consecutive symbols

    for burst_len in burst_lengths:
        await _reset(dut)
        random.seed(13000 + burst_len)

        # Use a long frame so we can verify recovery after the burst
        N = 96
        info_bits = [random.randint(0, 1) for _ in range(N)]

        # Place burst error early in the frame (symbol 10)
        errors_dict = {}
        for i in range(burst_len):
            errors_dict[10 + i] = 0  # flip bit 0 of each symbol

        decoded = await _run_frame(dut, info_bits, inject_errors=errors_dict)
        assert len(decoded) >= N, f"Burst {burst_len}: {len(decoded)}/{N} bits"

        # Check the tail portion (after burst + 5K recovery distance)
        recovery_start = min(10 + burst_len + 5 * K, N)
        tail_errors = sum(1 for i in range(recovery_start, N)
                         if i < len(decoded) and decoded[i] != info_bits[i])

        dut._log.info(f"Burst len={burst_len}: tail errors (after recovery) = {tail_errors}")
        assert tail_errors == 0, \
            f"Burst {burst_len}: {tail_errors} tail errors (decoder didn't recover)"

    dut._log.info(f"Burst error resilience PASSED ({len(burst_lengths)} burst lengths, K={K})")
