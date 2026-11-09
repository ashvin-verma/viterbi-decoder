#!/usr/bin/env python3
"""
server.py -- Flask web server for interactive Viterbi Decoder FPGA demo.

Provides a web UI where users type a message, inject noise, and watch
the PYNQ-Z2 FPGA decode it in real-time via XSDB/JTAG.

Usage:
    pip install flask waitress
    python server.py              # http://localhost:5000
    python server.py --no-fpga    # software-only mode (no XSDB needed)

AXI Frame Buffer register map (base = 0x43C00000):
    0x000  CTRL       [0]=trigger, [1]=soft_reset
    0x004  STATUS     [0]=busy, [1]=done, [15:8]=output byte count
    0x008  FRAME_LEN  [8:0]=input byte count
    0x400  INPUT_BUF  256-byte write buffer (64 x 32-bit words)
    0x800  OUTPUT_BUF 256-byte read buffer  (64 x 32-bit words)
"""

import os
import sys
import random
import time
import uuid
import atexit
import logging
import threading
import queue as queue_mod
from collections import deque, OrderedDict
import json
import re
import urllib.error
from flask import Flask, render_template, jsonify, request
from xsdb_session import PersistentXSDB
from ber_theory import theory_curves, ebn0_to_p

# =========================================================================
# Configuration
# =========================================================================
VIVADO_PATH = os.environ.get("VIVADO_PATH", r"D:\Xilinx\Vivado\2024.2")
XSDB = os.path.join(VIVADO_PATH, "bin", "xsdb.bat")
FPGA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
BIT_FILE = os.path.join(FPGA_DIR, "vivado_project_ps7", "viterbi_ps7.bit")

# Frame buffer base address
FB_BASE = 0x43C00000
ADDR_CTRL      = FB_BASE + 0x000
ADDR_STATUS    = FB_BASE + 0x004
ADDR_FRAME_LEN = FB_BASE + 0x008
ADDR_IN_BASE   = FB_BASE + 0x400
ADDR_OUT_BASE  = FB_BASE + 0x800

# K configurations: K -> {G0 (octal), G1 (octal), D (traceback depth), label}
K_CONFIGS = {
    3: {"G0": 0o7,   "G1": 0o5,   "D": 12, "label": "K=3 (Minimal)"},
    5: {"G0": 0o23,  "G1": 0o35,  "D": 24, "label": "K=5 (Moderate)"},
    7: {"G0": 0o171, "G1": 0o133, "D": 42, "label": "K=7 (NASA Standard)"},
    9: {"G0": 0o561, "G1": 0o753, "D": 60, "label": "K=9 (IS-95/3GPP, 256 states)"},
}

# Active decoder parameters (default K=7)
K = 7
G0 = 0o171
G1 = 0o133
M = K - 1
D = 42


def set_k(new_k):
    """Switch the active constraint length. Updates all global encoder/decoder params."""
    global K, G0, G1, M, D
    cfg = K_CONFIGS[new_k]
    K = new_k
    G0 = cfg["G0"]
    G1 = cfg["G1"]
    M = K - 1
    D = cfg["D"]


def bit_file_for_k(k):
    """Return the bitstream path for a given K, with fallback for K=7."""
    k_specific = os.path.join(FPGA_DIR, "vivado_project_ps7",
                              f"viterbi_ps7_k{k}.bit")
    if os.path.exists(k_specific):
        return k_specific
    # Fallback: default bitstream name (backward compat for K=7)
    if k == 7:
        return BIT_FILE
    return k_specific  # return expected path even if missing

# =========================================================================
# Convolutional Encoder (matches RTL convention)
# =========================================================================
def _parity(x):
    p = 0
    while x:
        p ^= (x & 1)
        x >>= 1
    return p


def conv_encode(info_bits, g0=None, g1=None, m=None):
    """Rate-1/2 convolutional encoder. Appends m tail zeros."""
    g0 = g0 if g0 is not None else G0
    g1 = g1 if g1 is not None else G1
    m = m if m is not None else M
    mask = (1 << m) - 1
    state = 0
    symbols = []
    for bit in list(info_bits) + [0] * m:
        reg = (bit & 1) | (state << 1)
        c0 = _parity(reg & g0)
        c1 = _parity(reg & g1)
        symbols.append((c0 << 1) | c1)
        state = ((state << 1) | (bit & 1)) & mask
    return symbols


def pack_symbols_to_bytes(symbols):
    """Pack 2-bit symbols into bytes, 4 per byte, LSB first."""
    padded = list(symbols)
    while len(padded) % 4 != 0:
        padded.append(0)
    packed = []
    for i in range(0, len(padded), 4):
        byte_val = 0
        for j in range(4):
            byte_val |= (padded[i + j] & 0x03) << (j * 2)
        packed.append(byte_val)
    return packed


def bytes_to_bits_msb(byte_list):
    """Unpack bytes to bits, MSB first (ASCII convention)."""
    bits = []
    for b in byte_list:
        for j in range(7, -1, -1):
            bits.append((b >> j) & 1)
    return bits


def bits_to_bytes_msb(bits):
    """Pack bits to bytes, MSB first."""
    result = []
    for i in range(0, len(bits), 8):
        byte_val = 0
        for j in range(8):
            if i + j < len(bits):
                byte_val |= (bits[i + j] << (7 - j))
        result.append(byte_val)
    return result


def unpack_decoded_bytes(byte_list):
    """Unpack decoded output bytes to bits, LSB first (bit_packer_8x)."""
    bits = []
    for b in byte_list:
        for j in range(8):
            bits.append((b >> j) & 1)
    return bits


def inject_errors(symbols, error_rate):
    """Flip random bits in 2-bit symbols at given error rate.
    Returns (noisy_symbols, error_positions)."""
    noisy = list(symbols)
    positions = []
    for i in range(len(noisy)):
        if random.random() < error_rate:
            # Flip one random bit in the 2-bit symbol
            flip_bit = random.randint(0, 1)
            noisy[i] ^= (1 << flip_bit)
            positions.append(i)
    return noisy, positions


def prepare_frame(info_bits):
    """Encode info bits, return (input_bytes, num_output_bytes, total_symbols)."""
    symbols = conv_encode(info_bits)
    data_bytes = pack_symbols_to_bytes(symbols)

    # Flush symbols to push through traceback
    flush_syms = [0] * (D - 1)
    flush_bytes = pack_symbols_to_bytes(flush_syms)

    all_bytes = data_bytes + flush_bytes
    total_syms = len(all_bytes) * 4
    total_dec_bits = total_syms - D
    num_out_bytes = total_dec_bits // 8

    return all_bytes, num_out_bytes, len(symbols)


# =========================================================================
# Software-only Viterbi decoder (for --no-fpga mode)
# =========================================================================
def software_decode(noisy_symbols, g0=None, g1=None, m=None):
    """Simple Viterbi decoder in software for demo/testing without FPGA."""
    g0 = g0 if g0 is not None else G0
    g1 = g1 if g1 is not None else G1
    m = m if m is not None else M
    n_states = 1 << m
    INF = 999999

    pm = [INF] * n_states
    pm[0] = 0
    survivors = []

    for sym in noisy_symbols:
        new_pm = [INF] * n_states
        surv = [0] * n_states
        for s in range(n_states):
            for b in range(2):
                prev = ((s >> 1) | (b << (m - 1))) & (n_states - 1)
                reg = s | (b << m)
                c0 = _parity(reg & g0)
                c1 = _parity(reg & g1)
                expected = (c0 << 1) | c1
                diff = expected ^ sym
                bm = ((diff >> 1) & 1) + (diff & 1)
                candidate = pm[prev] + bm
                if candidate < new_pm[s]:
                    new_pm[s] = candidate
                    surv[s] = b
        pm = new_pm
        survivors.append(surv)

    state = min(range(n_states), key=lambda s: pm[s])
    decoded = []
    for t in range(len(survivors) - 1, -1, -1):
        decoded.append(state & 1)
        b = survivors[t][state]
        state = ((state >> 1) | (b << (m - 1))) & (n_states - 1)
    decoded.reverse()

    return decoded


def software_decode_with_trellis(noisy_symbols, g0=None, g1=None, m=None):
    """Viterbi decoder that also returns trellis visualization data."""
    g0 = g0 if g0 is not None else G0
    g1 = g1 if g1 is not None else G1
    m = m if m is not None else M
    n_states = 1 << m
    INF = 999999

    pm = [INF] * n_states
    pm[0] = 0
    all_survivors = []
    all_pm = []

    for sym in noisy_symbols:
        new_pm = [INF] * n_states
        surv = [0] * n_states
        for s in range(n_states):
            for b in range(2):
                prev = ((s >> 1) | (b << (m - 1))) & (n_states - 1)
                reg = s | (b << m)
                c0 = _parity(reg & g0)
                c1 = _parity(reg & g1)
                expected = (c0 << 1) | c1
                diff = expected ^ sym
                bm = ((diff >> 1) & 1) + (diff & 1)
                candidate = pm[prev] + bm
                if candidate < new_pm[s]:
                    new_pm[s] = candidate
                    surv[s] = b
        pm = new_pm
        all_survivors.append(surv)
        # Normalize path metrics (subtract min to keep values small)
        pm_min = min(pm)
        all_pm.append([v - pm_min for v in pm])

    # Traceback
    state = min(range(n_states), key=lambda s: pm[s])
    decoded = []
    tb_path = [0] * len(all_survivors)
    for t in range(len(all_survivors) - 1, -1, -1):
        tb_path[t] = state
        decoded.append(state & 1)
        b = all_survivors[t][state]
        state = ((state >> 1) | (b << (m - 1))) & (n_states - 1)
    decoded.reverse()

    # For K=9 (256 states), omit full path_metrics to save bandwidth
    include_pm = n_states <= 64
    trellis = {
        "n_states": n_states,
        "n_timesteps": len(noisy_symbols),
        "traceback_path": tb_path,
        "survivors": all_survivors,
    }
    if include_pm:
        trellis["path_metrics"] = all_pm

    return decoded, trellis


def build_hw_trellis(k, d, n_data_steps, entries, steps, pm_words, sv_words,
                     best_words, hw_decoded_bits):
    """Turn raw BRAM capture words into trellis visualization data, and
    replay the hardware's sliding-window traceback to cross-check it against
    the bits the FPGA actually emitted."""
    m = k - 1
    n_states = 1 << m
    steps = min(steps, entries // n_states)

    surv = []
    for t in range(steps):
        row = []
        for s in range(n_states):
            e = t * n_states + s
            row.append((sv_words[e >> 5] >> (e & 31)) & 1)
        surv.append(row)
    best = [(best_words[t >> 2] >> (8 * (t & 3))) & 0xFF for t in range(steps)]

    pms = None
    if pm_words:
        pms = []
        for t in range(steps):
            raw = [(pm_words[(t * n_states + s) >> 2] >> (8 * ((t * n_states + s) & 3))) & 0xFF
                   for s in range(n_states)]
            mn = min(raw)
            # 255 = saturated "unreachable" seed metric in the first K-1 steps
            pms.append([None if (v == 255 and t < m) else v - mn for v in raw])

    # Hardware traceback replay: window starting at step t walks back D-1
    # steps from best[t] and emits the LSB of the state reached (time t-D+1).
    decided = []
    for t in range(d - 1, steps):
        st = best[t]
        for j in range(d - 1):
            b = surv[t - j][st]
            st = ((st >> 1) | (b << (m - 1))) & (n_states - 1)
        decided.append(st)
    replay_bits = [s & 1 for s in decided]
    n_chk = min(len(replay_bits), len(hw_decoded_bits))
    mismatches = sum(a != b for a, b in zip(replay_bits[:n_chk], hw_decoded_bits[:n_chk]))

    trellis = {
        "source": "FPGA",
        "n_states": n_states,
        "n_timesteps": steps,
        "n_data_steps": n_data_steps,
        "traceback_depth": d,
        "survivors": surv,
        "best_states": best,
        "traceback_path": decided,
        "replay_checked": n_chk,
        "replay_mismatches": mismatches,
    }
    if pms is not None:
        trellis["path_metrics"] = pms
    return trellis


# =========================================================================
# XSDB Frame Buffer Interface (persistent session)
# =========================================================================
WEB_DIR = os.path.dirname(os.path.abspath(__file__))
HELPERS_TCL = os.path.join(WEB_DIR, "fb_helpers.tcl")

logger = logging.getLogger(__name__)


class FrameBufferXSDB:
    """Communicates with viterbi_axi_framebuf via a persistent XSDB session."""

    def __init__(self):
        self.xsdb = PersistentXSDB(
            xsdb_path=XSDB,
            helpers_tcl=HELPERS_TCL,
        )
        self.programmed = False

    @property
    def alive(self):
        return self.xsdb.alive

    def start(self):
        """Start the persistent XSDB session (connect + source helpers)."""
        self.xsdb.start()
        logger.info("XSDB session started (persistent)")

    def close(self):
        """Shut down the XSDB session."""
        self.xsdb.close()

    def _find_ps7_init(self):
        for candidate in [
            os.path.join(FPGA_DIR, "vivado_project_ps7", "viterbi_ps7.gen",
                         "sources_1", "bd", "system", "ip",
                         "system_ps7_0", "ps7_init.tcl"),
            os.path.join(FPGA_DIR, "vivado_project_ps7", "ps7_init.tcl"),
        ]:
            if os.path.exists(candidate):
                return candidate.replace("\\", "/")
        return None

    def program(self, bit_path_override=None):
        """Program PL + init PS7 via the fb_program TCL proc (every step checked).
        Retries once on a transient failure. Never issues rst -system, which
        leaves the DAP unusable until a physical power cycle."""
        actual_bit = bit_path_override or BIT_FILE
        if not os.path.exists(actual_bit):
            return False, f"Bitstream not found: {actual_bit}"

        ps7_init = self._find_ps7_init() or ""
        bit_path = actual_bit.replace("\\", "/")

        last = ""
        for attempt in range(2):
            try:
                last = self.xsdb.execute(
                    f"puts [fb_program {{{bit_path}}} {{{ps7_init}}}]",
                    timeout=90).strip()
            except Exception as e:
                last = f"FAIL xsdb: {e}"
            logger.info("fb_program attempt %d: %s", attempt + 1, last)
            if last.startswith("OK"):
                self.programmed = True
                return True, "FPGA programmed successfully"
            if "no_arm" in last:
                break  # needs a physical power cycle; retrying makes it worse
        self.programmed = False
        msg = last.splitlines()[-1] if last else "unknown error"
        return False, f"Programming failed: {msg}"

    def decode_frame(self, input_bytes):
        """Write frame to buffer, trigger, read output via fb_decode."""
        n = len(input_bytes)
        if n > 256:
            return None, "Frame too large (max 256 bytes)"

        # Pack input bytes into 32-bit words (decimal)
        n_words = (n + 3) // 4
        words = []
        for w in range(n_words):
            word = 0
            for b in range(4):
                idx = w * 4 + b
                if idx < n:
                    word |= (input_bytes[idx] & 0xFF) << (b * 8)
            words.append(str(word))

        # Build TCL command: fb_decode frame_len {w0 w1 w2 ...}
        word_list_str = " ".join(words)
        tcl_cmd = f"puts [fb_decode {n} {{{word_list_str}}}]"

        try:
            result = self.xsdb.execute(tcl_cmd, timeout=30)
        except Exception as e:
            logger.error("decode_frame failed: %s", e)
            return None, f"XSDB error: {e}"

        # Parse TCL list result: "out_count word0 word1 ..."
        parts = result.strip().split()
        if not parts:
            return None, "Empty response from XSDB"

        try:
            out_count = int(parts[0], 0)
        except ValueError:
            return None, f"Bad out_count: {parts[0]}"

        # Unpack 32-bit words to bytes
        decoded_bytes = []
        for i, val_str in enumerate(parts[1:]):
            try:
                word = int(val_str, 0)
            except ValueError:
                continue
            for b in range(4):
                if len(decoded_bytes) < out_count:
                    decoded_bytes.append((word >> (b * 8)) & 0xFF)

        return decoded_bytes, f"OK ({out_count} bytes)"

    def hw_config(self):
        """Decode the HW_CONFIG register: {K, D, G0, G1} baked into the
        bitstream, or None for bitstreams that predate it."""
        try:
            v = int(self.xsdb.execute("puts [fb_hwconfig]", timeout=10).strip(), 0)
        except Exception:
            return None
        if (v >> 30) != 1:
            return None
        return {"k": v & 0xF, "d": (v >> 4) & 0xFF,
                "g0": (v >> 12) & 0x1FF, "g1": (v >> 21) & 0x1FF}

    def read_trellis(self, read_pm):
        """Read the trellis captured in BRAM during the last decoded frame."""
        out = self.xsdb.execute(f"puts [fb_trellis {1 if read_pm else 0}]",
                                timeout=60)
        lines = {}
        head = None
        for line in out.splitlines():
            line = line.strip()
            if not line:
                continue
            tag, _, rest = line.partition(" ")
            if tag in ("PM", "SV", "BS"):
                lines[tag] = [int(x, 0) for x in rest.split()]
            elif head is None:
                head = [int(x, 0) for x in line.split()]
        if not head or len(head) < 2:
            raise RuntimeError(f"bad trellis readback: {out[:200]!r}")
        return head[0], head[1], lines.get("PM", []), lines.get("SV", []), lines.get("BS", [])

    def ber_point(self, thresh, max_errs, timeout_ms, seed):
        """Run the on-chip BER tester at one threshold. Returns dict."""
        out = self.xsdb.execute(
            f"puts [fb_ber_point {thresh} {max_errs} {timeout_ms} {seed}]",
            timeout=timeout_ms / 1000 + 30)
        vals = [int(x, 0) for x in out.split()]
        if len(vals) < 11:
            raise RuntimeError(f"bad BER readback: {out[:200]!r}")
        st = vals[0]

        def u64(i):
            return vals[1 + i] | (vals[2 + i] << 32)
        return {"status": st, "lanes": (st >> 8) & 0xFF, "k": (st >> 16) & 0xF,
                "bits": u64(0), "errors": u64(2), "flips": u64(4),
                "channel_bits": u64(6), "cycles": u64(8)}

    def ping(self):
        """Health check: read STATUS register."""
        try:
            result = self.xsdb.execute('puts [fb_ping]', timeout=10)
            return True, result.strip()
        except Exception as e:
            return False, str(e)


class FrameBufferNet:
    """Same interface as FrameBufferXSDB, but talks to pynq_agent/agent.py on a
    PYNQ-Z2 booted from SD (PYNQ Linux) over Ethernet. No JTAG involved."""

    def __init__(self, url, token=""):
        self.url = url.rstrip("/")
        self.token = token
        self.loaded_k = None

    @property
    def programmed(self):
        """Ask the agent what is actually loaded: the board can be reprogrammed
        or rebooted independently of this server (unlike a JTAG session)."""
        if self.loaded_k is None:
            return False
        try:
            return self._call("/ping", timeout=5).get("k") == self.loaded_k
        except Exception:
            return False

    @programmed.setter
    def programmed(self, value):
        if not value:
            self.loaded_k = None

    @property
    def alive(self):
        return self.ping()[0]

    def start(self):
        ok, msg = self.ping()
        logger.info("PYNQ agent %s: %s", self.url, "reachable" if ok else msg)

    def close(self):
        pass

    def _call(self, path, payload=None, timeout=30):
        import urllib.request
        data = None if payload is None else json.dumps(payload).encode()
        req = urllib.request.Request(self.url + path, data=data, method="POST" if data else "GET",
                                     headers={"Content-Type": "application/json",
                                              "X-Agent-Token": self.token})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            try:
                msg = json.loads(e.read()).get("error", str(e))
            except Exception:
                msg = str(e)
            raise RuntimeError(msg) from None

    def program(self, bit_path_override=None):
        m = re.search(r"_k(\d+)\.bit$", bit_path_override or BIT_FILE)
        k = int(m.group(1)) if m else 7
        try:
            r = self._call("/program", {"k": k}, timeout=60)
        except Exception as e:
            self.loaded_k = None
            logger.info("agent program K=%d: FAIL %s", k, e)
            return False, f"Programming failed: {e}"
        logger.info("agent program K=%d: %s", k, r.get("message"))
        self.loaded_k = k
        return True, "FPGA programmed successfully"

    def decode_frame(self, input_bytes):
        n = len(input_bytes)
        if n > 256:
            return None, "Frame too large (max 256 bytes)"
        words = [int.from_bytes(bytes(input_bytes[i:i + 4]).ljust(4, b"\0"), "little")
                 for i in range(0, n, 4)]
        try:
            r = self._call("/decode", {"frame_len": n, "words": words})
        except Exception as e:
            logger.error("decode_frame failed: %s", e)
            return None, f"Agent error: {e}"
        oc = r["out_count"]
        out = b"".join(int(w).to_bytes(4, "little") for w in r["words"])[:oc]
        return list(out), f"OK ({oc} bytes)"

    def hw_config(self):
        try:
            v = int(self._call("/hwconfig", timeout=10)["value"])
        except Exception:
            return None
        if (v >> 30) != 1:
            return None
        return {"k": v & 0xF, "d": (v >> 4) & 0xFF,
                "g0": (v >> 12) & 0x1FF, "g1": (v >> 21) & 0x1FF}

    def read_trellis(self, read_pm):
        r = self._call("/trellis", {"read_pm": bool(read_pm)}, timeout=60)
        return r["entries"], r["steps"], r["pm"], r["sv"], r["bs"]

    def ber_point(self, thresh, max_errs, timeout_ms, seed):
        vals = self._call("/ber_point", {"thresh": thresh, "maxerrs": max_errs,
                                         "timeout_ms": timeout_ms, "seed": seed},
                          timeout=timeout_ms / 1000 + 30)["values"]
        st = vals[0]

        def u64(i):
            return vals[1 + i] | (vals[2 + i] << 32)
        return {"status": st, "lanes": (st >> 8) & 0xFF, "k": (st >> 16) & 0xF,
                "bits": u64(0), "errors": u64(2), "flips": u64(4),
                "channel_bits": u64(6), "cycles": u64(8)}

    def ping(self):
        try:
            r = self._call("/ping", timeout=5)
            return True, str(r.get("status"))
        except Exception as e:
            return False, str(e)


# =========================================================================
# Activity Log
# =========================================================================
activity_log = deque(maxlen=50)
_activity_lock = threading.Lock()


def log_activity(event, detail=""):
    with _activity_lock:
        activity_log.appendleft({
            "timestamp": time.time(),
            "event": event,
            "detail": detail,
        })


# =========================================================================
# Async Job Queue (FPGA is a single shared resource)
# =========================================================================
class DecodeJob:
    __slots__ = ("id", "k", "message", "error_rate", "trellis", "status",
                 "position", "result", "created", "kind")

    def __init__(self, job_id, k, message, error_rate, trellis=False):
        self.kind = "decode"
        self.id = job_id
        self.k = k
        self.message = message
        self.error_rate = error_rate
        self.trellis = trellis
        self.status = "queued"
        self.position = 0
        self.result = None
        self.created = time.time()


class BerJob:
    """BER sweep on the on-chip tester: one result point per Eb/N0 value,
    appended live so clients can plot progress."""
    __slots__ = ("id", "k", "points", "status", "position", "result",
                 "created", "kind")

    def __init__(self, job_id, k, points):
        self.kind = "ber"
        self.id = job_id
        self.k = k
        self.points = points
        self.status = "queued"
        self.position = 0
        self.result = {"k": k, "points": [], "total": len(points)}
        self.created = time.time()


BER_POINT_TIMEOUT_MS = 3000   # per Eb/N0 point
BER_MAX_ERRS = 300            # stop a point early once this many errors seen
BER_DEFAULT_POINTS = [0, 1, 2, 3, 4, 5, 6, 7]
FCLK_HZ = 50e6
BER_CACHE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "ber_cache.json")


def _load_ber_cache():
    try:
        with open(BER_CACHE_FILE) as f:
            return {int(k): v for k, v in json.load(f).items()}
    except Exception:
        return {}


_ber_cache = _load_ber_cache()


def _save_ber_cache():
    try:
        tmp = BER_CACHE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump({str(k): v for k, v in _ber_cache.items()}, f)
        os.replace(tmp, BER_CACHE_FILE)
    except Exception as e:
        logger.warning("Could not save BER cache: %s", e)


def _run_ber_sweep(job, fpga_ref):
    hw = fpga_ref.hw_config()
    if hw is None:
        raise RuntimeError("Loaded bitstream has no BER tester (rebuild needed)")
    if hw["k"] != job.k:
        raise RuntimeError(f"Bitstream reports K={hw['k']}, expected K={job.k}")
    for x in job.points:
        p = ebn0_to_p(x)
        thresh = min(0xFFFFFFFF, int(round(p * 2 ** 32)))
        r = fpga_ref.ber_point(thresh, BER_MAX_ERRS, BER_POINT_TIMEOUT_MS,
                               random.getrandbits(32) | 1)
        secs = r["cycles"] / FCLK_HZ
        job.result["lanes"] = r["lanes"]
        job.result["points"].append({
            "ebn0_db": x,
            "p_target": p,
            "bits": r["bits"],
            "errors": r["errors"],
            "ber": (r["errors"] / r["bits"]) if r["bits"] else None,
            "channel_bits": r["channel_bits"],
            "channel_flips": r["flips"],
            "channel_ber": (r["flips"] / r["channel_bits"]) if r["channel_bits"] else None,
            "seconds": round(secs, 4),
            "mbps": round(r["bits"] / secs / 1e6, 3) if secs > 0 else 0,
        })
    job.result["finished"] = time.time()
    _ber_cache[job.k] = job.result
    _save_ber_cache()


_jobs = OrderedDict()
_jobs_lock = threading.Lock()
_job_queue = queue_mod.Queue()
_current_fpga_k = None

JOB_TTL = 300  # 5 min


def _update_positions():
    """Recount queue positions for all waiting jobs."""
    pos = 1
    for job in _jobs.values():
        if job.status == "queued":
            job.position = pos
            pos += 1


def _cleanup_old_jobs():
    """Remove completed/errored jobs older than JOB_TTL."""
    now = time.time()
    with _jobs_lock:
        stale = [jid for jid, j in _jobs.items()
                 if j.status in ("done", "error") and now - j.created > JOB_TTL]
        for jid in stale:
            del _jobs[jid]


def _hw_trellis_or_software(fpga_ref, k, d, g0, g1, m, noisy_symbols,
                            total_syms, decoded_bytes):
    """Prefer the trellis captured in FPGA BRAM; fall back to a software
    replay (clearly labelled) for bitstreams without the capture logic."""
    n_states = 1 << m
    try:
        if fpga_ref.hw_config() is not None:
            entries, steps, pm_w, sv_w, bs_w = fpga_ref.read_trellis(
                read_pm=n_states <= 64)
            hw_bits = unpack_decoded_bytes(decoded_bytes or [])
            return build_hw_trellis(k, d, len(noisy_symbols), entries, steps,
                                    pm_w, sv_w, bs_w, hw_bits)
    except Exception as e:
        logger.warning("HW trellis readback failed, using software: %s", e)
    all_noisy_syms = noisy_symbols + [0] * (total_syms - len(noisy_symbols))
    _, tr = software_decode_with_trellis(all_noisy_syms, g0, g1, m)
    tr["source"] = "Software"
    tr["n_data_steps"] = len(noisy_symbols)
    tr["traceback_depth"] = d
    return tr


def _run_decode_pipeline(k, message, error_rate, use_fpga_hw, fpga_ref,
                         include_trellis=False):
    """Full encode -> noise -> decode pipeline. Returns result dict.
    Thread-safe: uses only local K params, no globals."""
    cfg = K_CONFIGS[k]
    g0, g1, m, d = cfg["G0"], cfg["G1"], k - 1, cfg["D"]

    msg_bytes = list(message.encode("ascii"))
    info_bits = bytes_to_bits_msb(msg_bytes)
    num_info_bits = len(info_bits)
    symbols = conv_encode(info_bits, g0, g1, m)
    noisy_symbols, error_positions = inject_errors(symbols, error_rate)

    noisy_data_bytes = pack_symbols_to_bytes(noisy_symbols)
    flush_bytes = pack_symbols_to_bytes([0] * (d - 1))
    all_input_bytes = noisy_data_bytes + flush_bytes
    total_syms = len(all_input_bytes) * 4
    total_dec_bits = total_syms - d

    trellis_data = None
    t_start = time.time()
    if use_fpga_hw:
        decoded_bytes, status_msg = fpga_ref.decode_frame(all_input_bytes)
        decode_method = "FPGA"
        t_decode = time.time() - t_start
        if include_trellis:
            trellis_data = _hw_trellis_or_software(
                fpga_ref, k, d, g0, g1, m, noisy_symbols, total_syms,
                decoded_bytes)
    else:
        all_noisy_syms = noisy_symbols + [0] * (d - 1)
        if include_trellis:
            decoded_bits_sw, trellis_data = software_decode_with_trellis(
                all_noisy_syms, g0, g1, m)
            trellis_data["source"] = "Software"
            trellis_data["n_data_steps"] = len(noisy_symbols)
            trellis_data["traceback_depth"] = d
        else:
            decoded_bits_sw = software_decode(all_noisy_syms, g0, g1, m)
        decoded_bits_sw = decoded_bits_sw[:num_info_bits]
        while len(decoded_bits_sw) % 8 != 0:
            decoded_bits_sw.append(0)
        decoded_bytes = []
        for i in range(0, len(decoded_bits_sw), 8):
            byte_val = 0
            for j in range(8):
                if i + j < len(decoded_bits_sw):
                    byte_val |= (decoded_bits_sw[i + j] << j)
            decoded_bytes.append(byte_val)
        decode_method = "Software"
        t_decode = time.time() - t_start
    t_elapsed = t_decode

    if decoded_bytes:
        decoded_bits = unpack_decoded_bytes(decoded_bytes)
        recon_bits = decoded_bits[:num_info_bits]
        recon_byte_list = bits_to_bytes_msb(recon_bits)
        decoded_text = bytes(recon_byte_list[:len(msg_bytes)]).decode(
            "ascii", errors="replace")
        n_cmp = min(num_info_bits, len(decoded_bits))
        bit_errors = sum(a != b for a, b in
                         zip(info_bits[:n_cmp], decoded_bits[:n_cmp]))
    else:
        decoded_text = ""
        bit_errors = num_info_bits
        decoded_bits = []

    channel_ber = len(error_positions) / len(symbols) if symbols else 0
    decoded_ber = bit_errors / num_info_bits if num_info_bits > 0 else 0

    return {
        "input_text": message,
        "info_bits": num_info_bits,
        "num_symbols": len(symbols),
        "encoded_symbols": symbols,
        "noisy_symbols": noisy_symbols,
        "error_positions": error_positions,
        "num_errors_injected": len(error_positions),
        "decoded_text": decoded_text,
        "bit_errors": bit_errors,
        "channel_ber": round(channel_ber * 100, 1),
        "decoded_ber": round(decoded_ber * 100, 1),
        "decode_time_ms": round(t_elapsed * 1000, 1),
        "decode_method": decode_method,
        "num_input_bytes": len(all_input_bytes),
        "num_output_bytes": len(decoded_bytes) if decoded_bytes else 0,
        "k": k,
        "trellis": trellis_data,
    }


def _fpga_worker():
    """Background thread: processes FPGA decode jobs one at a time."""
    global _current_fpga_k
    while True:
        job = _job_queue.get()
        try:
            # Auto-program if K doesn't match or FPGA not yet programmed
            if job.k != _current_fpga_k or not fpga.programmed:
                bf = bit_file_for_k(job.k)
                if not os.path.exists(bf):
                    job.status = "error"
                    job.result = {"error": f"No bitstream for K={job.k}"}
                    log_activity("error", f"No bitstream for K={job.k}")
                    continue
                job.status = "programming"
                log_activity("programming", f"K={job.k}")
                success, msg = fpga.program(bf)
                if not success:
                    job.status = "error"
                    job.result = {"error": f"Programming failed: {msg}"}
                    log_activity("error", f"Program failed: {msg}")
                    continue
                _current_fpga_k = job.k
                log_activity("programmed", f"K={job.k}")

            if job.kind == "ber":
                job.status = "running"
                log_activity("ber_sweep", f"K={job.k}, {len(job.points)} points")
                _run_ber_sweep(job, fpga)
                job.status = "done"
                pts = job.result["points"]
                total_bits = sum(pt["bits"] for pt in pts)
                log_activity("ber_done", f"K={job.k}, {total_bits/1e6:.1f}M bits on FPGA")
                continue

            job.status = "decoding"
            result = _run_decode_pipeline(
                job.k, job.message, job.error_rate,
                use_fpga_hw=True, fpga_ref=fpga,
                include_trellis=job.trellis)
            job.result = result
            job.status = "done"
            log_activity("decoded",
                         f"K={job.k}, {result['bit_errors']} errors,"
                         f" {result['decode_time_ms']}ms, FPGA")
        except Exception as e:
            job.status = "error"
            job.result = {"error": str(e)}
            log_activity("error", str(e))
        finally:
            _job_queue.task_done()
            with _jobs_lock:
                _update_positions()


# =========================================================================
# Flask App
# =========================================================================
app = Flask(__name__)

# Hardware backend: PYNQ agent over Ethernet if --board URL / PYNQ_AGENT_URL
# is given (board booted from SD), otherwise JTAG via XSDB (board in JTAG boot).
PYNQ_AGENT_URL = os.environ.get("PYNQ_AGENT_URL", "")
if "--board" in sys.argv:
    PYNQ_AGENT_URL = sys.argv[sys.argv.index("--board") + 1]
if PYNQ_AGENT_URL:
    fpga = FrameBufferNet(PYNQ_AGENT_URL, os.environ.get("AGENT_TOKEN", ""))
else:
    fpga = FrameBufferXSDB()
USE_FPGA = True


def backend_available():
    return bool(PYNQ_AGENT_URL) or os.path.exists(XSDB)

# =========================================================================
# Security: allowed origins for CORS (set via env or default)
# =========================================================================
ALLOWED_ORIGINS = os.environ.get(
    "ALLOWED_ORIGINS",
    "https://viterbi.ashvinverma.com,http://localhost:5000,http://127.0.0.1:5000"
).split(",")


@app.after_request
def security_headers(response):
    """Add security headers to every response."""
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        # Cloudflare injects its Web Analytics beacon at the edge
        "script-src 'self' https://static.cloudflareinsights.com; "
        "style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data:; "
        "connect-src 'self' https://cloudflareinsights.com; "
        "frame-ancestors 'none'"
    )

    # CORS: only allow configured origins
    origin = request.headers.get("Origin")
    if origin in ALLOWED_ORIGINS:
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    return response


# =========================================================================
# Rate limiting (per-IP, in-memory)
# =========================================================================
class RateLimiter:
    """Simple per-IP token bucket rate limiter."""

    def __init__(self, rate=10, burst=20):
        """rate: requests per second refill. burst: max tokens."""
        self.rate = rate
        self.burst = burst
        self._buckets = {}  # ip -> (tokens, last_refill_time)
        self._lock = threading.Lock()

    def allow(self, ip):
        now = time.time()
        with self._lock:
            if ip in self._buckets:
                tokens, last = self._buckets[ip]
                # Refill
                tokens = min(self.burst, tokens + (now - last) * self.rate)
            else:
                tokens = self.burst
            if tokens >= 1:
                self._buckets[ip] = (tokens - 1, now)
                return True
            else:
                self._buckets[ip] = (tokens, now)
                return False

    def cleanup(self):
        """Remove stale entries (call periodically)."""
        now = time.time()
        with self._lock:
            stale = [ip for ip, (_, t) in self._buckets.items()
                     if now - t > 300]
            for ip in stale:
                del self._buckets[ip]


# Decode endpoint: 2 req/s sustained, burst of 5
decode_limiter = RateLimiter(rate=2, burst=5)
# FPGA-mutating endpoints (program, switch_k): 0.2 req/s (1 per 5s), burst 2
fpga_limiter = RateLimiter(rate=0.2, burst=2)
# General API: 5 req/s, burst 15
general_limiter = RateLimiter(rate=5, burst=15)
# BER sweeps hold the FPGA for ~25 s: 1 per minute per IP
ber_limiter = RateLimiter(rate=1 / 60, burst=1)


def get_client_ip():
    """Get client IP, respecting Cloudflare's CF-Connecting-IP header."""
    return (request.headers.get("CF-Connecting-IP")
            or request.headers.get("X-Forwarded-For", "").split(",")[0].strip()
            or request.remote_addr)


@app.errorhandler(429)
def rate_limit_exceeded(e):
    return jsonify({"error": "Rate limit exceeded. Please wait and try again."}), 429


def _asset_version():
    """Content hash of the static assets, appended as ?v= so browsers and
    Cloudflare (which caches static files for hours) fetch new code on deploy."""
    import hashlib
    h = hashlib.sha1()
    static_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
    for name in ("app.js", "style.css"):
        try:
            with open(os.path.join(static_dir, name), "rb") as f:
                h.update(f.read())
        except OSError:
            pass
    return h.hexdigest()[:10]


ASSET_VERSION = _asset_version()


@app.route("/")
def index():
    resp = app.make_response(render_template("index.html", v=ASSET_VERSION))
    resp.headers["Cache-Control"] = "no-cache"
    return resp


@app.route("/api/status")
def api_status():
    if not general_limiter.allow(get_client_ip()):
        return jsonify({"error": "Rate limit exceeded"}), 429
    k_options = {}
    for k_val, cfg in K_CONFIGS.items():
        bf = bit_file_for_k(k_val)
        k_options[str(k_val)] = {
            "label": cfg["label"],
            "bitstream_found": os.path.exists(bf),
        }
    return jsonify({
        "fpga_available": USE_FPGA and backend_available(),
        "bitstream_found": os.path.exists(bit_file_for_k(K)),
        "programmed": fpga.programmed if USE_FPGA else False,
        "mode": "FPGA" if USE_FPGA else "Software",
        "k": K,
        "fpga_k": _current_fpga_k,
        "rate": "1/2",
        "polynomials": f"G0={oct(G0)}, G1={oct(G1)}",
        "traceback_depth": D,
        "k_options": k_options,
        "queue_depth": _job_queue.qsize(),
    })


@app.route("/api/health")
def api_health():
    if not general_limiter.allow(get_client_ip()):
        return jsonify({"error": "Rate limit exceeded"}), 429
    if not USE_FPGA:
        return jsonify({"ok": True, "mode": "software", "xsdb_alive": False})
    ok, status = fpga.ping()
    return jsonify({
        "ok": ok,
        "mode": "fpga",
        "xsdb_alive": fpga.alive,
        "programmed": fpga.programmed,
        "status_register": status,
    })


@app.route("/api/program", methods=["POST"])
def api_program():
    if not fpga_limiter.allow(get_client_ip()):
        return jsonify({"error": "Rate limit exceeded. Please wait before reprogramming."}), 429
    if not USE_FPGA:
        return jsonify({"success": False, "message": "Software-only mode"})
    success, msg = fpga.program(bit_file_for_k(K))
    return jsonify({"success": success, "message": msg})


@app.route("/api/switch_k", methods=["POST"])
def api_switch_k():
    if not fpga_limiter.allow(get_client_ip()):
        return jsonify({"error": "Rate limit exceeded. Please wait before switching K."}), 429
    global USE_FPGA
    data = request.get_json(silent=True)
    if not data or not isinstance(data, dict) or "k" not in data:
        return jsonify({"error": "Missing 'k' parameter"}), 400

    try:
        new_k = int(data["k"])
    except (ValueError, TypeError):
        return jsonify({"error": "Invalid K value"}), 400
    if new_k not in K_CONFIGS:
        return jsonify({"error": f"Invalid K={new_k}. Must be one of {list(K_CONFIGS.keys())}"}), 400

    set_k(new_k)

    # In FPGA mode, reprogram with the correct bitstream
    if USE_FPGA:
        bf = bit_file_for_k(new_k)
        if os.path.exists(bf):
            success, msg = fpga.program(bf)
            if not success:
                return jsonify({
                    "success": False,
                    "message": f"K switched to {new_k} but FPGA programming failed: {msg}",
                    "k": K, "mode": "FPGA",
                })
            return jsonify({
                "success": True,
                "message": f"Switched to K={new_k} and reprogrammed FPGA",
                "k": K, "mode": "FPGA",
            })
        else:
            # Bitstream not found — fall back to software for this K
            USE_FPGA = False
            fpga.programmed = False
            return jsonify({
                "success": True,
                "message": f"Switched to K={new_k} (software mode — no bitstream found)",
                "k": K, "mode": "Software",
                "fallback": True,
            })

    return jsonify({
        "success": True,
        "message": f"Switched to K={new_k} (software mode)",
        "k": K, "mode": "Software",
    })


@app.route("/api/set_mode", methods=["POST"])
def api_set_mode():
    if not fpga_limiter.allow(get_client_ip()):
        return jsonify({"error": "Rate limit exceeded. Please wait before switching mode."}), 429
    global USE_FPGA
    data = request.get_json(silent=True)
    if not data or not isinstance(data, dict) or "mode" not in data:
        return jsonify({"error": "Missing 'mode' parameter"}), 400

    mode_val = data["mode"]
    if not isinstance(mode_val, str) or len(mode_val) > 20:
        return jsonify({"error": "Invalid mode value"}), 400
    mode = mode_val.lower()
    if mode == "software":
        USE_FPGA = False
        return jsonify({"success": True, "mode": "Software",
                        "message": "Switched to software mode"})
    elif mode == "fpga":
        if not backend_available():
            return jsonify({"success": False, "mode": "Software",
                            "message": "XSDB not available"})
        USE_FPGA = True
        # Re-start XSDB session if needed
        if not fpga.alive:
            try:
                fpga.start()
            except Exception as e:
                USE_FPGA = False
                return jsonify({"success": False, "mode": "Software",
                                "message": f"Failed to start XSDB: {e}"})
        return jsonify({"success": True, "mode": "FPGA",
                        "message": "Switched to FPGA mode"})
    else:
        return jsonify({"error": "Invalid mode. Use 'fpga' or 'software'"}), 400


@app.route("/api/decode", methods=["POST"])
def api_decode():
    if not decode_limiter.allow(get_client_ip()):
        return jsonify({"error": "Rate limit exceeded. Please wait and try again."}), 429

    data = request.get_json(silent=True)
    if not data or not isinstance(data, dict):
        return jsonify({"error": "No JSON body"}), 400

    message = data.get("message", "")
    if not isinstance(message, str):
        return jsonify({"error": "Invalid message type"}), 400

    try:
        error_rate = max(0.0, min(100.0, float(data.get("error_rate", 0)))) / 100.0
    except (ValueError, TypeError):
        return jsonify({"error": "Invalid error_rate"}), 400

    # Per-request K (defaults to current global K)
    try:
        req_k = int(data.get("k", K))
    except (ValueError, TypeError):
        return jsonify({"error": "Invalid K value"}), 400
    if req_k not in K_CONFIGS:
        return jsonify({"error": f"Invalid K={req_k}"}), 400

    if not message:
        return jsonify({"error": "Empty message"}), 400
    if len(message) > 24:
        return jsonify({"error": "Message too long (max 24 chars)"}), 400

    try:
        message.encode("ascii")
    except UnicodeEncodeError:
        return jsonify({"error": "ASCII only"}), 400

    req_trellis = bool(data.get("trellis", False))

    # FPGA mode: submit to job queue (async)
    if USE_FPGA:
        job_id = uuid.uuid4().hex[:12]
        job = DecodeJob(job_id, req_k, message, error_rate, trellis=req_trellis)
        with _jobs_lock:
            _jobs[job_id] = job
            job.position = _job_queue.qsize() + 1
        _job_queue.put(job)
        return jsonify({
            "async": True,
            "job_id": job_id,
            "position": job.position,
            "queue_depth": _job_queue.qsize(),
            "status": "queued",
        })

    # Software mode: decode synchronously with per-request K
    result = _run_decode_pipeline(
        req_k, message, error_rate,
        use_fpga_hw=False, fpga_ref=None,
        include_trellis=req_trellis)
    log_activity("decoded",
                 f"K={req_k}, {result['bit_errors']} errors,"
                 f" {result['decode_time_ms']}ms, SW")
    return jsonify(result)


@app.route("/api/job/<job_id>")
def api_job_status(job_id):
    """Poll job status. Returns result when done."""
    if not general_limiter.allow(get_client_ip()):
        return jsonify({"error": "Rate limit exceeded"}), 429
    with _jobs_lock:
        job = _jobs.get(job_id)
    if not job:
        return jsonify({"error": "Job not found"}), 404
    resp = {
        "job_id": job.id,
        "status": job.status,
        "position": job.position,
        "queue_depth": _job_queue.qsize(),
        "k": job.k,
    }
    resp["kind"] = job.kind
    if job.status in ("done", "error") or job.kind == "ber":
        resp["result"] = job.result
    return jsonify(resp)


@app.route("/api/ber")
def api_ber():
    """Theory curves + latest hardware-measured BER points for one K."""
    if not general_limiter.allow(get_client_ip()):
        return jsonify({"error": "Rate limit exceeded"}), 429
    try:
        k = int(request.args.get("k", K))
    except (ValueError, TypeError):
        return jsonify({"error": "Invalid K"}), 400
    if k not in K_CONFIGS:
        return jsonify({"error": f"Invalid K={k}"}), 400
    cfg = K_CONFIGS[k]
    running = None
    with _jobs_lock:
        for j in _jobs.values():
            if j.kind == "ber" and j.status in ("queued", "programming", "running"):
                running = {"job_id": j.id, "k": j.k, "status": j.status}
    return jsonify({
        "k": k,
        "theory": theory_curves(k, cfg["G0"], cfg["G1"]),
        "measured": _ber_cache.get(k),
        "running": running,
        "fpga_mode": USE_FPGA,
    })


@app.route("/api/ber/sweep", methods=["POST"])
def api_ber_sweep():
    """Queue a BER sweep on the FPGA. Only one sweep may be queued at once;
    if one exists it is returned so every visitor can watch the same run."""
    if not USE_FPGA:
        return jsonify({"error": "BER sweeps need the FPGA (server is in software mode)"}), 400
    data = request.get_json(silent=True) or {}
    try:
        k = int(data.get("k", K))
    except (ValueError, TypeError):
        return jsonify({"error": "Invalid K"}), 400
    if k not in K_CONFIGS:
        return jsonify({"error": f"Invalid K={k}"}), 400
    if not os.path.exists(bit_file_for_k(k)):
        return jsonify({"error": f"No bitstream for K={k}"}), 400
    with _jobs_lock:
        for j in _jobs.values():
            if j.kind == "ber" and j.status in ("queued", "programming", "running"):
                return jsonify({"job_id": j.id, "k": j.k, "status": j.status,
                                "joined": True})
    if not ber_limiter.allow(get_client_ip()):
        return jsonify({"error": "One BER sweep per minute, please."}), 429
    job = BerJob(uuid.uuid4().hex[:12], k, list(BER_DEFAULT_POINTS))
    with _jobs_lock:
        _jobs[job.id] = job
        job.position = _job_queue.qsize() + 1
    _job_queue.put(job)
    return jsonify({"job_id": job.id, "k": k, "status": "queued",
                    "position": job.position})


@app.route("/api/activity")
def api_activity():
    """Return recent activity log entries."""
    if not general_limiter.allow(get_client_ip()):
        return jsonify({"error": "Rate limit exceeded"}), 429
    with _activity_lock:
        entries = list(activity_log)
    return jsonify({"activity": entries})


# =========================================================================
# Periodic rate limiter cleanup (every 5 min)
# =========================================================================
def _cleanup_limiters():
    while True:
        time.sleep(300)
        decode_limiter.cleanup()
        fpga_limiter.cleanup()
        general_limiter.cleanup()


# =========================================================================
# Main
# =========================================================================
if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    )

    # Limit request body size (16 KB — decode payloads are tiny)
    app.config["MAX_CONTENT_LENGTH"] = 16 * 1024

    if "--no-fpga" in sys.argv:
        USE_FPGA = False
        print("Running in SOFTWARE-ONLY mode (no XSDB/FPGA)")
    else:
        if not backend_available():
            print(f"WARNING: XSDB not found at {XSDB}")
            print("Run with --no-fpga for software-only mode")
        else:
            print("Starting persistent XSDB session...")
            try:
                fpga.start()
                atexit.register(fpga.close)
                print("XSDB session started (persistent)")
            except Exception as e:
                print(f"WARNING: Failed to start XSDB session: {e}")
                print("FPGA decode will attempt reconnect on first request.")

    # Start background threads
    threading.Thread(target=_cleanup_limiters, daemon=True).start()
    threading.Thread(target=_fpga_worker, daemon=True).start()
    log_activity("server_start",
                 f"{'FPGA' if USE_FPGA else 'Software'} mode, K={K}")

    print(f"\nViterbi Decoder Web Demo (Multi-K)")
    print(f"  Mode:     {'FPGA' if USE_FPGA else 'Software'}")
    print(f"  Default:  K={K}, Rate=1/2, G0={oct(G0)}, G1={oct(G1)}")
    print(f"  Available K: {list(K_CONFIGS.keys())}")
    for kv, cfg in K_CONFIGS.items():
        bf = bit_file_for_k(kv)
        has_bit = "YES" if os.path.exists(bf) else "no"
        print(f"    K={kv}: {cfg['label']} [bitstream: {has_bit}]")
    print(f"  URL:      http://localhost:5000")
    print(f"  CORS:     {ALLOWED_ORIGINS}")
    if USE_FPGA:
        print(f"\n  To expose publicly:")
        print(f"    cloudflared tunnel run viterbi")
    print()

    # Use waitress for production, fall back to Flask dev server
    try:
        from waitress import serve
        print("Starting production server (waitress)...")
        serve(app, host="0.0.0.0", port=int(os.environ.get("PORT", 5000)), threads=4,
              channel_timeout=30, recv_bytes=16384,
              url_scheme="https")
    except ImportError:
        print("WARNING: waitress not installed, using Flask dev server")
        print("  Install for production: pip install waitress")
        app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000)), debug=False)
