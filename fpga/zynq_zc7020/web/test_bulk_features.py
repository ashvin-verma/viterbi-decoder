#!/usr/bin/env python3
"""Live checks for long text, compare-all-K, and bulk image decode.

    python test_bulk_features.py [http://localhost:5000]
"""
import base64
import json
import random
import sys
import time
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:5000"
fails = 0


def check(ok, msg):
    global fails
    print(("  PASS " if ok else "  FAIL ") + msg)
    fails += 0 if ok else 1


def post(path, body):
    for _ in range(10):
        req = urllib.request.Request(BASE + path, json.dumps(body).encode(),
                                     {"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            if e.code != 429:
                return json.loads(e.read())
            time.sleep(8)
    raise RuntimeError("rate limited")


def wait(job_id, limit=120):
    t0 = time.time()
    while time.time() - t0 < limit:
        with urllib.request.urlopen(f"{BASE}/api/job/{job_id}", timeout=10) as r:
            j = json.loads(r.read())
        if j["status"] in ("done", "error"):
            return j
        time.sleep(0.4)
    raise TimeoutError(job_id)


rng = random.Random(1)
words = "viterbi trellis survivor metric branch decoder frame symbol channel noise".split()
long_text = " ".join(rng.choice(words) for _ in range(330))[:2000]

print("=== long text, K=7, clean channel ===")
j = wait(post("/api/decode", {"message": long_text, "error_rate": 0, "k": 7})["job_id"])
r = j["result"]
check(j["status"] == "done", f"status {j['status']}")
check(r["decoded_text"] == long_text, f"{len(long_text)} chars round-trip exactly")
check(r["n_frames"] == -(-len(long_text) // 121), f"{r['n_frames']} frames (121 chars/frame)")
print(f"    FPGA {r['hw_ms']} ms for {r['info_bits']} bits = {r['throughput_kbps']} kbit/s")

print("=== long text, K=7, 8% symbols hit, trellis ===")
j = wait(post("/api/decode", {"message": long_text, "error_rate": 8, "k": 7, "trellis": True})["job_id"])
r = j["result"]
check(r["bit_errors"] < r["uncoded_bit_errors"],
      f"coded {r['bit_errors']} bit errors < uncoded {r['uncoded_bit_errors']}")
t = r["trellis"]
check(t and t["source"] == "FPGA" and t["replay_mismatches"] == 0,
      f"trellis prefix from FPGA, {t and t['replay_checked']} windows, 0 mismatches")
check(t and t["truncated"] and t["n_info_bits"] == 200, "trellis covers first 200 bits")

print("=== compare all K, 10% ===")
msg = "Compare every constraint length on the same noisy channel. " * 3
j = wait(post("/api/decode", {"message": msg, "error_rate": 10, "compare": True})["job_id"])
r = j["result"]
check(j["status"] == "done" and r["type"] == "compare", f"status {j['status']}")
ks = [x["k"] for x in r["runs"]]
check(ks == [3, 5, 7, 9], f"runs for K={ks}")
for x in r["runs"]:
    print(f"    K={x['k']}: {x['bit_errors']:3d} bit errors, {x['num_errors_injected']} hits, "
          f"{x['n_frames']} frames, {x['hw_ms']} ms, {x['throughput_kbps']} kbit/s")
print(f"    uncoded: {r['uncoded_bit_errors']} bit errors")

print("=== image 160x120, K=7, 10% ===")
w, h = 160, 120
px = bytes((x * 255 // w) ^ ((y // 8) % 2) * 0x40 for y in range(h) for x in range(w))
j = wait(post("/api/decode_image", {"width": w, "height": h, "error_rate": 10, "k": 7,
                                    "pixels": base64.b64encode(px).decode()})["job_id"])
r = j["result"]
check(j["status"] == "done" and r["type"] == "image", f"status {j['status']}")
run = r["runs"][0]
dec = base64.b64decode(run["decoded_b64"])
check(len(dec) == w * h, f"{len(dec)} pixels back")
check(sum(a != b for a, b in zip(px, dec)) == 0 or run["bit_errors"] < r["uncoded_bit_errors"],
      f"coded {run['bit_errors']} bit errors vs uncoded {r['uncoded_bit_errors']}")
print(f"    {run['n_frames']} frames, FPGA {run['hw_ms']} ms, {run['throughput_kbps']} kbit/s")

print("=== image compare all K, 10% ===")
j = wait(post("/api/decode_image", {"width": w, "height": h, "error_rate": 10, "compare": True,
                                    "pixels": base64.b64encode(px).decode()})["job_id"], 180)
r = j["result"]
check(j["status"] == "done" and len(r["runs"]) == 4, f"status {j['status']}, {len(r.get('runs', []))} runs")
for x in r["runs"]:
    print(f"    K={x['k']}: {x['bit_errors']:5d} bit errors, {x['n_frames']} frames, "
          f"{x['hw_ms']} ms, {x['throughput_kbps']} kbit/s")
print(f"    uncoded: {r['uncoded_bit_errors']} bit errors")

print("\nALL PASS" if not fails else f"\n{fails} FAILED")
sys.exit(1 if fails else 0)
