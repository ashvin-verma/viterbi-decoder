#!/usr/bin/env python3
"""
demo.py -- Interactive Viterbi Decoder Demo for PYNQ-Z2 (via XSDB/JTAG)

Drives the Viterbi decoder on the FPGA through AXI GPIO registers,
accessed via XSDB's mwr/mrd commands over JTAG (USB).

Usage:
    python demo.py                     # Interactive menu
    python demo.py --selftest          # Run self-test only
    python demo.py --encode "hello"    # Encode+decode a string

Requirements:
    - PYNQ-Z2 connected via USB
    - Vivado/XSDB on PATH (or set VIVADO_PATH env var)
    - Bitstream built (vivado_project_ps7/viterbi_ps7.bit)
"""

import subprocess
import sys
import os
import struct

# =========================================================================
# Configuration
# =========================================================================
VIVADO_PATH = os.environ.get("VIVADO_PATH", r"D:\Xilinx\Vivado\2024.2")
XSDB = os.path.join(VIVADO_PATH, "bin", "xsdb.bat")
BIT_FILE = os.path.join(os.path.dirname(__file__), "vivado_project_ps7", "viterbi_ps7.bit")

GPIO_OUT_BASE = 0x41200000  # 16-bit output: [7:0]=ui_in, [15:8]=uio_in
GPIO_IN_BASE  = 0x41210000  # 16-bit input:  [7:0]=uo_out, [15:8]=uio_out

# K=7 NASA polynomials (octal)
K = 7
G0 = 0o171  # 0x79 = 1111001
G1 = 0o133  # 0x5B = 1011011


# =========================================================================
# Convolutional Encoder (matches RTL / cocotb convention)
#   reg = {state, bit_in}  where state[0] = newest, state[M-1] = oldest
#   sym = (c0 << 1) | c1
# =========================================================================
M = K - 1
D = 42  # traceback depth

def _parity(x):
    p = 0
    while x:
        p ^= (x & 1)
        x >>= 1
    return p

def conv_encode(info_bits, g0=G0, g1=G1, k=K):
    """Rate-1/2 convolutional encoder. Returns list of 2-bit symbol ints.
    Appends M tail zeros for encoder flush."""
    m = k - 1
    mask = (1 << m) - 1
    state = 0
    symbols = []
    for bit in list(info_bits) + [0] * m:
        reg = (bit & 1) | (state << 1)
        c0 = _parity(reg & g0)
        c1 = _parity(reg & g1)
        symbols.append((c0 << 1) | c1)
        state = ((state << 1) | (bit & 1)) & mask
    return symbols


def pack_symbols_to_bytes(symbols):
    """Pack 2-bit symbols into bytes, 4 symbols per byte, LSB first."""
    padded = list(symbols)
    while len(padded) % 4 != 0:
        padded.append(0)
    packed = []
    for i in range(0, len(padded), 4):
        byte_val = 0
        for j in range(4):
            byte_val |= (padded[i + j] & 0x03) << (j * 2)
        packed.append(byte_val)
    return packed


def bits_to_bytes_msb(bits):
    """Pack bits into bytes, MSB first (for converting ASCII to info bits)."""
    result = []
    for i in range(0, len(bits), 8):
        byte_val = 0
        for j in range(8):
            if i + j < len(bits):
                byte_val |= (bits[i + j] << (7 - j))
        result.append(byte_val)
    return result


def bytes_to_bits_msb(byte_list):
    """Unpack bytes to bits, MSB first (for converting ASCII to info bits)."""
    bits = []
    for b in byte_list:
        for j in range(7, -1, -1):
            bits.append((b >> j) & 1)
    return bits


def unpack_decoded_bytes(byte_list):
    """Unpack decoded output bytes to bits, LSB first (matches bit_packer_8x)."""
    bits = []
    for b in byte_list:
        for j in range(8):
            bits.append((b >> j) & 1)
    return bits


# =========================================================================
# XSDB Interface
# =========================================================================
class XSDBInterface:
    """Communicates with PYNQ-Z2 FPGA via XSDB commands over JTAG."""

    def __init__(self):
        self.proc = None

    def _run_xsdb(self, tcl_commands, timeout=30):
        """Run XSDB with given TCL commands and return output."""
        # Write commands to a temp file
        tcl_file = os.path.join(os.path.dirname(__file__), "_demo_tmp.tcl")
        with open(tcl_file, 'w') as f:
            f.write(tcl_commands)

        try:
            result = subprocess.run(
                [XSDB, tcl_file],
                capture_output=True, text=True, timeout=timeout,
                cwd=os.path.dirname(__file__)
            )
            return result.stdout, result.stderr, result.returncode
        except subprocess.TimeoutExpired:
            return "", "TIMEOUT", -1
        finally:
            if os.path.exists(tcl_file):
                os.remove(tcl_file)

    def program_and_init(self):
        """Program FPGA and initialize PS7."""
        print(f"Programming FPGA with {BIT_FILE}...")
        if not os.path.exists(BIT_FILE):
            print(f"ERROR: Bitstream not found at {BIT_FILE}")
            return False

        # Find ps7_init.tcl
        ps7_init_candidates = [
            os.path.join(os.path.dirname(__file__),
                         "vivado_project_ps7", "viterbi_ps7.gen",
                         "sources_1", "bd", "system", "ip",
                         "system_ps7_0", "ps7_init.tcl"),
            os.path.join(os.path.dirname(__file__),
                         "vivado_project_ps7", "ps7_init.tcl"),
        ]
        ps7_init = None
        for c in ps7_init_candidates:
            if os.path.exists(c):
                ps7_init = c.replace("\\", "/")
                break

        bit_path = BIT_FILE.replace("\\", "/")
        tcl = f"""
connect
after 1000
targets -set -filter {{name =~ "xc7z020*"}}
fpga -file {{{bit_path}}}
after 1000
targets -set -filter {{name =~ "*A9*#0"}}
catch {{stop}}
after 200
rst -processor
after 500
"""
        if ps7_init:
            tcl += f"""
source {{{ps7_init}}}
ps7_init
ps7_post_config
"""
        else:
            tcl += 'puts "WARNING: ps7_init.tcl not found"\n'

        # Set Mode 1 and verify
        tcl += f"""
after 500
mwr -force {GPIO_OUT_BASE:#010x} 0x00000080
after 10
set val [mrd -force -value {GPIO_IN_BASE:#010x}]
puts "STATUS: $val"
disconnect
"""
        stdout, stderr, rc = self._run_xsdb(tcl, timeout=60)
        print(stdout)
        if "STATUS:" in stdout:
            print("FPGA programmed and PS7 initialized successfully!")
            return True
        else:
            print(f"WARNING: May not have initialized properly.")
            if stderr:
                print(f"STDERR: {stderr[:500]}")
            return True  # Continue anyway

    def decode_frame_on_fpga(self, encoded_bytes, num_output_bytes):
        """Send encoded bytes to FPGA Viterbi decoder, read decoded bytes from FIFO.

        Uses the FIFO-based bridge protocol:
          - Mode 0->1 transition triggers soft reset (clears decoder + FIFO)
          - Rising edge on byte_valid (ui_in[0]) sends one byte
          - Auto-ack captures output into FIFO automatically
          - Rising edge on ui_in[4] pops one byte from FIFO
        """
        # Build TCL script
        tcl = f"""
connect
targets -set -filter {{name =~ "*A9*#0"}}

# Soft reset: mode 0 -> 1 transition resets decoder + FIFO
mwr -force {GPIO_OUT_BASE:#010x} 0x00000000
after 20
mwr -force {GPIO_OUT_BASE:#010x} 0x00000080
after 20

"""
        # Send each input byte
        for i, byte_val in enumerate(encoded_bytes):
            ctrl_val = 0x0080 | ((byte_val & 0xFF) << 8)
            tcl += f"""
# --- Send byte {i}: 0x{byte_val:02X} ---
for {{set i 0}} {{$i < 500}} {{incr i}} {{
    set s [mrd -force -value {GPIO_IN_BASE:#010x}]
    if {{$s & 0x01}} break
    after 1
}}
mwr -force {GPIO_OUT_BASE:#010x} {ctrl_val:#010x}
after 1
mwr -force {GPIO_OUT_BASE:#010x} [expr {{{ctrl_val} | 1}}]
after 2
mwr -force {GPIO_OUT_BASE:#010x} 0x00000080
after 1
"""

        # Wait for processing, then read FIFO
        tcl += f"""
after 200

# Read output bytes from FIFO
"""
        for i in range(num_output_bytes):
            tcl += f"""
set s [mrd -force -value {GPIO_IN_BASE:#010x}]
if {{$s & 0x02}} {{
    set out_byte [expr {{($s >> 8) & 0xFF}}]
    puts "OUT_{i}: $out_byte"
    mwr -force {GPIO_OUT_BASE:#010x} 0x00000080
    after 1
    mwr -force {GPIO_OUT_BASE:#010x} 0x00000090
    after 2
    mwr -force {GPIO_OUT_BASE:#010x} 0x00000080
    after 2
}} else {{
    puts "OUT_{i}: TIMEOUT"
}}
"""

        tcl += """
disconnect
"""

        stdout, stderr, rc = self._run_xsdb(tcl, timeout=120)

        # Parse output bytes from stdout
        decoded_bytes = []
        for line in stdout.splitlines():
            if line.startswith("OUT_"):
                parts = line.split(": ")
                if len(parts) == 2 and parts[1] != "TIMEOUT":
                    try:
                        decoded_bytes.append(int(parts[1]))
                    except ValueError:
                        pass

        return decoded_bytes


# =========================================================================
# Demo Functions
# =========================================================================

def _prepare_frame(info_bits):
    """Encode info bits and prepare full frame with flush symbols.

    Returns (all_input_bytes, num_output_bytes, num_info_bits).
    """
    n_info = len(info_bits)

    # Encode (includes M tail zeros for encoder flush)
    symbols = conv_encode(info_bits)
    data_bytes = pack_symbols_to_bytes(symbols)

    # Add D-1 flush zero symbols to push data through traceback
    flush_syms = [0] * (D - 1)
    flush_bytes = pack_symbols_to_bytes(flush_syms)

    all_bytes = data_bytes + flush_bytes
    total_syms = len(all_bytes) * 4
    total_dec_bits = total_syms - D
    num_out_bytes = total_dec_bits // 8

    return all_bytes, num_out_bytes, n_info


def demo_encode_decode(xsdb, message):
    """Encode a message string, send to FPGA decoder, verify round-trip."""
    print(f"\n{'='*50}")
    print(f" Encoding: \"{message}\"")
    print(f"{'='*50}")

    # Convert to bits (MSB first for ASCII)
    msg_bytes = list(message.encode('ascii'))
    info_bits = bytes_to_bits_msb(msg_bytes)
    num_info_bits = len(info_bits)

    # Prepare frame
    all_bytes, num_out_bytes, _ = _prepare_frame(info_bits)
    print(f"  Info bits:    {num_info_bits} ({len(msg_bytes)} bytes)")
    print(f"  Frame:        {len(all_bytes)} input bytes -> {num_out_bytes} output bytes")

    # Send to FPGA
    print(f"\n  Sending to FPGA Viterbi decoder...")
    decoded_bytes = xsdb.decode_frame_on_fpga(all_bytes, num_out_bytes)

    print(f"  Received:     {len(decoded_bytes)}/{num_out_bytes} bytes")

    if decoded_bytes:
        print(f"  Decoded hex:  {' '.join(f'{b:02X}' for b in decoded_bytes)}")

        # Unpack decoded bytes to bits (LSB first, matching bit_packer)
        decoded_bits = unpack_decoded_bytes(decoded_bytes)

        # Compare first num_info_bits
        n_cmp = min(num_info_bits, len(decoded_bits))
        errors = sum(a != b for a, b in zip(info_bits[:n_cmp],
                                              decoded_bits[:n_cmp]))

        # Reconstruct decoded ASCII from bits
        recon_bits = decoded_bits[:num_info_bits]
        recon_bytes = bits_to_bytes_msb(recon_bits)
        decoded_str = bytes(recon_bytes[:len(msg_bytes)]).decode('ascii', errors='replace')

        print(f"  Decoded text: \"{decoded_str}\"")
        print(f"  Bit errors:   {errors}/{num_info_bits}")

        if errors == 0:
            print(f"\n  >> PERFECT DECODE! <<")
        else:
            print(f"\n  >> {errors} bit errors <<")
    else:
        print(f"  ERROR: No output bytes received!")

    print()


def demo_selftest(xsdb):
    """Run self-test with known patterns."""
    print(f"\n{'='*50}")
    print(f" Viterbi Decoder Self-Test (K=7, Rate=1/2)")
    print(f"{'='*50}")

    test_cases = [
        ("all-zeros (32 bits)", [0] * 32),
        ("all-ones (32 bits)",  [1] * 32),
        ("alternating 01",      [0, 1] * 16),
        ("0xDEAD (16 bits)",    bytes_to_bits_msb([0xDE, 0xAD])),
    ]

    passed = 0
    for name, info_bits in test_cases:
        print(f"\n--- Test: {name} ---")
        n_info = len(info_bits)

        # Prepare frame
        all_bytes, num_out_bytes, _ = _prepare_frame(info_bits)

        # Decode on FPGA
        decoded_bytes = xsdb.decode_frame_on_fpga(all_bytes, num_out_bytes)

        # Unpack and compare
        decoded_bits = unpack_decoded_bytes(decoded_bytes)
        n_cmp = min(n_info, len(decoded_bits))
        errors = sum(a != b for a, b in zip(info_bits[:n_cmp],
                                              decoded_bits[:n_cmp]))

        if errors == 0 and len(decoded_bits) >= n_info:
            print(f"  PASS (0 bit errors)")
            passed += 1
        else:
            print(f"  FAIL: {errors} bit errors in {n_cmp} bits")

    print(f"\n{'='*50}")
    print(f" Results: {passed}/{len(test_cases)} tests passed")
    print(f"{'='*50}\n")


# =========================================================================
# Main
# =========================================================================

def main():
    xsdb = XSDBInterface()

    if not os.path.exists(XSDB):
        print(f"ERROR: XSDB not found at {XSDB}")
        print(f"Set VIVADO_PATH environment variable to your Vivado installation.")
        sys.exit(1)

    if "--selftest" in sys.argv:
        print("Programming FPGA...")
        xsdb.program_and_init()
        demo_selftest(xsdb)
        return

    if "--encode" in sys.argv:
        idx = sys.argv.index("--encode")
        if idx + 1 < len(sys.argv):
            xsdb.program_and_init()
            demo_encode_decode(xsdb, sys.argv[idx + 1])
            return

    # Interactive menu
    print("""
    ╔══════════════════════════════════════════════╗
    ║   Viterbi Decoder FPGA Demo (PYNQ-Z2)       ║
    ║   K=7, Rate=1/2, NASA Polynomials            ║
    ║   Control via XSDB/JTAG                      ║
    ╚══════════════════════════════════════════════╝
    """)

    print("[1] Program FPGA")
    print("[2] Run self-test")
    print("[3] Encode & decode a message")
    print("[4] Quit")
    print()

    programmed = False
    while True:
        try:
            choice = input(">> ").strip()
        except (EOFError, KeyboardInterrupt):
            break

        if choice == "1":
            if xsdb.program_and_init():
                programmed = True
        elif choice == "2":
            if not programmed:
                print("Programming FPGA first...")
                if not xsdb.program_and_init():
                    continue
                programmed = True
            demo_selftest(xsdb)
        elif choice == "3":
            if not programmed:
                print("Programming FPGA first...")
                if not xsdb.program_and_init():
                    continue
                programmed = True
            msg = input("Enter message: ").strip()
            if msg:
                demo_encode_decode(xsdb, msg)
        elif choice == "4" or choice.lower() == "q":
            break
        else:
            print("Invalid choice. Enter 1-4.")


if __name__ == "__main__":
    main()
