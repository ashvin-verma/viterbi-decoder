# =============================================================================
# build.tcl -- Run synthesis, implementation, and bitstream generation
#
# Usage:  vivado -mode batch -source scripts/build.tcl
#         (run from fpga/zynq_zc7020/)
#
# Prerequisite: Run create_project.tcl first to create the Vivado project.
# =============================================================================

set proj_name "viterbi_zynq"
set proj_dir  "./vivado_project"

# Open the existing project
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

# Check synthesis status
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}
puts ">>> Synthesis complete."

# Open the synthesized design for reporting
open_run synth_1

# Post-synthesis utilization report
report_utilization -file "$proj_dir/reports/post_synth_utilization.rpt"
report_timing_summary -file "$proj_dir/reports/post_synth_timing.rpt"

# -------------------------------------------------------------------------
# Implementation (opt, place, route)
# -------------------------------------------------------------------------
puts ">>> Running implementation..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Check implementation status
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    puts "ERROR: Implementation failed!"
    exit 1
}
puts ">>> Implementation complete."

# Open implemented design for reporting
open_run impl_1

# Post-implementation reports
report_utilization -file "$proj_dir/reports/post_impl_utilization.rpt"
report_timing_summary -file "$proj_dir/reports/post_impl_timing.rpt"
report_power -file "$proj_dir/reports/post_impl_power.rpt"
report_drc -file "$proj_dir/reports/post_impl_drc.rpt"

# -------------------------------------------------------------------------
# Locate bitstream
# -------------------------------------------------------------------------
set bit_file [glob -nocomplain "$proj_dir/$proj_name.runs/impl_1/*.bit"]
if {$bit_file ne ""} {
    puts "============================================="
    puts "Bitstream generated: $bit_file"
    puts "============================================="
    # Copy bitstream to a convenient location
    file copy -force $bit_file "$proj_dir/$proj_name.bit"
    puts "Copied to: $proj_dir/$proj_name.bit"
} else {
    puts "WARNING: Bitstream file not found in expected location."
}

puts ">>> Build complete."
