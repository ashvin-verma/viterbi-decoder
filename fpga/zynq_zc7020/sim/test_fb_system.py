"""cocotb system test: frame decode + trellis capture + BER tester registers.

Uses the web server's own encoder / software Viterbi as the reference, so this
checks the exact data path the website uses (minus JTAG).
"""
import os
import random
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "web"))
import server as S  # noqa: E402

K = int(os.environ.get("TB_K", "7"))
CFG = S.K_CONFIGS[K]
S.set_k(K)


# All bus sampling/driving happens on the falling edge: the DUT is purely
# posedge, so values are settled and there are no NBA-ordering races.
async def axi_write(dut, addr, data):
    dut.awaddr.value = addr
    dut.awvalid.value = 1
    dut.wdata.value = data
    dut.wstrb.value = 0xF
    dut.wvalid.value = 1
    aw = w = False
    while not (aw and w):
        await FallingEdge(dut.clk)
        if int(dut.awready.value):
            aw = True
            dut.awvalid.value = 0
        if int(dut.wready.value):
            w = True
            dut.wvalid.value = 0
    while True:
        await FallingEdge(dut.clk)
        if int(dut.bvalid.value):
            break   # bready is held high; BVALID clears on the next posedge


async def axi_read(dut, addr):
    dut.araddr.value = addr
    dut.arvalid.value = 1
    while True:
        await FallingEdge(dut.clk)
        if int(dut.arready.value):
            dut.arvalid.value = 0
            break
    while True:
        await FallingEdge(dut.clk)
        if int(dut.rvalid.value):
            # Unwritten BRAM bytes are X in sim but 0 on the FPGA (power-on init)
            bits = str(dut.rdata.value).lower().replace("x", "0").replace("z", "0")
            return int(bits, 2)   # rready held high


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for sig in ("awvalid", "wvalid", "arvalid"):
        getattr(dut, sig).value = 0
    dut.bready.value = 1
    dut.rready.value = 1
    dut.awaddr.value = 0
    dut.araddr.value = 0
    dut.wdata.value = 0
    dut.wstrb.value = 0
    dut.resetn.value = 0
    for _ in range(10):
        await RisingEdge(dut.clk)
    dut.resetn.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)


async def decode_frame(dut, input_bytes):
    await axi_write(dut, 0x008, len(input_bytes))
    for w in range((len(input_bytes) + 3) // 4):
        word = 0
        for b in range(4):
            i = w * 4 + b
            if i < len(input_bytes):
                word |= input_bytes[i] << (8 * b)
        await axi_write(dut, 0x400 + 4 * w, word)
    await axi_write(dut, 0x000, 1)
    while True:
        st = await axi_read(dut, 0x004)
        if st & 2:
            break
        await ClockCycles(dut.clk, 500)
    n_out = (st >> 8) & 0xFF
    out = []
    for w in range((n_out + 3) // 4):
        v = await axi_read(dut, 0x800 + 4 * w)
        for b in range(4):
            if len(out) < n_out:
                out.append((v >> (8 * b)) & 0xFF)
    return out


@cocotb.test()
async def test_hw_config(dut):
    await setup(dut)
    v = await axi_read(dut, 0x014)
    assert v & 0xF == K
    assert (v >> 4) & 0xFF == CFG["D"]
    assert (v >> 12) & 0x1FF == CFG["G0"]
    assert (v >> 21) & 0x1FF == CFG["G1"]
    assert (v >> 30) == 1


@cocotb.test()
async def test_decode_and_trellis_capture(dut):
    await setup(dut)
    random.seed(1234)
    n_states = 1 << (K - 1)
    for msg, rate in (("Hi FPGA!", 0.0), ("Viterbi trellis", 0.06)):
        info = S.bytes_to_bits_msb(list(msg.encode()))
        syms = S.conv_encode(info)
        noisy, _ = S.inject_errors(syms, rate)
        data_bytes = S.pack_symbols_to_bytes(noisy)
        flush = S.pack_symbols_to_bytes([0] * (CFG["D"] - 1))
        frame = data_bytes + flush
        out = await decode_frame(dut, frame)
        dec_bits = S.unpack_decoded_bytes(out)[:len(info)]
        assert S.bits_to_bytes_msb(dec_bits) == list(msg.encode()), f"decode mismatch for {msg!r}"

        # --- trellis capture ---
        n_entries = (await axi_read(dut, 0x00C)) & 0x1FFFF
        n_steps = (await axi_read(dut, 0x010)) & 0x7FF
        total_syms = len(frame) * 4
        assert n_steps == total_syms, (n_steps, total_syms)
        assert n_entries == total_syms * n_states, (n_entries, total_syms * n_states)

        all_syms = noisy + [0] * (total_syms - len(noisy))
        _, sw = S.software_decode_with_trellis(all_syms)

        check_steps = min(total_syms, 40)
        for t in range(check_steps):
            hw_pm = []
            hw_sv = []
            for s in range(n_states):
                e = t * n_states + s
                if s % 4 == 0 or not hw_pm:
                    word = await axi_read(dut, 0x20000 + 4 * (e // 4))
                hw_pm.append((word >> (8 * (e % 4))) & 0xFF)
                if e % 32 == 0 or not hw_sv:
                    sword = await axi_read(dut, 0x10000 + 4 * (e // 32))
                hw_sv.append((sword >> (e % 32)) & 1)
            # Reachable states only (early steps keep INF entries)
            mn = min(hw_pm)
            reach = [s for s in range(n_states) if sw["path_metrics"][t][s] < 1000] \
                if "path_metrics" in sw else list(range(n_states))
            for s in reach:
                if "path_metrics" in sw:  # omitted by the server at K=9
                    assert hw_pm[s] - mn == sw["path_metrics"][t][s], (t, s, hw_pm[s], mn, sw["path_metrics"][t][s])
                assert hw_sv[s] == sw["survivors"][t][s], (t, s)
        dut._log.info("K=%d %r: %d steps, trellis matches software for %d steps",
                      K, msg, n_steps, check_steps)

        # Full readback through the server's own parser + traceback replay
        sv_words = [await axi_read(dut, 0x10000 + 4 * w) for w in range((n_entries + 31) // 32)]
        bs_words = [await axi_read(dut, 0x14000 + 4 * w) for w in range((n_steps + 3) // 4)]
        tr = S.build_hw_trellis(K, CFG["D"], len(noisy), n_entries, n_steps,
                                [], sv_words, bs_words, S.unpack_decoded_bytes(out))
        assert tr["replay_checked"] >= len(info), tr["replay_checked"]
        assert tr["replay_mismatches"] == 0, tr["replay_mismatches"]
        assert len(tr["traceback_path"]) == n_steps - CFG["D"] + 1
        dut._log.info("K=%d %r: replayed %d HW traceback windows, 0 mismatches",
                      K, msg, tr["replay_checked"])


@cocotb.test()
async def test_ber_registers(dut):
    await setup(dut)
    base = 0x100
    st = await axi_read(dut, base + 0x04)
    assert (st >> 16) & 0xF == K
    await axi_write(dut, base + 0x08, int(0.03 * 2**32))
    await axi_write(dut, base + 0x0C, 4000)
    await axi_write(dut, base + 0x10, 0)
    await axi_write(dut, base + 0x14, 0)
    await axi_write(dut, base + 0x00, 1)
    while True:
        st = await axi_read(dut, base + 0x04)
        if not (st & 1):
            break
        await ClockCycles(dut.clk, 2000)
    bits = await axi_read(dut, base + 0x20)
    errs = await axi_read(dut, base + 0x28)
    flips = await axi_read(dut, base + 0x30)
    chb = await axi_read(dut, base + 0x38)
    cyc = await axi_read(dut, base + 0x40)
    dut._log.info("BER: bits=%d errs=%d flips=%d chbits=%d cycles=%d", bits, errs, flips, chb, cyc)
    assert bits >= 4000
    assert 0.015 < flips / chb < 0.045
    assert errs / bits < 0.02


@cocotb.test()
async def test_noisy_traceback_replay(dut):
    """Noisy frames back to back: every bit the hardware emits must equal a
    replay of its own sliding-window traceback over the captured survivors and
    best states. This caught tracebacks starting from the previous symbol's
    best state (invisible without noise). NOISY_DUMP=<file> also writes the
    outputs, for A/B runs between RTL versions."""
    await setup(dut)
    rng = random.Random(4242)
    n_frames = int(os.environ.get("NOISY_FRAMES", "8"))
    lines, total_mm = [], 0
    for f in range(n_frames):
        msg = bytes(rng.randrange(32, 127) for _ in range(24))
        info = S.bytes_to_bits_msb(list(msg))
        syms = S.conv_encode(info)
        noisy = [s ^ (1 << rng.randrange(2)) if rng.random() < 0.12 else s for s in syms]
        frame = S.pack_symbols_to_bytes(noisy) + S.pack_symbols_to_bytes([0] * (CFG["D"] - 1))
        out = await decode_frame(dut, frame)
        entries = (await axi_read(dut, 0x00C)) & 0x1FFFF
        steps = (await axi_read(dut, 0x010)) & 0x7FF
        sv = [await axi_read(dut, 0x10000 + 4 * w) for w in range((entries + 31) // 32)]
        bs = [await axi_read(dut, 0x14000 + 4 * w) for w in range((steps + 3) // 4)]
        hwb = S.unpack_decoded_bytes(out)
        tr = S.build_hw_trellis(K, CFG["D"], len(noisy), entries, steps, [], sv, bs, hwb)
        assert tr["replay_checked"] >= len(info), (f, tr["replay_checked"])
        rp = [st & 1 for st in tr["traceback_path"]]
        pos = [i for i, (x, y) in enumerate(zip(rp, hwb)) if x != y]
        hw_err = sum(x != y for x, y in zip(hwb, info))
        total_mm += len(pos)
        lines.append(f"{f} {bytes(out).hex()} replay_mm={len(pos)} pos={pos} hw_err={hw_err}")
    if os.environ.get("NOISY_DUMP"):
        with open(os.environ["NOISY_DUMP"], "w") as fh:
            fh.write("\n".join(lines) + "\n")
    dut._log.info("K=%d: %d noisy frames, %d replay mismatches", K, n_frames, total_mm)
    assert total_mm == 0, "hardware traceback disagrees with replay:\n" + "\n".join(lines)
