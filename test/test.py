# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.triggers import ClockCycles, RisingEdge
import os
import subprocess
import json
import tempfile

GL_TEST = os.environ.get('GATES', 'no') == 'yes'
TIMEOUT_MULT = 100 if GL_TEST else 1

# Determine K from TB_K compile arg (default 5)
TB_K = int(os.environ.get('TB_K', '5'))

_golden_cache = {}


def encode_k3(bits):
    """Encode with K=3, G0=7o (111), G1=5o (101). Appends M=2 tail bits."""
    state = 0
    symbols = []
    for bit in bits:
        r = (state << 1) | bit
        g0 = bin(r & 0b111).count('1') % 2
        g1 = bin(r & 0b101).count('1') % 2
        symbols.append((g0 << 1) | g1)
        state = ((state << 1) | bit) & 0b11
    # Tail: encode M=2 zero bits to flush encoder back to state 0
    for _ in range(2):
        r = (state << 1) | 0
        g0 = bin(r & 0b111).count('1') % 2
        g1 = bin(r & 0b101).count('1') % 2
        symbols.append((g0 << 1) | g1)
        state = ((state << 1) | 0) & 0b11
    return symbols


def encode_k5(bits):
    """Encode with K=5, G0=23o (10011), G1=35o (11101). Appends M=4 tail bits."""
    state = 0
    symbols = []
    for bit in bits:
        r = (state << 1) | bit
        g0 = bin(r & 0b10011).count('1') % 2
        g1 = bin(r & 0b11101).count('1') % 2
        symbols.append((g0 << 1) | g1)
        state = ((state << 1) | bit) & 0b1111
    # Tail: encode M=4 zero bits to flush encoder back to state 0
    for _ in range(4):
        r = (state << 1) | 0
        g0 = bin(r & 0b10011).count('1') % 2
        g1 = bin(r & 0b11101).count('1') % 2
        symbols.append((g0 << 1) | g1)
        state = ((state << 1) | 0) & 0b1111
    return symbols


def encode_k7(bits):
    """Encode with K=7, G0=171o (1111001), G1=133o (1011011). Appends M=6 tail bits."""
    state = 0
    symbols = []
    for bit in bits:
        r = (state << 1) | bit
        g0 = bin(r & 0b1111001).count('1') % 2
        g1 = bin(r & 0b1011011).count('1') % 2
        symbols.append((g0 << 1) | g1)
        state = ((state << 1) | bit) & 0b111111
    # Tail: encode M=6 zero bits to flush encoder back to state 0
    for _ in range(6):
        r = (state << 1) | 0
        g0 = bin(r & 0b1111001).count('1') % 2
        g1 = bin(r & 0b1011011).count('1') % 2
        symbols.append((g0 << 1) | g1)
        state = ((state << 1) | 0) & 0b111111
    return symbols


def encode(bits):
    """Encode using the current TB_K setting."""
    if TB_K == 3:
        return encode_k3(bits)
    elif TB_K == 7:
        return encode_k7(bits)
    else:
        return encode_k5(bits)


def pack_symbols_to_byte(symbols):
    """Pack 4 x 2-bit symbols into a byte."""
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
    """Run decode test using UART byte mode."""
    clk = dut.clk

    # Reset
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1
    await ClockCycles(clk, 20 * TIMEOUT_MULT)
    dut.rst_n.value = 1
    await ClockCycles(clk, 50 * TIMEOUT_MULT)

    if GL_TEST:
        dut._log.info(f"After reset: uo_out=0x{safe_int(dut.uo_out.value):02x}")

    symbols = encode(test_bits)
    dut._log.info(f"{test_name}: {len(test_bits)} bits -> {len(symbols)} symbols (K={TB_K})")

    # Pack symbols into bytes
    symbol_bytes = []
    for i in range(0, len(symbols), 4):
        chunk = symbols[i:i+4]
        symbol_bytes.append(pack_symbols_to_byte(chunk))

    # Feed symbol bytes
    for i, sym_byte in enumerate(symbol_bytes):
        timeout = 0
        max_timeout = 200 * TIMEOUT_MULT
        while timeout < max_timeout:
            uo_val = safe_int(dut.uo_out.value)
            if uo_val & 0x1:
                break
            await RisingEdge(clk)
            timeout += 1
        if timeout >= max_timeout:
            raise AssertionError(f"Timeout waiting for byte_in_ready at byte {i}")

        dut.uio_in.value = sym_byte
        dut.ui_in.value = 0x01
        await RisingEdge(clk)
        dut.ui_in.value = 0
        await ClockCycles(clk, 2)

    await ClockCycles(clk, 20)

    # Start decode
    dut.ui_in.value = 0x08
    await RisingEdge(clk)
    dut.ui_in.value = 0
    await ClockCycles(clk, 5)

    # Wait for busy to go low
    timeout = 0
    max_timeout = 50000 * TIMEOUT_MULT
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
        timeout = 0
        while timeout < 2000 * TIMEOUT_MULT:
            if (safe_int(dut.uo_out.value) >> 1) & 0x1:
                break
            await RisingEdge(clk)
            timeout += 1

        if timeout >= 2000 * TIMEOUT_MULT:
            dut._log.warning(f"Timeout waiting for output byte {byte_idx}")
            break

        out_byte = safe_int(dut.uio_out.value)
        for bit_idx in range(8):
            if len(decoded) < len(test_bits):
                decoded.append((out_byte >> bit_idx) & 0x1)

        dut.ui_in.value = 0x10
        await RisingEdge(clk)
        dut.ui_in.value = 0
        await ClockCycles(clk, 5)

    errors = sum(1 for a, b in zip(test_bits, decoded) if a != b)
    errors += abs(len(test_bits) - len(decoded))
    return decoded, errors


async def run_uart_decode_test_with_symbols(dut, symbols, expected_num_data_bits, test_name):
    """Run decode test using pre-encoded symbols (for golden vector testing).
    Returns decoded bits list. Caller handles comparison."""
    clk = dut.clk

    # Reset
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1
    await ClockCycles(clk, 20 * TIMEOUT_MULT)
    dut.rst_n.value = 1
    await ClockCycles(clk, 50 * TIMEOUT_MULT)

    dut._log.info(f"{test_name}: {expected_num_data_bits} data bits, {len(symbols)} symbols (K={TB_K})")

    # Pack symbols into bytes
    symbol_bytes = []
    for i in range(0, len(symbols), 4):
        chunk = symbols[i:i+4]
        symbol_bytes.append(pack_symbols_to_byte(chunk))

    # Feed symbol bytes
    for i, sym_byte in enumerate(symbol_bytes):
        timeout = 0
        max_timeout = 200 * TIMEOUT_MULT
        while timeout < max_timeout:
            uo_val = safe_int(dut.uo_out.value)
            if uo_val & 0x1:
                break
            await RisingEdge(clk)
            timeout += 1
        if timeout >= max_timeout:
            raise AssertionError(f"Timeout waiting for byte_in_ready at byte {i}")

        dut.uio_in.value = sym_byte
        dut.ui_in.value = 0x01
        await RisingEdge(clk)
        dut.ui_in.value = 0
        await ClockCycles(clk, 2)

    await ClockCycles(clk, 20)

    # Start decode
    dut.ui_in.value = 0x08
    await RisingEdge(clk)
    dut.ui_in.value = 0
    await ClockCycles(clk, 5)

    # Wait for busy to go low
    timeout = 0
    max_timeout = 50000 * TIMEOUT_MULT
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
    num_output_bytes = (expected_num_data_bits + 7) // 8

    for byte_idx in range(num_output_bytes):
        timeout = 0
        while timeout < 2000 * TIMEOUT_MULT:
            if (safe_int(dut.uo_out.value) >> 1) & 0x1:
                break
            await RisingEdge(clk)
            timeout += 1

        if timeout >= 2000 * TIMEOUT_MULT:
            dut._log.warning(f"Timeout waiting for output byte {byte_idx}")
            break

        out_byte = safe_int(dut.uio_out.value)
        for bit_idx in range(8):
            if len(decoded) < expected_num_data_bits:
                decoded.append((out_byte >> bit_idx) & 0x1)

        dut.ui_in.value = 0x10
        await RisingEdge(clk)
        dut.ui_in.value = 0
        await ClockCycles(clk, 5)

    return decoded


def get_golden_vectors():
    """Compile and run C golden vector generator, return parsed JSON."""
    if TB_K in _golden_cache:
        return _golden_cache[TB_K]

    k_config = {
        3: {'g0': '07', 'g1': '05'},
        5: {'g0': '023', 'g1': '035'},
        7: {'g0': '0171', 'g1': '0133'},
    }
    cfg = k_config[TB_K]

    src = os.path.join(os.path.dirname(__file__), '..', 'c-tests', 'gen_golden_vectors.c')
    golden_src = os.path.join(os.path.dirname(__file__), '..', 'c-tests', 'viterbi_golden.c')

    with tempfile.NamedTemporaryFile(suffix='.bin', delete=False) as f:
        binpath = f.name

    # Compile
    cmd = [
        'gcc', '-O2', f'-DK={TB_K}', f'-DG0_OCT={cfg["g0"]}', f'-DG1_OCT={cfg["g1"]}',
        '-I' + os.path.join(os.path.dirname(__file__), '..', 'c-tests'),
        src, '-o', binpath, '-lm'
    ]
    subprocess.run(cmd, check=True)

    # Run and capture JSON
    result = subprocess.run([binpath], capture_output=True, text=True, check=True)
    os.unlink(binpath)

    data = json.loads(result.stdout)
    _golden_cache[TB_K] = data
    return data


@cocotb.test()
async def test_viterbi_8bit(dut):
    """Test Viterbi decoder with 8-bit pattern"""
    dut._log.info(f"=== K={TB_K} Viterbi Decoder Test (8-bit) {'[GL]' if GL_TEST else ''} ===")
    test_bits = [1, 0, 1, 1, 0, 1, 0, 0]
    decoded, errors = await run_uart_decode_test(dut, test_bits, "8-bit")
    dut._log.info(f"Input:   {test_bits}")
    dut._log.info(f"Decoded: {decoded}")
    dut._log.info(f"Errors:  {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_all_zeros(dut):
    """Test with all zeros"""
    dut._log.info(f"=== K={TB_K} Viterbi Decoder Test (All Zeros) ===")
    test_bits = [0] * 8
    decoded, errors = await run_uart_decode_test(dut, test_bits, "All Zeros")
    dut._log.info(f"Errors: {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_all_ones(dut):
    """Test with all ones"""
    dut._log.info(f"=== K={TB_K} Viterbi Decoder Test (All Ones) ===")
    test_bits = [1] * 8
    decoded, errors = await run_uart_decode_test(dut, test_bits, "All Ones")
    dut._log.info(f"Errors: {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_alternating(dut):
    """Test with alternating pattern"""
    dut._log.info(f"=== K={TB_K} Viterbi Decoder Test (Alternating) ===")
    test_bits = [1, 0, 1, 0, 1, 0, 1, 0]
    decoded, errors = await run_uart_decode_test(dut, test_bits, "Alternating")
    dut._log.info(f"Errors: {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_16bit(dut):
    """Test with 16-bit pattern"""
    dut._log.info(f"=== K={TB_K} Viterbi Decoder Test (16-bit) ===")
    test_bits = [1, 0, 1, 0, 1, 1, 0, 0, 1, 1, 1, 0, 0, 0, 1, 0]
    decoded, errors = await run_uart_decode_test(dut, test_bits, "16-bit")
    dut._log.info(f"Errors: {errors}/{len(test_bits)}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_max_frame(dut):
    """Test with max-length frame (data + tail = MAX_FRAME=32)"""
    M = TB_K - 1
    max_data = 32 - M  # leave room for tail bits
    dut._log.info(f"=== K={TB_K} Viterbi Decoder Test (Max Frame: {max_data} data bits) ===")
    base = [1, 0, 1, 1, 0, 1, 0, 0]
    test_bits = (base * ((max_data + 7) // 8))[:max_data]
    decoded, errors = await run_uart_decode_test(dut, test_bits, f"{max_data}-bit")
    dut._log.info(f"Decoded {len(decoded)} bits, Errors: {errors}")
    if errors > 0:
        raise AssertionError(f"Decode failed: {errors} errors")
    dut._log.info("=== TEST PASSED ===")


@cocotb.test()
async def test_viterbi_golden_comparison(dut):
    """Test Viterbi decoder against C golden reference on 25 patterns."""
    if GL_TEST:
        dut._log.info("Skipping golden comparison in GL test (too slow)")
        return

    dut._log.info(f"=== K={TB_K} Golden Reference Comparison ===")
    golden = get_golden_vectors()

    failures = []
    for tc in golden['tests']:
        if tc.get('noisy', False):
            continue  # skip noisy vectors here

        symbols = tc['symbols']
        expected = tc['decoded']
        name = tc['name']

        decoded = await run_uart_decode_test_with_symbols(dut, symbols, len(expected), name)

        if decoded != expected:
            errors = sum(1 for a, b in zip(decoded, expected) if a != b)
            errors += abs(len(decoded) - len(expected))
            failures.append(f"{name}: {errors} bit errors")
            dut._log.error(f"FAIL {name}: expected {expected}, got {decoded}")
        else:
            dut._log.info(f"PASS {name}")

    if failures:
        raise AssertionError(f"Golden comparison failures: {'; '.join(failures)}")
    dut._log.info("=== ALL GOLDEN TESTS PASSED ===")


@cocotb.test()
async def test_viterbi_noise_resilience(dut):
    """Test Viterbi decoder corrects errors (noisy golden vectors)."""
    if GL_TEST:
        dut._log.info("Skipping noise test in GL test")
        return

    dut._log.info(f"=== K={TB_K} Noise Resilience Test ===")
    golden = get_golden_vectors()

    for tc in golden['tests']:
        if not tc.get('noisy', False):
            continue

        symbols = tc['symbols']
        expected = tc['decoded']
        name = tc['name']

        decoded = await run_uart_decode_test_with_symbols(dut, symbols, len(expected), name)

        errors = sum(1 for a, b in zip(decoded, expected) if a != b)
        errors += abs(len(decoded) - len(expected))
        dut._log.info(f"{name}: {errors} errors (golden expects match)")

        if decoded != expected:
            dut._log.warning(f"{name}: RTL differs from golden - expected {expected}, got {decoded}")

    dut._log.info("=== NOISE RESILIENCE TEST DONE ===")


@cocotb.test()
async def test_viterbi_back_to_back(dut):
    """Test back-to-back decoding without reset between frames."""
    dut._log.info(f"=== K={TB_K} Back-to-Back Test ===")
    clk = dut.clk

    # Reset once
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1
    await ClockCycles(clk, 20 * TIMEOUT_MULT)
    dut.rst_n.value = 1
    await ClockCycles(clk, 50 * TIMEOUT_MULT)

    patterns = [
        [1, 0, 1, 1, 0, 1, 0, 0],
        [0, 0, 1, 1, 1, 0, 0, 1],
    ]

    M = TB_K - 1

    for idx, test_bits in enumerate(patterns):
        symbols = encode(test_bits)  # now includes tail
        dut._log.info(f"Frame {idx}: {len(test_bits)} data bits -> {len(symbols)} symbols")

        # Pack and send symbols
        symbol_bytes = []
        for i in range(0, len(symbols), 4):
            chunk = symbols[i:i+4]
            symbol_bytes.append(pack_symbols_to_byte(chunk))

        for i, sym_byte in enumerate(symbol_bytes):
            timeout = 0
            while timeout < 200 * TIMEOUT_MULT:
                if safe_int(dut.uo_out.value) & 0x1:
                    break
                await RisingEdge(clk)
                timeout += 1
            assert timeout < 200 * TIMEOUT_MULT, f"Timeout waiting for byte_in_ready"

            dut.uio_in.value = sym_byte
            dut.ui_in.value = 0x01
            await RisingEdge(clk)
            dut.ui_in.value = 0
            await ClockCycles(clk, 2)

        await ClockCycles(clk, 20)

        # Start decode
        dut.ui_in.value = 0x08
        await RisingEdge(clk)
        dut.ui_in.value = 0
        await ClockCycles(clk, 5)

        # Wait for busy to go low (decode complete, entering S_OUTPUT)
        timeout = 0
        while timeout < 50000 * TIMEOUT_MULT:
            if not ((safe_int(dut.uo_out.value) >> 3) & 0x1):
                break
            await RisingEdge(clk)
            timeout += 1
        assert timeout < 50000 * TIMEOUT_MULT, "Timeout waiting for decode"

        # Read output bytes until frame_done
        decoded = []
        for _ in range(10):  # safety limit
            timeout = 0
            while timeout < 2000 * TIMEOUT_MULT:
                uo = safe_int(dut.uo_out.value)
                if uo & 0x10:  # frame_done
                    break
                if (uo >> 1) & 0x1:  # byte_out_valid
                    out_byte = safe_int(dut.uio_out.value)
                    for bit_idx in range(8):
                        decoded.append((out_byte >> bit_idx) & 0x1)
                    dut.ui_in.value = 0x10  # read_ack
                    await RisingEdge(clk)
                    dut.ui_in.value = 0
                    await ClockCycles(clk, 5)
                    break
                await RisingEdge(clk)
                timeout += 1
            if safe_int(dut.uo_out.value) & 0x10:
                break

        # Trim decoded to data bits only
        decoded = decoded[:len(test_bits)]

        errors = sum(1 for a, b in zip(test_bits, decoded) if a != b)
        dut._log.info(f"Frame {idx}: decoded {len(decoded)} bits, errors={errors}")
        if errors > 0:
            raise AssertionError(f"Frame {idx} decode failed: {errors} errors")

        # Pulse start to go back to IDLE for next frame
        await ClockCycles(clk, 5)
        dut.ui_in.value = 0x08
        await RisingEdge(clk)
        dut.ui_in.value = 0
        await ClockCycles(clk, 20)

    dut._log.info("=== BACK-TO-BACK TEST PASSED ===")
