![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Multi-Mode Convolutional Encoder - Tiny Tapeout Project

- [Read the documentation for project](docs/info.md)

## Overview

This project implements a multi-mode rate 1/2 convolutional encoder with three operating modes:
- **Mode 00**: K=3 encoder (low complexity, generators 7,5 octal)
- **Mode 01**: K=7 encoder (NASA standard, generators 171,133 octal)  
- **Mode 10**: UART byte interface (K=3 with packing/unpacking)

Convolutional encoding adds redundancy for forward error correction, commonly used in satellite communications, deep space missions, and wireless systems.

## Features

- Parameterizable constraint length (K=3 to K=9 tested)
- NASA standard generator polynomials
- Three selectable modes via mode pins
- Streaming valid/ready handshaking
- UART byte-oriented interface option
- Compact Verilog-2001 design

## How to Use

1. Select mode using `ui_in[7:6]`
2. For direct modes (00/01): Send bits via `ui_in[0]` (valid) and `ui_in[1]` (bit data)
3. For UART mode (10): Send bytes via `uio_in[7:0]` with `ui_in[0]` as valid
4. Read encoded output from `uo_out[2:1]` (symbol) or `uo_out[7:1]` (UART bytes)

See [docs/info.md](docs/info.md) for detailed pin assignments and modes.


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
