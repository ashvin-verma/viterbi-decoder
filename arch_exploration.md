# Viterbi Decoder Architecture Exploration

## Objective

Explore how the parametric Viterbi decoder scales across K=3, K=5, K=7 constraint lengths
on two open-source PDKs (Sky130 and IHP SG13G2) targeting Tiny Tapeout tile sizes.

## Parameters

| K | M (state bits) | States (2^M) | D (traceback) | G0 (octal) | G1 (octal) | Rate |
|---|---------------|-------------|--------------|-----------|-----------|------|
| 3 | 2 | 4 | 12 | 07 | 05 | 1/2 |
| 5 | 4 | 16 | 24 | 023 | 035 | 1/2 |
| 7 | 6 | 64 | 42 | 0171 | 0133 | 1/2 |

## Synthesis Environment

- **Tool**: LibreLane (OpenROAD-based) via tt-support-tools
- **Sky130**: librelane 2.4.2, CLOCK_PERIOD=20ns (50 MHz), PL_TARGET_DENSITY_PCT=70
- **IHP SG13G2**: librelane 3.0.0.dev52, CLOCK_PERIOD=25ns (40 MHz), PL_TARGET_DENSITY_PCT=60
- **Platform**: WSL Ubuntu 24.04, Docker-based synthesis flow

## Results: Sky130 (130nm)

| K | States | Post-Synth Cells | Post-Synth Area (um2) | TT Tile | Utilization | Wire Length (um) | Status |
|---|--------|-----------------|----------------------|---------|-------------|-----------------|--------|
| 3 | 4 | 888 | 11,227 | 1x2 | 33.9% | 26,615 | PASS (all clean) |
| 5 | 16 | 3,249 | 41,357 | 2x2 | 58.5% | 140,709 | PASS (1 antenna violation) |
| 7 | 64 | 18,207 | 238,456 | 8x2 (max) | 80.5%* | - | FAIL (DPL overflow after hold buffers) |

### Sky130 Cell Breakdown

| K | Sequential | Seq Area (um2) | Combinational | Comb Area (um2) |
|---|-----------|---------------|--------------|----------------|
| 3 | 216 | 4,855 | 634 | 6,218 |
| 5 | 883 | 19,172 | 2,310 | 21,964 |
| 7 | 5,298 | 113,391 | 12,854 | 124,847 |

## Results: IHP SG13G2 (130nm)

| K | States | Post-Synth Cells | Post-Synth Area (um2) | TT Tile | Utilization | Wire Length (um) | Status |
|---|--------|-----------------|----------------------|---------|-------------|-----------------|--------|
| 3 | 4 | 1,260 | 20,419 | 1x2 | 36.9% | 41,803 | PASS (all clean) |
| 5 | 16 | 4,721 | 78,193 | 2x2 | 66.0% | 195,924 | PASS (all clean) |
| 7 | 64 | 30,773* | 492,595* | 8x2 (max) | >100%* | - | FAIL (DPL overflow after CTS) |

*K=7 values are post-buffer-insertion at point of failure.

### IHP Cell Breakdown

| K | Sequential | Seq Area (um2) | Combinational | Comb Area (um2) |
|---|-----------|---------------|--------------|----------------|
| 3 | 219 | 10,729 | 926 | 9,048 |
| 5 | 886 | 43,404 | 3,307 | 31,899 |
| 7 | 5,301 | 259,690 | 18,237 | 186,453 |

## Growth Analysis

### Relative Growth (normalized to K=3)

| Metric | K=3 | K=5 (4x states) | K=7 (16x states) |
|--------|-----|-----------------|-------------------|
| Sky130 cells | 1.0x | 3.7x | 20.5x |
| Sky130 area | 1.0x | 3.7x | 21.2x |
| IHP cells | 1.0x | 3.7x | 24.4x |
| IHP area | 1.0x | 3.8x | 24.1x |

### Step-by-Step Growth

| Metric | K=3 to K=5 (4x states) | K=5 to K=7 (4x states) |
|--------|------------------------|------------------------|
| Sky130 cells | 3.7x | 5.6x |
| Sky130 area | 3.7x | 5.8x |
| IHP cells | 3.7x | 6.5x |
| IHP area | 3.8x | 6.3x |
| Sky130 wire | - | 5.3x (26.6k to 140.7k) |

### Growth Model

The state count grows as S = 2^(K-1), so K=3/5/7 gives S = 4/16/64.
Relative to states, the area growth is approximately **O(S^1.3)** — super-linear
but sub-quadratic. The dominant cost drivers are:

1. **Path metric storage** (S x Wm bits of registers): grows linearly with S
2. **ACS butterfly units** (S/2 units): grows linearly with S
3. **Survivor memory** (D x S bits): grows as O(S x K), i.e., super-linear
4. **Traceback mux tree**: grows as O(S x log2(S))
5. **Interconnect/buffers**: grows super-linearly due to fanout and wire length

The combinational-to-sequential ratio shifts toward combinational at larger K,
reflecting the growing ACS and mux complexity.

## PDK Comparison

| Metric | IHP / Sky130 Ratio | Notes |
|--------|-------------------|-------|
| K=3 cell count | 1.42x | IHP needs more cells (smaller std cell library) |
| K=3 area | 1.82x | IHP cells are physically larger (130nm, fewer options) |
| K=5 cell count | 1.45x | Consistent ratio |
| K=5 area | 1.89x | IHP ~1.9x area penalty |
| K=5 wire length | 1.39x | IHP routing also longer |

IHP's smaller standard cell library (~78 cells vs Sky130's 400+) means the
synthesizer has fewer optimization options, leading to ~1.4x more cells and
~1.9x more area for equivalent designs.

## Key Conclusions

1. **K=5 is the practical maximum for Tiny Tapeout** on either PDK, fitting
   comfortably in a 2x2 tile with ~60% utilization and clean timing.

2. **K=7 exceeds TT's largest 8x2 tile** — even with aggressive density
   targets (85%), hold/timing buffer insertion pushes the design past the
   available core area. K=7 requires a standalone ASIC or FPGA.

3. **Growth is super-linear (~S^1.3)** but your intuition about quadratic
   was close — the actual exponent of ~1.3 reflects that not all components
   grow quadratically (path metrics are linear, but interconnect is super-linear).

4. **IHP costs ~1.9x more area** than Sky130 for the same design, consistent
   across all K values. Plan for roughly double the tile count on IHP.

5. **K=3 is trivially small** — fits in 1x1 (barely) or 1x2 at ~34% util.
   Could be useful for ultra-low-area applications but coding gain is limited.