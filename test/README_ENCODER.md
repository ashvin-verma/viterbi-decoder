# Convolutional Encoder Tests

This directory contains comprehensive tests for the rate-1/2 convolutional encoder implementation.

## Encoder Module

**File**: `../src/conv_encoder.v`

A parameterizable convolutional encoder supporting:
- Arbitrary constraint length K (tested with K=3 and K=4)
- Octal generator polynomial specification
- Streaming interface with valid signals
- Seed loading for tail-biting mode
- Verilog-2001 compatible

### Parameters
- `K`: Constraint length (default: 4)
- `G0_OCT`: Generator polynomial 0 in octal (default: 8'o17)
- `G1_OCT`: Generator polynomial 1 in octal (default: 8'o13)

### Standard Configurations
- **K=3**: G0=7 (octal), G1=5 (octal) - Classic NASA/CCSDS
- **K=4**: G0=17 (octal), G1=13 (octal) - Industry standard

## Testbenches

### Main Testbench: `tb_conv_encoder_new.v`

Comprehensive self-checking testbench with 8 test cases:

1. **Single bits**: Single 0 then single 1
2. **All-zeros**: Stream of 16 zeros
3. **All-ones**: Stream of 16 ones  
4. **Alternating**: Pattern 0101... (32 bits)
5. **Random with gaps**: 64 random bits with ~25% idle cycles
6. **PRBS7**: 128-bit pseudo-random binary sequence
7. **Seed loading**: Tail-biting configuration test
8. **Long burn-in**: 1000 random bits with ~10% idle cycles

### K=4 Testbench: `tb_conv_encoder_k4.v`

Verifies encoder works with different constraint length:
- All-zeros test (32 bits)
- All-ones test (32 bits)
- Random test (100 bits)

## Running Tests

### Run Main Testbench (K=3)
```bash
make -f Makefile.encoder sim_encoder
```

### Run K=4 Test
```bash
iverilog -g2005 -o tb_k4.vvp ../src/conv_encoder.v ./tb_conv_encoder_k4.v
vvp tb_k4.vvp
```

### Generate Test Vectors (C Golden Reference)
```bash
make -f Makefile.encoder test_c
```

### View Waveforms
```bash
make -f Makefile.encoder wave
```

## Test Results

All tests pass successfully:
- **K=3 (7,5)**: ✅ All 8 tests PASSED
- **K=4 (17,13)**: ✅ All 3 tests PASSED

## Golden Reference

**File**: `../c-tests/encoder_golden.c`

C implementation matching the Verilog encoder:
- Same state update convention
- Same generator polynomial interpretation
- Used for test vector generation and verification

## Makefile Targets

- `all` / `sim_encoder`: Compile and run main testbench
- `compile_encoder`: Compile testbench only
- `wave`: Open waveform viewer (GTKWave)
- `test_c`: Run C golden reference
- `vectors`: Generate test vectors
- `clean`: Remove build artifacts
- `test_all`: Run both C and Verilog tests

## Files

- `tb_conv_encoder_new.v` - Main comprehensive testbench
- `tb_conv_encoder_k4.v` - K=4 configuration test
- `Makefile.encoder` - Build automation
- `tb_conv_encoder_new.vcd` - Waveform dump (generated)
- `../c-tests/encoder_golden.c` - C golden reference
- `../c-tests/encoder_test_vectors.txt` - Generated test vectors
