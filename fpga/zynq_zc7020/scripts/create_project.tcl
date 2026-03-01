# =============================================================================
# create_project.tcl -- Create Vivado project for PYNQ-Z2 Viterbi decoder
#
# Usage:  vivado -mode batch -source scripts/create_project.tcl
#         (run from fpga/zynq_zc7020/)
# =============================================================================

# Project name and directory
set proj_name   "viterbi_zynq"
set proj_dir    "./vivado_project"
set part        "xc7z020clg400-1"

# Resolve source directories relative to this script
set script_dir  [file dirname [info script]]
set base_dir    [file normalize "$script_dir/.."]
set fpga_src    "$base_dir/src"
set rtl_src     [file normalize "$base_dir/../../src"]
set constr_dir  "$base_dir/constraints"

# Create project
create_project $proj_name $proj_dir -part $part -force

# Set project properties
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]

# -------------------------------------------------------------------------
# Add RTL sources -- Viterbi decoder core (from ../../src)
# -------------------------------------------------------------------------
add_files -norecurse [list \
    "$rtl_src/project.v"             \
    "$rtl_src/viterbi_core.v"        \
    "$rtl_src/acs_core.v"            \
    "$rtl_src/branch_metric.v"       \
    "$rtl_src/expected_bits.v"       \
    "$rtl_src/pm_bank.v"             \
    "$rtl_src/survivor_mem.v"        \
    "$rtl_src/traceback_v2.v"        \
    "$rtl_src/sym_unpacker_4x.v"     \
    "$rtl_src/bit_packer_8x.v"       \
    "$rtl_src/ham2.v"                \
    "$rtl_src/ham3.v"                \
]

# -------------------------------------------------------------------------
# Add FPGA-specific sources (UART, bridge, top)
# -------------------------------------------------------------------------
add_files -norecurse [list \
    "$fpga_src/top_zynq.v"           \
    "$fpga_src/uart_rx.v"            \
    "$fpga_src/uart_tx.v"            \
    "$fpga_src/uart_viterbi_bridge.v" \
]

# -------------------------------------------------------------------------
# Add constraint files
# -------------------------------------------------------------------------
add_files -fileset constrs_1 -norecurse [list \
    "$constr_dir/pynq_z2.xdc"       \
    "$constr_dir/timing.xdc"         \
]

# -------------------------------------------------------------------------
# Set top module
# -------------------------------------------------------------------------
set_property top top_zynq [current_fileset]

# -------------------------------------------------------------------------
# Mark SystemVerilog files (.v with SV constructs) as SystemVerilog
# -------------------------------------------------------------------------
set sv_names [list project.v viterbi_core.v acs_core.v traceback_v2.v \
                   branch_metric.v expected_bits.v pm_bank.v survivor_mem.v]
foreach f [get_files -of_objects [current_fileset]] {
    if {[file tail $f] in $sv_names} {
        set_property file_type SystemVerilog $f
        puts "  -> Set SystemVerilog: [file tail $f]"
    }
}

# Update compile order
update_compile_order -fileset sources_1

# Print summary
puts "============================================="
puts "Project created: $proj_name"
puts "Part:            $part"
puts "Top module:      top_zynq"
puts "Project dir:     $proj_dir"
puts "============================================="
