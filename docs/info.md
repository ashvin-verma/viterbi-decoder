## How it works

This is a **parameterized Viterbi decoder** for rate 1/2 convolutional codes. The Viterbi algorithm performs maximum-likelihood sequence estimation to decode convolutional codes corrupted by channel noise.

### Architecture

The decoder implements a full-frame Viterbi algorithm with:

1. **ACS (Add-Compare-Select) Unit**: Computes branch metrics and selects surviving paths for each trellis state
2. **Survivor Memory**: Stores decision bits for traceback (one bit per state per time step)
3. **Path Metric Banks**: Dual-bank ping-pong storage for current/previous metrics
4. **Traceback Unit**: Reconstructs decoded sequence from survivor decisions
5. **UART Byte Interface**: Symbol packing/unpacking for byte-oriented I/O

### Default Configuration

- **Code**: NASA standard K=7, G0=171, G1=133 (octal)
- **States**: 64 (2^6)
- **Frame size**: Up to 32 symbols
- **Rate**: 1/2 (2 coded bits per information bit)

### Parameterization

Change these parameters in `src/project.v` before synthesis:

```verilog
parameter K = 7,                    // Constraint length
parameter [K-1:0] G0 = 7'b1111001,  // Generator 0 (171 octal)
parameter [K-1:0] G1 = 7'b1011011,  // Generator 1 (133 octal)
parameter MAX_FRAME = 32            // Maximum symbols per frame
```

## Pin Interface

### Inputs (ui_in)

| Pin | Name | Description |
|-----|------|-------------|
| ui_in[0] | BYTE_VALID | Input byte is valid |
| ui_in[3] | START | Begin decoding |
| ui_in[4] | READ_ACK | Acknowledge output byte read |

### Outputs (uo_out)

| Pin | Name | Description |
|-----|------|-------------|
| uo_out[0] | BYTE_IN_READY | Ready to accept input byte |
| uo_out[1] | BYTE_OUT_VALID | Output byte available |
| uo_out[3] | BUSY | Decoding in progress |
| uo_out[4] | DONE | Frame decode complete |

### Bidirectional (uio)

| Pin | Direction | Description |
|-----|-----------|-------------|
| uio[7:0] | Input | Symbol byte: 4 x 2-bit symbols packed |
| uio[7:0] | Output | Decoded byte: 8 decoded bits |

**Symbol packing**: `{sym3[1:0], sym2[1:0], sym1[1:0], sym0[1:0]}`

## How to test

### Basic Test Sequence

1. Reset the device (rst_n low, then high)
2. Wait for BYTE_IN_READY
3. Send symbol bytes via uio_in with BYTE_VALID asserted
4. After all symbols loaded, assert START
5. Wait for BUSY to go low
6. Read output bytes when BYTE_OUT_VALID is high, assert READ_ACK for each
7. DONE signals frame completion

### Using Cocotb

```bash
cd test
make                  # RTL simulation
make GATES=yes        # Gate-level (post-synthesis)
```

### Using the C Golden Model

```bash
cd c-tests
gcc -DK=7 -DG0_OCT=0171 -DG1_OCT=0133 -DTEST_MAIN -o viterbi_test viterbi_golden.c -lm
./viterbi_test
```

## External hardware

- **Microcontroller**: Any MCU with GPIO for control signals and parallel data bus
- **FPGA**: Direct connection via I/O ports
- **Logic Analyzer**: For debugging timing and protocol

Typical setup: MCU encodes test data, sends symbols to decoder, verifies output matches original data.
