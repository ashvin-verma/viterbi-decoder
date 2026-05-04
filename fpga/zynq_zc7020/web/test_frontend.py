#!/usr/bin/env python3
"""Frontend + multi-user tests for Viterbi Decoder web demo."""

import time
import sys
import json
import threading
import requests
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait, Select
from selenium.webdriver.support import expected_conditions as EC

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


def wait_decode_result(driver, prev_text="-", timeout=60):
    """Wait for decode result, handling FPGA async polling."""
    for _ in range(timeout * 2):
        txt = driver.find_element(By.ID, "result-text").text
        btn = driver.find_element(By.ID, "send-btn")
        if txt not in ("", "-", prev_text) and btn.text == "Decode":
            return txt
        time.sleep(0.5)
    return driver.find_element(By.ID, "result-text").text


def api_decode_sync(message, k=7, error_rate=0, timeout=60):
    """Submit decode via API and poll until done. Returns result dict."""
    r = requests.post(f"{BASE}/api/decode", json={
        "message": message, "error_rate": error_rate, "k": k
    }, timeout=10)
    data = r.json()
    if not data.get("async"):
        return data
    job_id = data["job_id"]
    for _ in range(timeout * 2):
        r = requests.get(f"{BASE}/api/job/{job_id}", timeout=10)
        j = r.json()
        if j["status"] in ("done", "error"):
            return j.get("result", j)
        time.sleep(0.5)
    return {"error": "timeout"}


def run_ui_tests():
    global PASS, FAIL
    driver = webdriver.Edge()
    driver.set_window_size(1200, 900)

    try:
        # =================================================================
        print("\n=== 1. Page Load ===")
        # =================================================================
        driver.get(BASE)
        time.sleep(2)

        check("Title", "Viterbi" in driver.title)
        check("H1 visible", driver.find_element(By.TAG_NAME, "h1").is_displayed())
        check("Subtitle", driver.find_element(By.ID, "subtitle").is_displayed())
        check("Footer", driver.find_element(By.ID, "footer-text").is_displayed())

        logs = driver.get_log("browser")
        js_errors = [l for l in logs if l["level"] == "SEVERE"]
        check("No JS errors on load", len(js_errors) == 0,
              str(js_errors[:3]) if js_errors else "")

        # =================================================================
        print("\n=== 2. UI Elements ===")
        # =================================================================
        for eid in ["message-input", "send-btn", "error-slider", "k-select",
                    "mode-toggle-btn", "program-btn", "status-bar",
                    "activity-log"]:
            check(f"#{eid} present", driver.find_element(By.ID, eid).is_displayed())
        check("#queue-indicator exists",
              driver.find_element(By.ID, "queue-indicator") is not None)

        # =================================================================
        print("\n=== 3. Status Loaded ===")
        # =================================================================
        status_text = driver.find_element(By.ID, "status-text").text
        check("Status populated", len(status_text) > 5, status_text)
        check("Not stuck on 'Checking'", "Checking" not in status_text)

        # =================================================================
        print("\n=== 4. K Selector ===")
        # =================================================================
        k_select = Select(driver.find_element(By.ID, "k-select"))
        vals = [o.get_attribute("value") for o in k_select.options]
        check("K options: 3,5,7,9", vals == ["3", "5", "7", "9"], str(vals))
        check("K=7 default", k_select.first_selected_option.get_attribute("value") == "7")

        # =================================================================
        print("\n=== 5. FPGA Decode: 'Hello' (K=7, 0%) ===")
        # =================================================================
        msg = driver.find_element(By.ID, "message-input")
        msg.clear()
        msg.send_keys("Hello")
        driver.execute_script(
            "document.getElementById('error-slider').value=0;"
            "document.getElementById('error-value').textContent='0%';")
        driver.find_element(By.ID, "send-btn").click()

        result = wait_decode_result(driver)
        check("Decoded 'Hello'", result == "Hello", f"got '{result}'")

        ber = driver.find_element(By.ID, "result-decoded-ber").text
        check("0% BER", "0" in ber and "%" in ber, ber)

        pipe = driver.find_element(By.ID, "pipe-decoded").text
        check("Pipeline shows decode method", len(pipe) > 3, pipe)

        verdict = driver.find_element(By.ID, "verdict")
        check("Verdict visible", verdict.is_displayed())
        check("Verdict class 'perfect'", "perfect" in verdict.get_attribute("class"))

        # =================================================================
        print("\n=== 6. Decode with Noise (K=7, 15%) ===")
        # =================================================================
        driver.execute_script(
            "document.getElementById('error-slider').value=15;"
            "document.getElementById('error-value').textContent='15%';")
        msg.clear()
        msg.send_keys("Test 123")
        driver.find_element(By.ID, "send-btn").click()

        result = wait_decode_result(driver, prev_text="Hello")
        check("Noisy decode returned text", len(result) > 0, result)

        injected = driver.find_element(By.ID, "result-injected").text
        check("Errors injected", "0 /" not in injected, injected)

        sym_cells = driver.find_elements(By.CSS_SELECTOR, "#symbol-grid .sym-cell")
        check("Symbol grid has cells", len(sym_cells) > 10, f"{len(sym_cells)}")

        err_cells = driver.find_elements(By.CSS_SELECTOR, "#symbol-grid .error")
        check("Error cells exist", len(err_cells) > 0, f"{len(err_cells)}")

        # =================================================================
        print("\n=== 7. Switch K ===")
        # =================================================================
        k_select = Select(driver.find_element(By.ID, "k-select"))
        k_select.select_by_value("3")
        time.sleep(0.5)

        sub = driver.find_element(By.ID, "subtitle").text
        check("Subtitle says K=3", "K=3" in sub, sub)

        footer = driver.find_element(By.ID, "footer-text").text
        check("Footer says K=3", "K=3" in footer, footer)

        # Decode with K=3
        driver.execute_script("document.getElementById('error-slider').value=0;")
        msg.clear()
        msg.send_keys("AB")
        driver.find_element(By.ID, "send-btn").click()
        result = wait_decode_result(driver, prev_text="Test 123", timeout=60)
        check("K=3 decode", result == "AB", f"got '{result}'")

        # Switch back
        k_select = Select(driver.find_element(By.ID, "k-select"))
        k_select.select_by_value("7")
        time.sleep(0.5)

        # =================================================================
        print("\n=== 8. Error Slider ===")
        # =================================================================
        driver.execute_script(
            "document.getElementById('error-slider').value=42;"
            "document.getElementById('error-slider').dispatchEvent(new Event('input'));")
        val = driver.find_element(By.ID, "error-value").text
        check("Slider display", val == "42%", val)

        # =================================================================
        print("\n=== 9. Enter Key ===")
        # =================================================================
        driver.execute_script("document.getElementById('error-slider').value=0;")
        msg.clear()
        msg.send_keys("XY")
        msg.send_keys(Keys.RETURN)
        result = wait_decode_result(driver, prev_text="AB")
        check("Enter triggers decode", result == "XY", f"got '{result}'")

        # =================================================================
        print("\n=== 10. Activity Log ===")
        # =================================================================
        time.sleep(6)  # wait for auto-refresh
        entries = driver.find_elements(By.CSS_SELECTOR, "#activity-log .activity-entry")
        check("Activity has entries", len(entries) >= 3, f"{len(entries)}")

        # =================================================================
        print("\n=== 11. Dark Theme ===")
        # =================================================================
        bg = driver.execute_script(
            "return getComputedStyle(document.body).backgroundColor;")
        check("Dark background", "255, 255, 255" not in bg, bg)

        cards = driver.find_elements(By.CLASS_NAME, "card")
        check("Cards rendered", len(cards) >= 5, f"{len(cards)}")

        # =================================================================
        print("\n=== 12. Final Console Check ===")
        # =================================================================
        logs = driver.get_log("browser")
        js_errors = [l for l in logs if l["level"] == "SEVERE"]
        check("No JS errors after tests", len(js_errors) == 0,
              str(js_errors[:3]) if js_errors else "")

    finally:
        driver.quit()


def run_multiuser_tests():
    """Simulate concurrent users hitting the API."""
    print("\n=== 13. Multi-User Concurrent Decodes ===")

    results = {}
    errors = []

    def user_decode(user_id, message, k):
        try:
            r = api_decode_sync(message, k=k, error_rate=0, timeout=90)
            results[user_id] = r
        except Exception as e:
            errors.append(f"User {user_id}: {e}")

    # Launch 3 concurrent FPGA decode requests with different K values
    threads = []
    users = [
        ("user1", "AAA", 7),
        ("user2", "BBB", 7),
        ("user3", "CCC", 7),
    ]
    for uid, msg, k in users:
        t = threading.Thread(target=user_decode, args=(uid, msg, k))
        threads.append(t)

    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=120)

    check("All 3 users got responses", len(results) == 3,
          f"got {len(results)}, errors: {errors}")

    for uid, msg, k in users:
        if uid in results:
            r = results[uid]
            decoded = r.get("decoded_text", "")
            check(f"{uid}: '{msg}' decoded correctly",
                  decoded == msg, f"got '{decoded}'")

    # Check queue processed sequentially (no corruption)
    check("No thread errors", len(errors) == 0, str(errors))

    # Test concurrent different-K requests
    print("\n=== 14. Multi-User Different K ===")
    results.clear()
    errors.clear()

    users_k = [
        ("userA", "Hi", 3),
        ("userB", "Hi", 7),
    ]
    threads = []
    for uid, msg, k in users_k:
        t = threading.Thread(target=user_decode, args=(uid, msg, k))
        threads.append(t)

    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=120)

    for uid, msg, k in users_k:
        if uid in results:
            r = results[uid]
            decoded = r.get("decoded_text", "")
            if r.get("error"):
                check(f"{uid} K={k}: expected error (no bitstream)",
                      "bitstream" in r["error"].lower() or "No bitstream" in r["error"],
                      r["error"])
            else:
                check(f"{uid} K={k}: '{msg}' correct",
                      decoded == msg, f"got '{decoded}'")

    check("No errors in multi-K", len(errors) == 0, str(errors))

    # Rate limiting test
    print("\n=== 15. Rate Limiting ===")
    rate_limited = False
    for i in range(10):
        r = requests.post(f"{BASE}/api/decode", json={
            "message": "X", "error_rate": 0, "k": 7
        }, timeout=10)
        if r.status_code == 429:
            rate_limited = True
            break
    check("Rate limiter triggers", rate_limited, "never hit 429")


if __name__ == "__main__":
    run_ui_tests()
    run_multiuser_tests()

    total = PASS + FAIL
    print(f"\n{'='*50}")
    print(f"  {PASS}/{total} passed, {FAIL} failed")
    print(f"{'='*50}")
    sys.exit(0 if FAIL == 0 else 1)
