# =============================================================================
# program.tcl -- Program the PYNQ-Z2 FPGA with the Viterbi decoder bitstream
#
# Usage:  vivado -mode batch -source scripts/program.tcl
#         (run from fpga/zynq_zc7020/)
# =============================================================================

set bit_file "./vivado_project/viterbi_zynq.bit"

if {![file exists $bit_file]} {
    puts "ERROR: Bitstream not found at $bit_file"
    puts "Run build.tcl first."
    exit 1
}

# Connect to hardware
open_hw_manager
connect_hw_server -allow_non_jtag

# Auto-detect target
open_hw_target

# List all devices and find the xc7z020
puts "=== Available devices ==="
foreach d [get_hw_devices] {
    puts "  $d"
}

# Find the programmable FPGA device (xc7z020, not arm_dap)
set device [get_hw_devices xc7z020*]
if {$device eq ""} {
    # Fall back to second device if name doesn't match
    set device [lindex [get_hw_devices] 1]
}
puts "=== Programming device: $device ==="

current_hw_device $device
set_property PROGRAM.FILE $bit_file $device

# Program the device
program_hw_devices $device

puts "=== Programming complete! ==="
puts "Bitstream: $bit_file"

# Close
close_hw_target
disconnect_hw_server
close_hw_manager
