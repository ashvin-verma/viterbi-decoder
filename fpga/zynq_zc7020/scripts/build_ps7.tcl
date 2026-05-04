# =============================================================================
# build_ps7.tcl -- Synthesize, implement, generate bitstream, export hardware
#
# Usage:  vivado -mode batch -source scripts/build_ps7.tcl
#         (run from fpga/zynq_zc7020/)
#
# Prerequisite: Run create_ps7_project.tcl first.
# =============================================================================

set proj_name "viterbi_ps7"
set proj_dir  "./vivado_project_ps7"

# Open project
open_project "$proj_dir/$proj_name.xpr"

# Create reports directory
file mkdir "$proj_dir/reports"

# -------------------------------------------------------------------------
# Synthesis
# -------------------------------------------------------------------------
puts ">>> Running synthesis..."
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    puts "Status: [get_property STATUS [get_runs synth_1]]"
    exit 1
}
puts ">>> Synthesis complete."

open_run synth_1
report_utilization -file "$proj_dir/reports/post_synth_utilization.rpt"
report_timing_summary -file "$proj_dir/reports/post_synth_timing.rpt"

# -------------------------------------------------------------------------
# Implementation + Bitstream
# -------------------------------------------------------------------------
puts ">>> Running implementation..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    puts "ERROR: Implementation failed!"
    puts "Status: [get_property STATUS [get_runs impl_1]]"
    exit 1
}
puts ">>> Implementation complete."

open_run impl_1
report_utilization -file "$proj_dir/reports/post_impl_utilization.rpt"
report_timing_summary -file "$proj_dir/reports/post_impl_timing.rpt"
report_power -file "$proj_dir/reports/post_impl_power.rpt"

# -------------------------------------------------------------------------
# Copy bitstream
# -------------------------------------------------------------------------
set bit_file [glob -nocomplain "$proj_dir/$proj_name.runs/impl_1/*.bit"]
if {$bit_file ne ""} {
    file copy -force $bit_file "$proj_dir/$proj_name.bit"
    puts ">>> Bitstream: $proj_dir/$proj_name.bit"
} else {
    puts "WARNING: Bitstream not found."
}

# -------------------------------------------------------------------------
# Export hardware (.xsa) -- includes ps7_init.tcl for XSDB
# -------------------------------------------------------------------------
puts ">>> Exporting hardware..."
write_hw_platform -fixed -include_bit -force "$proj_dir/$proj_name.xsa"
puts ">>> Hardware exported: $proj_dir/$proj_name.xsa"

# -------------------------------------------------------------------------
# Also copy the .hwh file for potential PYNQ overlay use
# -------------------------------------------------------------------------
set hwh_file [glob -nocomplain "$proj_dir/$proj_name.gen/sources_1/bd/system/hw_handoff/*.hwh"]
if {$hwh_file ne ""} {
    file copy -force $hwh_file "$proj_dir/$proj_name.hwh"
    puts ">>> HWH file: $proj_dir/$proj_name.hwh"
}

puts ">>> Build complete."
