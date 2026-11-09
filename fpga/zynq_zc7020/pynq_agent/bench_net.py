#!/usr/bin/env python3
"""Benchmark the Ethernet agent path (PC -> HTTP -> agent -> /dev/mem).

    python bench_net.py [http://192.168.2.99:8800]
Mirrors bench_jtag.tcl so the two transports can be compared op for op.
"""
import json
import statistics
import sys
import time
import urllib.request

URL = sys.argv[1] if len(sys.argv) > 1 else "http://192.168.2.99:8800"


def call(path, payload=None, timeout=120):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(URL + path, data=data, method="POST" if data else "GET",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def timed(fn, n=1):
    ts = []
    for _ in range(n):
        t0 = time.perf_counter()
        out = fn()
        ts.append((time.perf_counter() - t0) * 1000)
    return statistics.median(ts), out


def main():
    res = {}
    for k in (7, 9):
        ms, _ = timed(lambda: call("/program", {"k": k}))
        res[f"program K={k} (ms)"] = ms
    # K=9 is loaded: biggest trellis (256 states)
    res["ping round trip (ms, median of 50)"], _ = timed(lambda: call("/ping"), 50)
    frame = list(range(60))
    words = [int.from_bytes(bytes(frame[i:i + 4]), "little") for i in range(0, 60, 4)]
    res["decode 60-byte frame (ms, median of 20)"], _ = timed(
        lambda: call("/decode", {"frame_len": 60, "words": words}), 20)
    ms, tr = timed(lambda: call("/trellis", {"read_pm": True}))
    nwords = len(tr["pm"]) + len(tr["sv"]) + len(tr["bs"])
    res[f"trellis readback K=9 ({nwords} words) (ms)"] = ms
    res["trellis readback (words/s)"] = nwords / (ms / 1000)
    ms, vals = timed(lambda: call("/ber_point", {"thresh": 0x0A000000, "maxerrs": 1 << 30,
                                                 "timeout_ms": 1000, "seed": 1}))
    res["ber_point 1 s run, wall (ms)"] = ms
    for k, v in res.items():
        print(f"{k:45s} {v:12.1f}")


if __name__ == "__main__":
    main()
