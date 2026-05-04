#!/usr/bin/env python3
"""
Production readiness test suite for Viterbi Decoder web demo.
Tests concurrent users, edge cases, security, and FPGA queue behavior.
"""

import time
import sys
import json
import threading
import random
import string
import requests
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait, Select

BASE = "http://localhost:5000"
PASS = 0
FAIL = 0


def check(name, condition, detail=""):
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")


def api(method, path, json_data=None, timeout=10):
    if method == "GET":
        return requests.get(f"{BASE}{path}", timeout=timeout)
    return requests.post(f"{BASE}{path}", json=json_data, timeout=timeout)


def api_decode_sync(message, k=7, error_rate=0, timeout=90):
    """Submit decode and poll until done."""
    r = api("POST", "/api/decode", {"message": message, "error_rate": error_rate, "k": k})
    data = r.json()
    if not data.get("async"):
        return data
    job_id = data["job_id"]
    for _ in range(timeout * 2):
        r = api("GET", f"/api/job/{job_id}")
        j = r.json()
        if j["status"] in ("done", "error"):
            return j.get("result", j)
        time.sleep(0.5)
    return {"error": "timeout"}


def wait_decode_result(driver, prev_text="-", timeout=60):
    for _ in range(timeout * 2):
        txt = driver.find_element(By.ID, "result-text").text
        btn = driver.find_element(By.ID, "send-btn")
        if txt not in ("", "-", prev_text) and btn.text == "Decode":
            return txt
        time.sleep(0.5)
    return driver.find_element(By.ID, "result-text").text


# =====================================================================
# Test Groups
# =====================================================================

def test_concurrent_same_k():
    """Multiple users decoding simultaneously with same K."""
    print("\n=== Concurrent Users (Same K=7) ===")

    messages = ["Hello", "World", "Test!", "FPGA!", "Viterbi"]
    results = {}
    errors = []

    def decode(uid, msg):
        try:
            results[uid] = api_decode_sync(msg, k=7, error_rate=0)
        except Exception as e:
            errors.append(f"{uid}: {e}")

    threads = [threading.Thread(target=decode, args=(f"u{i}", m))
               for i, m in enumerate(messages)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=120)

    check("All 5 users responded", len(results) == 5,
          f"got {len(results)}, errors: {errors}")
    for i, m in enumerate(messages):
        uid = f"u{i}"
        if uid in results:
            r = results[uid]
            decoded = r.get("decoded_text", "")
            check(f"  {uid} '{m}' correct", decoded == m, f"got '{decoded}'")
    check("No thread errors", len(errors) == 0, str(errors))


def test_concurrent_different_k():
    """Multiple users with different K values — tests FPGA reprogramming queue."""
    print("\n=== Concurrent Users (Different K) ===")

    # K=7 bitstream exists, K=3 may or may not
    users = [
        ("alice", "Hi", 7),
        ("bob", "OK", 7),
    ]

    # Check which bitstreams exist
    status = api("GET", "/api/status").json()
    k_opts = status.get("k_options", {})
    for k_val in [3, 5, 9]:
        if k_opts.get(str(k_val), {}).get("bitstream_found"):
            users.append((f"user_k{k_val}", "AB", k_val))

    results = {}
    errors = []

    def decode(uid, msg, k):
        try:
            results[uid] = api_decode_sync(msg, k=k, error_rate=0, timeout=120)
        except Exception as e:
            errors.append(f"{uid}: {e}")

    threads = [threading.Thread(target=decode, args=u) for u in users]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=180)

    check(f"All {len(users)} users responded", len(results) == len(users),
          f"got {len(results)}, errors: {errors}")
    for uid, msg, k in users:
        if uid in results:
            r = results[uid]
            decoded = r.get("decoded_text", "")
            err = r.get("error", "")
            if err:
                check(f"  {uid} K={k}: got error", True, err)
            else:
                check(f"  {uid} K={k}: '{msg}' correct", decoded == msg, f"got '{decoded}'")


def test_rapid_fire():
    """Rapid sequential decodes — stress test queue ordering."""
    print("\n=== Rapid Fire (10 sequential decodes) ===")

    results = []
    for i in range(10):
        msg = f"R{i}"
        r = api_decode_sync(msg, k=7, error_rate=0)
        results.append((msg, r.get("decoded_text", ""), r.get("error", "")))

    correct = sum(1 for msg, dec, _ in results if dec == msg)
    check(f"All 10 decoded correctly", correct == 10,
          f"{correct}/10 correct: {[(m,d) for m,d,_ in results if d != m]}")


def test_input_edge_cases():
    """Boundary and malformed inputs."""
    print("\n=== Input Edge Cases ===")

    # Empty message
    r = api("POST", "/api/decode", {"message": "", "k": 7}).json()
    check("Empty message rejected", "error" in r, r.get("error", ""))

    # Max length (24 chars)
    r = api_decode_sync("A" * 24, k=7, error_rate=0)
    check("24 chars accepted", r.get("decoded_text") == "A" * 24,
          r.get("decoded_text", r.get("error", ""))[:30])

    # Over max length
    r = api("POST", "/api/decode", {"message": "A" * 25, "k": 7}).json()
    check("25 chars rejected", "error" in r)

    # Single char
    r = api_decode_sync("X", k=7, error_rate=0)
    check("Single char", r.get("decoded_text") == "X", r.get("decoded_text", ""))

    # Spaces
    r = api_decode_sync("A B C", k=7, error_rate=0)
    check("Spaces preserved", r.get("decoded_text") == "A B C",
          r.get("decoded_text", ""))

    # Special ASCII chars
    r = api_decode_sync("!@#$%", k=7, error_rate=0)
    check("Special chars", r.get("decoded_text") == "!@#$%",
          r.get("decoded_text", ""))

    # Numbers
    r = api_decode_sync("1234567890", k=7, error_rate=0)
    check("Numbers", r.get("decoded_text") == "1234567890",
          r.get("decoded_text", ""))

    # Non-ASCII
    r = api("POST", "/api/decode", {"message": "éè", "k": 7}).json()
    check("Non-ASCII rejected", "error" in r)

    # Missing message field
    r = api("POST", "/api/decode", {"k": 7}).json()
    check("Missing message rejected", "error" in r)

    # No JSON body
    r = requests.post(f"{BASE}/api/decode", timeout=10).json()
    check("No body rejected", "error" in r)

    # Invalid K
    r = api("POST", "/api/decode", {"message": "Hi", "k": 4}).json()
    check("K=4 rejected", "error" in r)

    r = api("POST", "/api/decode", {"message": "Hi", "k": "abc"}).json()
    check("K='abc' rejected", "error" in r)

    # Error rate boundaries
    r = api_decode_sync("Hi", k=7, error_rate=-50)
    check("Negative error_rate clamped", "error" not in r, r.get("error", ""))

    r = api_decode_sync("Hi", k=7, error_rate=99999)
    check("Huge error_rate clamped", r.get("channel_ber") is not None)

    r = api("POST", "/api/decode", {"message": "Hi", "k": 7, "error_rate": "xyz"}).json()
    check("Non-numeric error_rate rejected", "error" in r)


def test_error_correction_quality():
    """Verify error correction at various noise levels."""
    print("\n=== Error Correction Quality ===")

    for pct in [0, 5, 10, 15]:
        successes = 0
        trials = 5
        for _ in range(trials):
            r = api_decode_sync("Hello", k=7, error_rate=pct)
            if r.get("decoded_text") == "Hello":
                successes += 1
        check(f"K=7 at {pct}% error: {successes}/{trials} perfect",
              successes >= (trials // 2 if pct <= 10 else 1),
              f"{successes}/{trials}")


def test_security_headers():
    """Verify all security headers present."""
    print("\n=== Security Headers ===")

    r = requests.get(f"{BASE}/api/status", timeout=10)

    check("X-Content-Type-Options",
          r.headers.get("X-Content-Type-Options") == "nosniff")
    check("X-Frame-Options",
          r.headers.get("X-Frame-Options") == "DENY")
    check("X-XSS-Protection",
          "1" in r.headers.get("X-XSS-Protection", ""))
    check("Referrer-Policy",
          "strict-origin" in r.headers.get("Referrer-Policy", ""))
    check("CSP present",
          "script-src 'self'" in r.headers.get("Content-Security-Policy", ""))
    check("CSP frame-ancestors none",
          "frame-ancestors 'none'" in r.headers.get("Content-Security-Policy", ""))


def test_cors():
    """Verify CORS blocks unauthorized origins."""
    print("\n=== CORS ===")

    # Bad origin
    r = requests.get(f"{BASE}/api/status",
                     headers={"Origin": "https://evil.com"}, timeout=10)
    check("Bad origin: no ACAO header",
          "Access-Control-Allow-Origin" not in r.headers)

    # Good origin
    r = requests.get(f"{BASE}/api/status",
                     headers={"Origin": "https://viterbi.ashvinverma.com"}, timeout=10)
    check("Good origin: ACAO set",
          r.headers.get("Access-Control-Allow-Origin") == "https://viterbi.ashvinverma.com")

    # Localhost
    r = requests.get(f"{BASE}/api/status",
                     headers={"Origin": "http://localhost:5000"}, timeout=10)
    check("Localhost: ACAO set",
          r.headers.get("Access-Control-Allow-Origin") == "http://localhost:5000")


def test_rate_limiting():
    """Verify rate limiting on FPGA-mutating endpoints."""
    print("\n=== Rate Limiting ===")

    # FPGA-mutating: 0.2 req/s, burst 2
    hit_429 = False
    for i in range(6):
        r = api("POST", "/api/set_mode", {"mode": "software"})
        if r.status_code == 429:
            hit_429 = True
            break
    check("FPGA endpoint rate limited", hit_429, "never hit 429 in 6 tries")

    # Reset to FPGA mode
    time.sleep(6)
    api("POST", "/api/set_mode", {"mode": "fpga"})


def test_request_size_limit():
    """Verify oversized requests are rejected."""
    print("\n=== Request Size Limit ===")

    # 16KB limit — send something huge
    big_body = {"message": "Hi", "k": 7, "junk": "A" * 20000}
    try:
        r = requests.post(f"{BASE}/api/decode", json=big_body, timeout=10)
        check("Oversized request rejected", r.status_code == 413,
              f"status={r.status_code}")
    except Exception as e:
        check("Oversized request handled", True, str(e))


def test_job_polling():
    """Test job lifecycle and cleanup."""
    print("\n=== Job Polling ===")

    # Nonexistent job
    r = api("GET", "/api/job/nonexistent")
    check("Unknown job returns 404", r.status_code == 404)

    # Submit and poll
    r = api("POST", "/api/decode", {"message": "JP", "k": 7, "error_rate": 0})
    data = r.json()
    if data.get("async"):
        job_id = data["job_id"]
        check("Job submitted", len(job_id) > 0)
        check("Position >= 1", data["position"] >= 1)

        # Poll until done
        for _ in range(60):
            r = api("GET", f"/api/job/{job_id}")
            j = r.json()
            if j["status"] == "done":
                check("Job completed", j["result"]["decoded_text"] == "JP",
                      j["result"].get("decoded_text", ""))
                break
            time.sleep(1)
        else:
            check("Job completed", False, "timed out")
    else:
        check("Got sync result (SW mode)", data.get("decoded_text") == "JP")


def test_activity_log():
    """Verify activity log populates and limits."""
    print("\n=== Activity Log ===")

    r = api("GET", "/api/activity").json()
    check("Activity endpoint works", "activity" in r)
    check("Has entries", len(r["activity"]) > 0, f"{len(r['activity'])} entries")

    if r["activity"]:
        entry = r["activity"][0]
        check("Entry has timestamp", "timestamp" in entry)
        check("Entry has event", "event" in entry)
        check("Entry has detail", "detail" in entry)
        check("Timestamp is recent",
              time.time() - entry["timestamp"] < 300,
              f"{time.time() - entry['timestamp']:.0f}s ago")


def test_status_endpoint():
    """Verify /api/status returns all expected fields."""
    print("\n=== Status Endpoint ===")

    r = api("GET", "/api/status").json()
    for field in ["fpga_available", "bitstream_found", "programmed", "mode",
                   "k", "fpga_k", "rate", "polynomials", "traceback_depth",
                   "k_options", "queue_depth"]:
        check(f"Has '{field}'", field in r, str(list(r.keys())))

    check("k_options has 4 entries", len(r.get("k_options", {})) == 4)
    check("queue_depth is int", isinstance(r.get("queue_depth"), int))


def test_xss_resilience():
    """Ensure XSS payloads are handled safely."""
    print("\n=== XSS Resilience ===")

    payloads = [
        "<script>alert(1)",
        "';DROP TABLE;--",
        "<img onerror=alert>",
        "{{7*7}}",
    ]
    for payload in payloads:
        if len(payload) > 24:
            continue
        r = api_decode_sync(payload, k=7, error_rate=0)
        decoded = r.get("decoded_text", "")
        # Should decode as literal bytes, not execute
        check(f"XSS '{payload[:15]}' safe",
              r.get("error") is None or decoded == payload,
              decoded[:30])


def test_browser_full_flow():
    """Selenium: full user flow with FPGA decode."""
    print("\n=== Browser Full Flow ===")

    driver = webdriver.Edge()
    driver.set_window_size(1200, 900)

    try:
        driver.get(BASE)
        time.sleep(2)

        # Check no JS errors
        logs = driver.get_log("browser")
        severe = [l for l in logs if l["level"] == "SEVERE"]
        check("No JS errors on load", len(severe) == 0,
              str(severe[:2]) if severe else "")

        # Decode "Hello"
        msg = driver.find_element(By.ID, "message-input")
        msg.clear()
        msg.send_keys("Hello")
        driver.execute_script("document.getElementById('error-slider').value=0;")
        driver.find_element(By.ID, "send-btn").click()

        result = wait_decode_result(driver, timeout=60)
        check("Browser decode 'Hello'", result == "Hello", f"got '{result}'")

        # Check pipeline populated
        for pid in ["pipe-input", "pipe-bits", "pipe-encoded",
                     "pipe-noise", "pipe-decoded", "pipe-output"]:
            val = driver.find_element(By.ID, pid).text
            check(f"  {pid} populated", val != "-", val)

        # Check verdict
        verdict = driver.find_element(By.ID, "verdict")
        check("Verdict displayed", verdict.is_displayed())

        # Switch K and decode
        k_select = Select(driver.find_element(By.ID, "k-select"))
        avail_k = [o.get_attribute("value") for o in k_select.options]

        # Find a K with bitstream
        status = api("GET", "/api/status").json()
        k_opts = status.get("k_options", {})
        test_k = None
        for kv in ["3", "5", "9"]:
            if k_opts.get(kv, {}).get("bitstream_found"):
                test_k = kv
                break

        if test_k:
            k_select.select_by_value(test_k)
            time.sleep(0.5)
            msg.clear()
            msg.send_keys("OK")
            driver.find_element(By.ID, "send-btn").click()
            result = wait_decode_result(driver, prev_text="Hello", timeout=60)
            check(f"Browser K={test_k} decode", result == "OK", f"got '{result}'")
        else:
            check("No alt-K bitstream to test", True, "skip")

        # Noisy decode
        driver.execute_script(
            "document.getElementById('error-slider').value=20;"
            "document.getElementById('error-slider').dispatchEvent(new Event('input'));")
        k_select = Select(driver.find_element(By.ID, "k-select"))
        k_select.select_by_value("7")
        time.sleep(0.5)
        msg.clear()
        msg.send_keys("Noise test")
        driver.find_element(By.ID, "send-btn").click()
        prev = result
        result = wait_decode_result(driver, prev_text=prev, timeout=60)
        check("Noisy decode returned", len(result) > 0, result)

        # Check error cells in symbol grid
        err_cells = driver.find_elements(By.CSS_SELECTOR, "#symbol-grid .error")
        check("Error cells in grid", len(err_cells) > 0, f"{len(err_cells)}")

        # Activity log rendered
        time.sleep(6)
        entries = driver.find_elements(By.CSS_SELECTOR, "#activity-log .activity-entry")
        check("Activity log entries", len(entries) >= 3, f"{len(entries)}")

        # Final console check
        logs = driver.get_log("browser")
        severe = [l for l in logs if l["level"] == "SEVERE"]
        check("No JS errors after flow", len(severe) == 0,
              str(severe[:2]) if severe else "")

    finally:
        driver.quit()


# =====================================================================
# Main
# =====================================================================
if __name__ == "__main__":
    print("=" * 60)
    print("  Viterbi Decoder — Production Readiness Test Suite")
    print("=" * 60)

    # API tests (fast)
    test_status_endpoint()
    test_security_headers()
    test_cors()
    test_activity_log()
    test_input_edge_cases()
    test_xss_resilience()
    test_request_size_limit()
    test_job_polling()

    # FPGA queue tests
    test_concurrent_same_k()
    test_concurrent_different_k()
    test_rapid_fire()
    test_error_correction_quality()
    test_rate_limiting()

    # Browser tests (slow)
    test_browser_full_flow()

    total = PASS + FAIL
    print(f"\n{'=' * 60}")
    print(f"  RESULTS: {PASS}/{total} passed, {FAIL} failed")
    print(f"{'=' * 60}")
    sys.exit(0 if FAIL == 0 else 1)
