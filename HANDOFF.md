# K=5 Viterbi Decoder - Handoff Notes

## Current State (2026-02-28)

### RTL Upgrade: K=3 -> K=5 - COMPLETE
- **K=5**, M=4, S=16 states, D=24 traceback depth, Wm=6 bits
- G0=0o23 (10011), G1=0o35 (11101) - NASA standard rate-1/2
- d_free=7, corrects up to 3 bit errors
- Tile size: **2x2** (1x2 was too small - see below)

### Critical RTL Bug Fixes Applied
1. **viterbi_core.v line 97 - FSM race condition:**
   Changed `!tb_busy` to `!tb_busy && !tb_start` in ST_TRACE.
   At K=5, traceback (D=24 cycles) takes longer than sweep (S=16 cycles),
   so the FSM would exit ST_TRACE before traceback started. The `tb_start`
   guard covers the 1-cycle busy propagation delay.

2. **traceback_v2.v - Pipeline stall fix:**
   Changed from registered `surv_q` to combinational `tb_surv_bit` in
   TB_PRIME and TB_RUN states. The registered version was stale because
   the address hadn't propagated when it was captured.

Both bugs were masked at K=3 (D=8 < S=4 sweep time) but exposed at K=5.

### Tests - ALL 14 PASS
```bash
# Run tests (use gmake on macOS, not make)
PATH=".venv/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  SIM=icarus gmake -C test
```

Test suite (test/test.py):
- test_viterbi_core_smoke - FSM alive check
- test_encoder_vs_commpy - Cross-validates our encoder against scikit-commpy
- test_all_zeros - Trivial pattern
- test_all_ones - Trivial pattern
- test_noiseless_roundtrip - 32 random bits, 0 errors
- test_commpy_golden_comparison - DUT vs commpy decoder (definitive golden test)
- test_single_error_correction - 1 flip corrected
- test_double_error_correction - 2 flips corrected
- test_triple_error_correction - 3 flips corrected (K=5 showcase)
- test_error_beyond_capacity - 4+ flips, asserts errors > 0
- test_multiple_frames - Reset between 3 frames
- test_long_frame - 128-bit frame
- test_wrong_polynomial_expected_failure - Verifies wrong polys fail
- test_throughput - Measures decoder throughput

### Sky130 Hardening - COMPLETE
```
runs_sky130_k5/final/gds/tt_um_ashvin_viterbi.gds
```

**Results:**
| Metric | Value |
|--------|-------|
| Tile | 2x2 (334.88 x 225.76 um) |
| Die area | 75,603 um^2 |
| Cell count | 12,103 |
| Utilization | 68.4% |
| DRC errors | 0 |
| LVS errors | 0 |
| Antenna violations | 0 |
| Setup WNS (typ tt) | +9.34 ns (clean) |
| Setup WNS (slow ss) | -1.17 ns (10 violations, extreme corner) |
| Hold violations | 0 (all corners) |
| Total power (typ) | 5.4 mW @ 50 MHz |

The slow-slow corner (ss, 100C, 1.60V) has 10 setup violations - this is the
extreme pessimistic PVT corner. Nominal and fast corners are clean.

**Why 2x2 not 1x2:** The K=5 design has 41,913 um^2 of logic (16 trellis
states, D=24 survivor memory, 6-bit path metrics). The 1x2 tile only has
34,255 um^2 core area -> 126.7% utilization, impossible. The 2x2 tile gives
72,565 um^2 core -> 68.4% utilization, healthy headroom.

### IHP SG13G2 Hardening - BLOCKED (needs PC)

**Issue:** The librelane 3.0.0.dev44 container's IHP PDK config has a
compatibility bug: `KLAYOUT_DRC_OPTIONS.run_mode = 'deep'` (string) but
librelane expects `bool|int`. The dev52 container might fix this.

**To resume on PC:**

```bash
# 1. Activate venv
source .venv/bin/activate

# 2. Install correct librelane version (try dev52 first, fall back to dev44)
uv pip install librelane==3.0.0.dev52

# 3. Create user config for IHP
export PDK=ihp-sg13g2
export LIBRELANE_TAG=3.0.0.dev52
# Note: do NOT set PDK_ROOT for IHP - the container has the PDK built in
python tt/tt_tool.py --ihp --create-user-config

# 4. Harden
python tt/tt_tool.py --ihp --harden

# 5. If dev52 fails with KLAYOUT_DRC_OPTIONS error, try dev44:
uv pip install librelane==3.0.0.dev44
export LIBRELANE_TAG=3.0.0.dev44
python tt/tt_tool.py --ihp --harden

# 6. If both fail, try setting PDK_ROOT to the IHP PDK:
#    git clone https://github.com/IHP-GmbH/IHP-Open-PDK ~/ttsetup/ihp-pdk
#    export PDK_ROOT=~/ttsetup/ihp-pdk
#    Then retry --harden

# 7. Save results
cp -r runs/wokwi/ runs_ihp_k5/
```

**IHP config notes:**
- Die area: 419.52 x 313.74 um (2x2 tile, larger than Sky130)
- DEF template: tt_block_2x2_pgvdd.def
- Top metal: Metal5 (vs Sky130's met4)
- Supply: 1.5V (vs Sky130's 1.8V)

### PPA Comparison - PENDING
After IHP hardening completes, extract metrics from both
`runs_sky130_k5/final/metrics.json` and `runs_ihp_k5/final/metrics.json`
for side-by-side comparison.

## File Summary

### RTL (all parameterized, auto-scale with K/D/Wm)
- `src/project.v` - Top-level wrapper (K=5, D=24, Wm=6, G0='o23, G1='o35)
- `src/viterbi_core.v` - Core FSM + FSM race fix
- `src/traceback_v2.v` - Traceback burst + pipeline fix
- `src/expected_bits.v` - Convolutional code symbol computation
- `src/pm_bank.v` - Double-buffered path metrics
- `src/survivor_mem.v` - Circular survivor buffer (D x S bits)
- `src/acs_core.v` - Add-Compare-Select unit
- `src/branch_metric.v` - Branch metric computation
- `src/ham2.v` - 2-bit Hamming distance

### Tests
- `test/test.py` - 14 cocotb tests with commpy golden reference
- `test/tb.v` - Cocotb wrapper
- `test/requirements.txt` - pytest, cocotb, scikit-commpy

### Config
- `info.yaml` - tiles: "2x2"
- `src/config.json` - CLOCK_PERIOD=20ns, PL_TARGET_DENSITY_PCT=60

## Environment
- Python 3.12 venv at `.venv/`
- cocotb 2.0.1, scikit-commpy, icarus verilog 12.0
- macOS: use `gmake` not `make`
- Need DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/lib" for tt_tool.py (cairo)
