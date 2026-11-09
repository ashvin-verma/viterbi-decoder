"""End-to-end hardware checks for trellis capture + on-chip BER tester.

Runs against a live server in FPGA mode (default http://localhost:5000):
    python test_hw_features.py [base_url] [k ...]

For each K:
  * decode with trellis=True -> trellis must come from FPGA BRAM, and the
    hardware traceback replay must reproduce every emitted bit
  * BER sweep -> measured channel flip rate must match the programmed p,
    decoded BER must beat the channel at moderate SNR
"""
import math
import sys
import time

import requests

BASE = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1].startswith("http") else "http://localhost:5000"
KS = [int(a) for a in sys.argv[1:] if a.isdigit()] or [7]

failures = []


def check(cond, msg):
    print(("  PASS " if cond else "  FAIL ") + msg)
    if not cond:
        failures.append(msg)


def wait_job(job_id, timeout=240):
    t0 = time.time()
    while time.time() - t0 < timeout:
        j = requests.get(f"{BASE}/api/job/{job_id}", timeout=10).json()
        if j.get("status") in ("done", "error"):
            return j
        time.sleep(1)
    raise TimeoutError(job_id)


for k in KS:
    print(f"=== K={k} ===")
    for msg, rate in (("Hello FPGA trellis", 5), ("ABCDEFGHIJKLMNOPQRSTUVWX", 8)):
        r = requests.post(f"{BASE}/api/decode", json={
            "message": msg, "error_rate": rate, "k": k, "trellis": True}, timeout=10).json()
        j = wait_job(r["job_id"])
        res = j["result"]
        check(j["status"] == "done", f"decode {msg!r} finished ({j['status']})")
        tr = res.get("trellis") or {}
        check(tr.get("source") == "FPGA", f"trellis source is FPGA ({tr.get('source')})")
        check(tr.get("replay_checked", 0) >= res["info_bits"],
              f"replayed {tr.get('replay_checked')} windows >= {res['info_bits']} info bits")
        check(tr.get("replay_mismatches") == 0,
              f"replay mismatches = {tr.get('replay_mismatches')}")
        check(tr.get("n_states") == 1 << (k - 1), f"n_states = {tr.get('n_states')}")
        if k <= 7:
            check("path_metrics" in tr, "path metrics present")
        print(f"    decoded={res['decoded_text']!r} errors_in={res['num_errors_injected']} "
              f"bit_errors={res['bit_errors']} fpga_ms={res['decode_time_ms']}")

    for _ in range(5):
        resp = requests.post(f"{BASE}/api/ber/sweep", json={"k": k}, timeout=10)
        if resp.status_code != 429:
            break
        print("    (rate limited: 1 sweep/min per IP, waiting)")
        time.sleep(61)
    r = resp.json()
    if "job_id" not in r:
        check(False, f"sweep queued: {r}")
        continue
    j = wait_job(r["job_id"], timeout=400)
    res = j["result"]
    check(j["status"] == "done", f"sweep finished ({j['status']}: {res.get('error', '')})")
    pts = res.get("points", [])
    check(len(pts) == res.get("total"), f"{len(pts)} points")
    for pt in pts:
        # channel flip rate within 5 sigma of target
        n = pt["channel_bits"]
        p = pt["p_target"]
        sigma = math.sqrt(p * (1 - p) / n) if n else 1
        ok = n > 0 and abs(pt["channel_ber"] - p) < 5 * sigma + 1e-9
        check(ok, f"Eb/N0={pt['ebn0_db']}: channel {pt['channel_ber']:.4g} vs p {p:.4g} "
                  f"(n={n}, 5sigma={5*sigma:.2g})")
        if pt["ebn0_db"] >= 4:
            check(pt["ber"] is not None and pt["ber"] < pt["channel_ber"],
                  f"Eb/N0={pt['ebn0_db']}: decoded {pt['ber']} < channel {pt['channel_ber']:.3g} "
                  f"({pt['errors']}/{pt['bits']}, {pt['mbps']} Mbit/s)")
    print(f"    lanes={res.get('lanes')} total bits={sum(p['bits'] for p in pts):,}")

print()
print("ALL PASS" if not failures else f"{len(failures)} FAILURES")
sys.exit(1 if failures else 0)
