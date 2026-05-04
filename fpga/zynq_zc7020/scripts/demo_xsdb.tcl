# =============================================================================
# demo_xsdb.tcl -- XSDB script for interactive Viterbi decoder demo on PYNQ-Z2
#
# Programs the FPGA, initializes PS7, and provides procedures for
# driving the Viterbi decoder via AXI GPIO registers over JTAG.
#
# Bridge architecture:
#   - Rising-edge detectors convert slow XSDB writes to single-cycle pulses
#   - Auto-ack captures decoded bytes into 16-entry FIFO automatically
#   - Mode 0->1 transition triggers soft reset (clears decoder + FIFO)
#
# Usage:
#   xsdb scripts/demo_xsdb.tcl              (run from fpga/zynq_zc7020/)
#   xsdb -interactive scripts/demo_xsdb.tcl (interactive mode)
#
# Or from Python:
#   subprocess.run(["xsdb", "scripts/demo_xsdb.tcl", "--run-test"])
# =============================================================================

# =========================================================================
# AXI GPIO register map
# =========================================================================
set GPIO_OUT_BASE  0x41200000  ;# 16-bit output: [7:0]=ui_in, [15:8]=uio_in
set GPIO_IN_BASE   0x41210000  ;# 16-bit input:  [7:0]=uo_out, [15:8]=uio_out

# AXI GPIO register offsets
set GPIO_DATA      0x0000      ;# Channel 1 data register

# =========================================================================
# Status bits (after FIFO bridge):
#   [0] = byte_in_ready (unpacker ready for next byte)
#   [1] = fifo_not_empty (decoded bytes available in FIFO)
#   [2] = rx_sym_ready
#   [15:8] = FIFO head byte (next decoded byte)
#
# Control:
#   ui_in[7]   = mode (1 = byte batch)
#   ui_in[4]   = FIFO pop (rising edge pops one byte)
#   ui_in[0]   = byte_valid (rising edge sends data byte)
#   uio_in[7:0] = input data byte
# =========================================================================

# =========================================================================
# Helper procedures
# =========================================================================

proc gpio_write {val} {
    mwr -force 0x41200000 $val
}

proc gpio_read {} {
    return [mrd -force -value 0x41210000]
}

proc get_status {} {
    set raw [gpio_read]
    return [expr {$raw & 0xFF}]
}

proc get_fifo_byte {} {
    set raw [gpio_read]
    return [expr {($raw >> 8) & 0xFF}]
}

proc reset_decoder {} {
    # Mode 0->1 triggers soft reset in bridge (clears decoder + FIFO)
    gpio_write 0x00000000
    after 20
    gpio_write 0x00000080
    after 20
}

proc send_byte {data_byte} {
    set ctrl [expr {0x0080 | (($data_byte & 0xFF) << 8)}]

    # Wait for byte_in_ready
    for {set i 0} {$i < 500} {incr i} {
        set s [gpio_read]
        if {$s & 0x01} break
        after 1
    }
    if {!($s & 0x01)} {
        puts "ERROR: Timeout waiting for byte_in_ready"
        return -1
    }

    # Load data, then pulse byte_valid (rising edge)
    gpio_write $ctrl
    after 1
    gpio_write [expr {$ctrl | 1}]
    after 2
    gpio_write 0x00000080
    after 1
    return 0
}

proc read_fifo {} {
    # Read all available bytes from output FIFO
    set output {}
    for {set n 0} {$n < 64} {incr n} {
        set s [gpio_read]
        if {$s & 0x02} {
            lappend output [expr {($s >> 8) & 0xFF}]
            # Pop: pulse ui_in[4]
            gpio_write 0x00000080
            after 1
            gpio_write 0x00000090
            after 2
            gpio_write 0x00000080
            after 2
        } else {
            break
        }
    }
    return $output
}

proc decode_frame {input_bytes {num_out 0}} {
    set num_in [llength $input_bytes]
    if {$num_out == 0} { set num_out 64 }

    puts "  Sending $num_in encoded bytes..."

    # Soft reset
    reset_decoder

    # Send all input bytes
    foreach byte $input_bytes {
        set result [send_byte $byte]
        if {$result < 0} {
            puts "  ERROR: Failed to send byte"
            return {}
        }
    }

    # Wait for processing
    after 200

    puts "  Reading FIFO..."
    set output [read_fifo]
    puts "  Got [llength $output] decoded bytes"

    return $output
}

# =========================================================================
# Connection and programming
# =========================================================================

proc program_fpga {{bit_file ""}} {
    if {$bit_file eq ""} {
        set bit_file "./vivado_project_ps7/viterbi_ps7.bit"
    }

    if {![file exists $bit_file]} {
        puts "ERROR: Bitstream not found at $bit_file"
        return -1
    }

    puts "=== Connecting to PYNQ-Z2 ==="
    connect
    after 1000

    puts "=== Programming PL fabric ==="
    targets -set -filter {name =~ "xc7z020*"}
    fpga -file $bit_file
    after 1000

    puts "=== Initializing PS7 ==="
    targets -set -filter {name =~ "*A9*#0"}
    catch {stop}
    after 200
    rst -processor
    after 500

    # Source ps7_init
    set ps7_init_file ""
    foreach candidate [list \
        "./vivado_project_ps7/viterbi_ps7.gen/sources_1/bd/system/ip/system_ps7_0/ps7_init.tcl" \
        "./vivado_project_ps7/ps7_init.tcl" \
    ] {
        if {[file exists $candidate]} {
            set ps7_init_file $candidate
            break
        }
    }

    if {$ps7_init_file ne ""} {
        puts "  Loading ps7_init from: $ps7_init_file"
        source $ps7_init_file
        ps7_init
        ps7_post_config
    } else {
        puts "  WARNING: ps7_init.tcl not found, skipping PS init"
    }

    after 500
    puts "=== FPGA programmed and PS7 initialized ==="

    # Set Mode 1
    gpio_write 0x00000080
    after 10

    # Verify
    set status [get_status]
    puts "  status = 0x[format %02X $status] (byte_in_ready=[expr {$status & 1}])"
    puts ""

    return 0
}

# =========================================================================
# Self-test
# =========================================================================

proc format_hex {byte_list} {
    set result {}
    foreach b $byte_list {
        lappend result [format "0x%02X" $b]
    }
    return [join $result " "]
}

proc run_self_test {} {
    puts ""
    puts "=========================================="
    puts " Viterbi Decoder Self-Test (K=7, Rate=1/2)"
    puts "=========================================="

    # Test 1: All-zeros (20 packed bytes of 0x00)
    puts "\n--- Test 1: All-zeros (20 bytes) ---"
    set enc_zeros [lrepeat 20 0]
    set dec [decode_frame $enc_zeros]
    set all_zero 1
    foreach b $dec { if {$b != 0} { set all_zero 0; break } }
    if {$all_zero && [llength $dec] > 0} {
        puts "  PASS: [llength $dec] bytes, all zero"
    } else {
        puts "  FAIL: [format_hex $dec]"
    }

    # Test 2: GPIO read check
    puts "\n--- Test 2: GPIO status check ---"
    set status [get_status]
    puts "  status = 0x[format %02X $status]"
    puts "  byte_in_ready  = [expr {($status >> 0) & 1}]"
    puts "  fifo_not_empty = [expr {($status >> 1) & 1}]"
    puts "  rx_sym_ready   = [expr {($status >> 2) & 1}]"

    puts ""
    puts "=========================================="
    puts " Self-test complete"
    puts "=========================================="
}

# =========================================================================
# Main: auto-run if invoked with --run-test
# =========================================================================

set run_test 0
foreach arg $argv {
    if {$arg eq "--run-test"} { set run_test 1 }
}

if {$run_test} {
    if {[program_fpga] == 0} {
        run_self_test
    }
    disconnect
    exit 0
} else {
    puts ""
    puts "=== Viterbi Decoder XSDB Demo ==="
    puts ""
    puts "Available commands:"
    puts "  program_fpga ?bitfile?    -- Program FPGA and init PS7"
    puts "  reset_decoder             -- Soft reset (mode 0->1)"
    puts "  send_byte <hex>           -- Send one encoded byte"
    puts "  read_fifo                 -- Read all bytes from output FIFO"
    puts "  decode_frame {b0 b1 ...}  -- Decode a full frame"
    puts "  run_self_test             -- Run built-in self test"
    puts "  gpio_read                 -- Read GPIO status"
    puts "  get_status / get_fifo_byte -- Read TT outputs"
    puts ""
    puts "Example:"
    puts "  program_fpga"
    puts "  decode_frame {0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00}"
    puts "  run_self_test"
    puts ""
}
