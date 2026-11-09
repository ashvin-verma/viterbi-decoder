#!/usr/bin/env python3
"""
Board-side agent for the Viterbi FPGA demo on a PYNQ-Z2 running PYNQ Linux.

Replaces the JTAG/XSDB path: the PC web server talks to this agent over
Ethernet, and the agent drives the AXI frame buffer through /dev/mem (pynq.MMIO)
and loads bitstreams through the Linux FPGA manager (pynq.Overlay). The
register-level sequences mirror web/fb_helpers.tcl one for one.

Run as root inside the PYNQ venv (needed for /dev/mem and the FPGA manager):
    sudo /usr/local/share/pynq-venv/bin/python3 agent.py --host 192.168.2.99

Expects viterbi_ps7_k{K}.bit next to this file.

API (JSON over HTTP; every call is serialized -- the PL is one shared device):
    GET  /ping                      -> {"ok", "status", "k"}
    POST /program   {"k"}           -> {"ok", "message"}
    GET  /hwconfig                  -> {"value"}
    POST /decode    {"frame_len", "words": [u32...]} -> {"out_count", "words"}
    POST /decode_many {"frames": [base64...]} -> {"outputs": [base64...], "hw_ms"}
    POST /trellis   {"read_pm"}     -> {"entries", "steps", "pm", "sv", "bs"}
    POST /ber_point {"thresh", "maxerrs", "timeout_ms", "seed"} -> {"values": [11 x u32]}
"""
import argparse
import base64
import ctypes
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

FB_BASE = 0x43C00000
FB_SIZE = 0x40000          # 256 KB window (see scripts/update_bd_256k.tcl)
FCLK0_MHZ = 50
HERE = os.path.dirname(os.path.abspath(__file__))
MAX_BODY = 4 * 1024 * 1024
MAX_FRAMES = 2000


class Board:
    def __init__(self):
        self.lock = threading.Lock()
        self.overlay = None
        self.mmio = None
        self.k = None

    # -- low level -----------------------------------------------------------
    def _need(self):
        if self.mmio is None:
            raise RuntimeError("PL not programmed")

    def rd(self, off):
        return int(self.mmio.read(off))

    def wr(self, off, val):
        self.mmio.write(off, int(val) & 0xFFFFFFFF)

    def rd_words(self, off, n):
        if n <= 0:
            return []
        arr = self.mmio.array            # numpy uint32 view of the window
        i = off // 4
        return [int(v) for v in arr[i:i + n]]

    # -- operations (match fb_helpers.tcl) -----------------------------------
    def program(self, k):
        # Not pynq.Overlay: its .hwh parser can't resolve this design (the
        # frame buffer is RTL outside the block design, behind an exported
        # M_AXI port). Bitstream.download() with no parser just converts
        # .bit -> .bin and hands it to the Linux FPGA manager.
        from pynq import MMIO, Bitstream
        from pynq.ps import Clocks
        bit = os.path.join(HERE, f"viterbi_ps7_k{int(k)}.bit")
        if not os.path.exists(bit):
            raise FileNotFoundError(f"missing {os.path.basename(bit)}")
        self.mmio = None
        self.k = None
        Bitstream(bit).download()
        Clocks.fclk0_mhz = FCLK0_MHZ     # design is timed for 50 MHz (PYNQ boots at 100)
        self.mmio = MMIO(FB_BASE, FB_SIZE)
        self.k = int(k)
        return self.rd(0x004)

    def ping(self):
        return None if self.mmio is None else self.rd(0x004)

    def hwconfig(self):
        self._need()
        return self.rd(0x014)

    def decode(self, frame_len, words):
        self._need()
        self.wr(0x008, frame_len)
        for i, w in enumerate(words):
            self.wr(0x400 + 4 * i, w)
        self.wr(0x000, 1)
        t0 = time.monotonic()
        while time.monotonic() - t0 < 2.0:
            if self.rd(0x004) & 0x2:
                break
        status = self.rd(0x004)
        out_count = (status >> 8) & 0xFF
        return out_count, self.rd_words(0x800, (out_count + 3) // 4)

    def decode_many(self, frames):
        """Decode a list of frames (bytes) back to back. Returns the output
        bytes per frame and the board-side wall time of the whole loop, so
        network latency never enters the throughput figure. Uses the C loop
        (libfbloop.so) when available, else single 32-bit MMIO stores."""
        self._need()
        if FBLOOP is not None:
            return self._decode_many_c(frames)
        return self._decode_many_py(frames)

    def _decode_many_c(self, frames):
        n = len(frames)
        inbuf = ctypes.create_string_buffer(b"".join(f.ljust(256, b"\0") for f in frames), n * 256)
        lens = (ctypes.c_int * n)(*[len(f) for f in frames])
        outbuf = ctypes.create_string_buffer(n * 256)
        olens = (ctypes.c_int * n)()
        hw_s = ctypes.c_double()
        done = FBLOOP.fb_decode_many(inbuf, lens, n, outbuf, olens,
                                     ctypes.c_double(2.0), ctypes.byref(hw_s))
        if done != n:
            raise TimeoutError(f"frame {done} of {n} did not finish")
        raw = outbuf.raw
        return [raw[i * 256:i * 256 + olens[i]] for i in range(n)], hw_s.value * 1000

    def _decode_many_py(self, frames):
        outs = []
        t0 = time.perf_counter()
        for fb in frames:
            n = len(fb)
            fb = fb + b"\0" * (-n % 4)
            self.wr(0x008, n)
            for i in range(0, len(fb), 4):
                self.mmio.write(0x400 + i, int.from_bytes(fb[i:i + 4], "little"))
            self.wr(0x000, 1)
            t1 = time.perf_counter()
            while not (self.rd(0x004) & 0x2):
                if time.perf_counter() - t1 > 2.0:
                    raise TimeoutError("frame decode did not finish")
            oc = (self.rd(0x004) >> 8) & 0xFF
            words = self.rd_words(0x800, (oc + 3) // 4)
            outs.append(b"".join(w.to_bytes(4, "little") for w in words)[:oc])
        return outs, (time.perf_counter() - t0) * 1000

    def trellis(self, read_pm):
        self._need()
        entries = self.rd(0x00C) & 0x1FFFF
        steps = self.rd(0x010) & 0x7FF
        pm = self.rd_words(0x20000, (entries + 3) // 4) if (read_pm and entries) else []
        sv = self.rd_words(0x10000, (entries + 31) // 32) if entries else []
        bs = self.rd_words(0x14000, (steps + 3) // 4) if steps else []
        return {"entries": entries, "steps": steps, "pm": pm, "sv": sv, "bs": bs}

    def ber_point(self, thresh, maxerrs, timeout_ms, seed):
        self._need()
        b = 0x100
        self.wr(b + 0x08, thresh)
        self.wr(b + 0x0C, 0)
        self.wr(b + 0x10, 0)
        self.wr(b + 0x14, maxerrs)
        self.wr(b + 0x18, seed)
        self.wr(b, 1)
        t0 = time.monotonic()
        while True:
            time.sleep(0.025)
            if not (self.rd(b + 0x04) & 1):
                break
            if (time.monotonic() - t0) * 1000 > timeout_ms:
                self.wr(b, 2)            # stop -> auto snapshot
                time.sleep(0.001)
                break
        return [self.rd(b + 0x04)] + self.rd_words(b + 0x20, 10)


def _load_fbloop():
    """C frame loop built by deploy.py; None -> fall back to pynq.MMIO."""
    path = os.path.join(HERE, "libfbloop.so")
    if not os.path.exists(path):
        return None
    try:
        lib = ctypes.CDLL(path)
        lib.fb_decode_many.restype = ctypes.c_int
        lib.fb_decode_many.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int), ctypes.c_int,
                                       ctypes.c_char_p, ctypes.POINTER(ctypes.c_int),
                                       ctypes.c_double, ctypes.POINTER(ctypes.c_double)]
        if lib.fb_open() != 0:
            return None
        return lib
    except OSError:
        return None


FBLOOP = _load_fbloop()
board = Board()


class Handler(BaseHTTPRequestHandler):
    server_version = "viterbi-agent/1"
    # Headers + body in one segment, no Nagle: otherwise every response stalls
    # on the peer's delayed ACK (~15 ms round trip on a direct gigabit link).
    wbufsize = 1 << 16
    disable_nagle_algorithm = True

    def log_message(self, fmt, *args):
        pass  # quiet; errors are reported in responses

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        tok = self.server.token
        return not tok or self.headers.get("X-Agent-Token") == tok

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n > MAX_BODY:
            raise ValueError("body too large")
        return json.loads(self.rfile.read(n) or b"{}")

    def _dispatch(self, method):
        if not self._authorized():
            return self._send(403, {"error": "bad token"})
        path = self.path.split("?")[0]
        try:
            req = self._body() if method == "POST" else {}
            with board.lock:
                if method == "GET" and path == "/ping":
                    return self._send(200, {"ok": True, "status": board.ping(), "k": board.k})
                if method == "GET" and path == "/hwconfig":
                    return self._send(200, {"value": board.hwconfig()})
                if method == "POST" and path == "/program":
                    st = board.program(int(req["k"]))
                    return self._send(200, {"ok": True, "message": f"OK {st}"})
                if method == "POST" and path == "/decode":
                    words = [int(w) for w in req["words"]][:64]
                    oc, out = board.decode(int(req["frame_len"]), words)
                    return self._send(200, {"out_count": oc, "words": out})
                if method == "POST" and path == "/decode_many":
                    frames = [base64.b64decode(f) for f in req["frames"]][:MAX_FRAMES]
                    if any(len(f) > 256 for f in frames):
                        raise ValueError("frame larger than 256 bytes")
                    outs, hw_ms = board.decode_many(frames)
                    return self._send(200, {"outputs": [base64.b64encode(o).decode() for o in outs],
                                            "hw_ms": hw_ms})
                if method == "POST" and path == "/trellis":
                    return self._send(200, board.trellis(bool(req.get("read_pm"))))
                if method == "POST" and path == "/ber_point":
                    timeout_ms = min(int(req["timeout_ms"]), 60000)
                    vals = board.ber_point(int(req["thresh"]), int(req["maxerrs"]),
                                           timeout_ms, int(req["seed"]))
                    return self._send(200, {"values": vals})
            return self._send(404, {"error": f"no route {method} {path}"})
        except Exception as e:  # report, never crash the agent
            return self._send(500, {"error": f"{type(e).__name__}: {e}"})

    def do_GET(self):
        self._dispatch("GET")

    def do_POST(self):
        self._dispatch("POST")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="192.168.2.99",
                    help="bind address (default: the direct-link interface only)")
    ap.add_argument("--port", type=int, default=8800)
    ap.add_argument("--program", type=int, default=0,
                    help="load this K's bitstream at startup")
    args = ap.parse_args()
    if args.program:
        board.program(args.program)
    srv = HTTPServer((args.host, args.port), Handler)
    srv.token = os.environ.get("AGENT_TOKEN", "")
    print(f"viterbi agent on {args.host}:{args.port} (K={board.k}, "
          f"frame loop: {'C' if FBLOOP else 'Python'})", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
