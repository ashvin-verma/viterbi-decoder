# =============================================================================
# build_all_k.tcl -- Build bitstreams for K=3, 5, 7, 9
#
# Opens the existing Vivado project and iterates over constraint lengths,
# setting verilog_define per K, running synth+impl+bitstream, and copying
# the result to viterbi_ps7_k{N}.bit.  K=7 is also copied to
# viterbi_ps7.bit for backward compatibility.
#
# Usage:  vivado -mode batch -source scripts/build_all_k.tcl
#         (run from fpga/zynq_zc7020/)
# =============================================================================

set proj_dir  "./vivado_project_ps7"
set proj_name "viterbi_ps7"

open_project "$proj_dir/$proj_name.xpr"

# K configs: {K D G0_dec G1_dec}
set k_configs {
    {3  12  7    5  }
    {5  24  19   29 }
    {7  42  121  91 }
    {9  60  369  491}
}

set success_list {}
set fail_list {}

foreach cfg $k_configs {
    lassign $cfg k_val d_val g0_val g1_val

    puts "============================================="
    puts ">>> Building K=$k_val (D=$d_val, G0=$g0_val, G1=$g1_val)"
    puts "============================================="

    # Set verilog defines for this K
    set defines "K_SEL=$k_val D_TB_SEL=$d_val G0_SEL=$g0_val G1_SEL=$g1_val"
    set_property verilog_define $defines [current_fileset]

    # Reset and launch synthesis
    reset_run synth_1
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1

    if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
        puts "ERROR: Synthesis failed for K=$k_val: [get_property STATUS [get_runs synth_1]]"
        lappend fail_list $k_val
        continue
    }
    puts ">>> K=$k_val synthesis OK"

    # Implementation + bitstream
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1

    if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
        puts "ERROR: Implementation failed for K=$k_val: [get_property STATUS [get_runs impl_1]]"
        lappend fail_list $k_val
        continue
    }

    # Copy bitstream with K suffix
    set bit_file [glob -nocomplain "$proj_dir/$proj_name.runs/impl_1/*.bit"]
    if {$bit_file ne ""} {
        set dst "$proj_dir/${proj_name}_k${k_val}.bit"
        file copy -force $bit_file $dst
        puts ">>> Bitstream: $dst"
        lappend success_list $k_val

        # Backward compat: K=7 also gets the default name
        if {$k_val == 7} {
            file copy -force $bit_file "$proj_dir/$proj_name.bit"
            puts ">>> Backward compat copy: $proj_dir/$proj_name.bit"
        }
    } else {
        puts "WARNING: No bitstream found for K=$k_val"
        lappend fail_list $k_val
    }
}

# Clear defines back to default
set_property verilog_define "" [current_fileset]

puts ""
puts "============================================="
puts "Build summary"
puts "  Success: $success_list"
puts "  Failed:  $fail_list"
puts "============================================="
