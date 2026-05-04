set proj_dir "./vivado_project_ps7"
set proj_name "viterbi_ps7"

open_project "$proj_dir/$proj_name.xpr"

# Re-synthesize and implement
puts ">>> Resynthesizing..."
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    puts "ERROR: Synthesis failed: [get_property STATUS [get_runs synth_1]]"
    exit 1
}
puts ">>> Synthesis OK"

puts ">>> Implementation + bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    puts "ERROR: Implementation failed: [get_property STATUS [get_runs impl_1]]"
    exit 1
}

# Copy bitstream
set bit_file [glob -nocomplain "$proj_dir/$proj_name.runs/impl_1/*.bit"]
if {$bit_file ne ""} {
    file copy -force $bit_file "$proj_dir/$proj_name.bit"
    puts ">>> Bitstream: $proj_dir/$proj_name.bit"
}

puts ">>> Build complete."
