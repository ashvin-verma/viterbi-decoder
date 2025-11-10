# Testbenches for Convolutional Encoder Project

This directory contains comprehensive testbenches for the multi-mode convolutional encoder project.

## Test Structure

### Main Testbenches

- **tb.v** - Comprehensive testbench for `project.v` (top-level module)
  - Tests all three modes: K=3 small encoder, K=7 large encoder, and UART encoder
  - Self-checking with golden reference models
  - Run with: `make -f Makefile.encoder sim_project`

- **tb_conv_encoder_new.v** - Comprehensive tests for core encoder (K=3)
  - 8 different test scenarios including PRBS, random, gaps, and tail-biting
  - Run with: `make -f Makefile.encoder sim_encoder`

### Parameterized K Tests

- **tb_conv_encoder_k4.v** through **tb_conv_encoder_k9.v**
  - Verify encoder with different constraint lengths (K=4,5,6,7,9)
  - Run individually: `make -f Makefile.encoder sim_k{4,5,6,7,9}`

### UART Encoder Test

- **tb_uart_conv_encoder_simple.v** - UART interface smoke test
  - Verifies byte-oriented interface and data flow
  - Run with: `make -f Makefile.encoder sim_uart`

## How to run

Run all tests:
```sh
make -f Makefile.encoder test_all
```

Run individual test suites:
```sh
make -f Makefile.encoder sim_project  # Top-level comprehensive test
make -f Makefile.encoder sim_encoder  # Core K=3 encoder
make -f Makefile.encoder sim_k7       # K=7 encoder (NASA standard)
make -f Makefile.encoder sim_uart     # UART byte interface
```

## How to view waveforms

Using GTKWave:
```sh
gtkwave tb.vcd
```

Using Surfer:
```sh
surfer tb.vcd
```

## Test Results

All testbenches include self-checking golden reference models and report PASS/FAIL status.

Example output from comprehensive test:
```
=== ALL TESTS PASSED ===
```
