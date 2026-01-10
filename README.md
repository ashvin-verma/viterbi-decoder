![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Parameterized Viterbi Decoder - Tiny Tapeout Project

- [Read the documentation for project](docs/info.md)

## Overview

This project implements a **parameterized Viterbi decoder** for rate 1/2 convolutional codes. The decoder uses the Viterbi algorithm to perform maximum-likelihood sequence estimation, providing forward error correction for noisy communication channels.

**Current configuration**: K=5, generators 23/35 (octal) - provides good error correction with reasonable area. Alternative K=7 (NASA standard) available on separate branch.

## Key Design Decisions

### Single Decoder Configuration
The chip contains **one decoder configuration at synthesis time**, determined by Verilog parameters. To use a different configuration (e.g., K=3 instead of K=7), modify the parameters in `src/project.v` and re-synthesize.

### UART Byte Interface Only
The decoder uses a **UART-style byte interface** exclusively. This simplifies integration with microcontrollers and FPGAs:
- Input: 4 symbols packed per byte (8 bits = 4 × 2-bit symbols)
- Output: 8 decoded bits per byte
- Handshaking via ready/valid signals

## Parameterization

All core decoder parameters are configurable at synthesis time:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `K` | 5 | Constraint length (memory M = K-1) |
| `G0` | 5'b10011 | Generator polynomial 0 (23 octal) |
| `G1` | 5'b11101 | Generator polynomial 1 (35 octal) |
| `MAX_FRAME` | 32 | Maximum frame length in symbols |

### Supported Configurations

The decoder has been tested with:
- **K=3**: G0=7, G1=5 (octal) - minimal complexity, 4 states
- **K=5**: G0=23, G1=35 (octal) - good error correction, 16 states (current build)
- **K=7**: G0=171, G1=133 (octal) - NASA standard, 64 states (requires 6x2 tiles)

Resource usage scales with 2^(K-1) states.

## Implementation Results

### K=5 (Current Build)

| Metric | Value |
|--------|-------|
| Tile Size | 2x2 |
| Die Area | 334.88 × 225.76 µm |
| Core Area | 72,564 µm² |
| Design Area | 49,851 µm² |
| Utilization | 70.55% |
| Clock Frequency | 50 MHz (target) |
| States | 16 |

### K=7 NASA Standard (Separate Branch)

| Metric | Value |
|--------|-------|
| Tile Size | 6x2 |
| Design Area | ~169,000 µm² |
| States | 64 |

*Note: K=7 requires 6x2 tiles due to 64 states requiring more survivor memory and path metric storage.*

## How to Use

1. **Load symbols**: Send encoded symbols via `uio_in[7:0]` with `ui_in[0]` (BYTE_VALID) high
   - Pack 4 symbols per byte: `{sym3[1:0], sym2[1:0], sym1[1:0], sym0[1:0]}`
   - Wait for `uo_out[0]` (BYTE_IN_READY) before sending each byte
2. **Start decoding**: Assert `ui_in[3]` (START) after loading all symbols
3. **Read output**: When `uo_out[1]` (BYTE_OUT_VALID) is high, read decoded byte from `uio_out[7:0]`
   - Assert `ui_in[4]` (READ_ACK) to acknowledge each byte
4. **Frame complete**: `uo_out[4]` (DONE) indicates decoding finished

See [docs/info.md](docs/info.md) for detailed pin assignments and timing diagrams.

## Testing and Verification

### C Golden Model

A reference implementation in C (`c-tests/viterbi_golden.c`) provides:
- Parameterized encoder (`conv_encode`) and decoder (`viterbi_decode`)
- Compile-time configuration via `-DK=7 -DG0_OCT=0171 -DG1_OCT=0133`
- Bit-exact match verification against RTL

### Noise Channel Models

The golden model includes several channel impairment models for testing decoder robustness:

| Channel | Description |
|---------|-------------|
| Noiseless | Direct encoder output (baseline) |
| BSC | Binary symmetric channel - i.i.d. bit flips |
| Gilbert-Elliott | Bursty error channel with good/bad states |
| AWGN | Additive white Gaussian noise (hard-quantized) |
| ISI + AWGN | Two-tap intersymbol interference with noise |

### Cocotb Testbench

The RTL testbench (`test/test.py`) verifies:
- Multiple bit patterns (8-bit, 16-bit, 32-bit frames)
- Edge cases: all zeros, all ones, alternating patterns
- UART byte interface protocol compliance
- Gate-level simulation support (with `GATES=yes`)

Run tests:
```bash
cd test
make          # RTL simulation
make GATES=yes  # Gate-level simulation (requires hardened netlist)
```

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.

## Set up your Verilog project

1. Add your Verilog files to the `src` folder.
2. Edit the [info.yaml](info.yaml) and update information about your project, paying special attention to the `source_files` and `top_module` properties. If you are upgrading an existing Tiny Tapeout project, check out our [online info.yaml migration tool](https://tinytapeout.github.io/tt-yaml-upgrade-tool/).
3. Edit [docs/info.md](docs/info.md) and add a description of your project.
4. Adapt the testbench to your design. See [test/README.md](test/README.md) for more information.

The GitHub action will automatically build the ASIC files using [LibreLane](https://www.zerotoasiccourse.com/terminology/librelane/).

## Enable GitHub actions to build the results page

- [Enabling GitHub Pages](https://tinytapeout.com/faq/#my-github-action-is-failing-on-the-pages-part)

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Learn how semiconductors work](https://tinytapeout.com/siliwiz/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)

## What next?

- [Submit your design to the next shuttle](https://app.tinytapeout.com/).
- Edit [this README](README.md) and explain your design, how it works, and how to test it.
- Share your project on your social network of choice:
  - LinkedIn [#tinytapeout](https://www.linkedin.com/search/results/content/?keywords=%23tinytapeout) [@TinyTapeout](https://www.linkedin.com/company/100708654/)
  - Mastodon [#tinytapeout](https://chaos.social/tags/tinytapeout) [@matthewvenn](https://chaos.social/@matthewvenn)
  - X (formerly Twitter) [#tinytapeout](https://twitter.com/hashtag/tinytapeout) [@tinytapeout](https://twitter.com/tinytapeout)
  - Bluesky [@tinytapeout.com](https://bsky.app/profile/tinytapeout.com)
