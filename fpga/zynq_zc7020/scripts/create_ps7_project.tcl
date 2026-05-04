# =============================================================================
# create_ps7_project.tcl -- PS7 block design with AXI-Lite export for
#                           Viterbi decoder frame buffer
#
# Creates a Vivado project with:
#   - ZYNQ7 PS (PYNQ-Z2 board preset, FCLK_CLK0=50MHz, UART0 on MIO14/15)
#   - AXI-Lite master exported to PL for viterbi_axi_framebuf
#   - No GPIO IPs (replaced by custom AXI-Lite frame buffer in top_ps7.v)
#
# Usage:  vivado -mode batch -source scripts/create_ps7_project.tcl
#         (run from fpga/zynq_zc7020/)
# =============================================================================

set proj_name   "viterbi_ps7"
set proj_dir    "./vivado_project_ps7"
set part        "xc7z020clg400-1"
set board_part  "tul.com.tw:pynq-z2:part0:1.0"

# Resolve source directories
set script_dir  [file dirname [info script]]
set base_dir    [file normalize "$script_dir/.."]
set fpga_src    "$base_dir/src"
set rtl_src     [file normalize "$base_dir/../../src"]
set constr_dir  "$base_dir/constraints"

# =========================================================================
# 1. Create project with PYNQ-Z2 board part
# =========================================================================
create_project $proj_name $proj_dir -part $part -force
set_property board_part $board_part [current_project]
set_property target_language Verilog [current_project]

# =========================================================================
# 2. Create block design
# =========================================================================
create_bd_design "system"

# --- PS7 ---
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]

# Apply board preset (configures DDR3, MIO, UART0, etc. for PYNQ-Z2)
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {
    make_external "FIXED_IO, DDR"
    apply_board_preset "1"
    Master "Disable"
    Slave "Disable"
} $ps7

# Override: enable M_AXI_GP0 and set FCLK to 50 MHz
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
] $ps7

# --- AXI Interconnect (1 master, 1 slave -- just passes through) ---
set axi_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0]
set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
] $axi_ic

# --- Processor System Reset ---
set rst_gen [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_50M]

# --- Clock and reset connections ---
# FCLK_CLK0 -> interconnect, reset generator
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_interconnect_0/ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_interconnect_0/S00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_interconnect_0/M00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins rst_ps7_50M/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7_50M/ext_reset_in]

# Reset connections
connect_bd_net [get_bd_pins rst_ps7_50M/interconnect_aresetn] [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] [get_bd_pins axi_interconnect_0/S00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] [get_bd_pins axi_interconnect_0/M00_ARESETN]

# --- Connect PS7 M_AXI_GP0 -> Interconnect S00 ---
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_net [get_bd_pins ps7/M_AXI_GP0_ACLK] [get_bd_pins ps7/FCLK_CLK0]

# --- Export PL clock first (needed for AXI clock association) ---
create_bd_port -dir O -type clk pl_clk
set_property CONFIG.FREQ_HZ 50000000 [get_bd_ports pl_clk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_ports pl_clk]

create_bd_port -dir O -type rst pl_resetn
connect_bd_net [get_bd_pins rst_ps7_50M/peripheral_aresetn] [get_bd_ports pl_resetn]

# --- Export M00_AXI as external AXI-Lite interface ---
# This creates external ports that top_ps7.v connects to viterbi_axi_framebuf
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI
set_property -dict [list \
    CONFIG.PROTOCOL {AXI4LITE} \
    CONFIG.ADDR_WIDTH {32} \
    CONFIG.DATA_WIDTH {32} \
    CONFIG.FREQ_HZ {50000000} \
] [get_bd_intf_ports M_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] [get_bd_intf_ports M_AXI]

# Associate the AXI interface with the clock port
set_property CONFIG.ASSOCIATED_BUSIF {M_AXI} [get_bd_ports pl_clk]

# --- Address mapping: 0x43C00000, 4K ---
create_bd_addr_seg -range 0x1000 -offset 0x43C00000 \
    [get_bd_addr_spaces ps7/Data] \
    [get_bd_addr_segs M_AXI/Reg] \
    SEG_framebuf

# --- Validate and save ---
regenerate_bd_layout
validate_bd_design
save_bd_design

# Generate output products (creates .hwh file)
generate_target all [get_files system.bd]

# Create HDL wrapper
make_wrapper -files [get_files system.bd] -top
set wrapper_file [glob "$proj_dir/$proj_name.gen/sources_1/bd/system/hdl/system_wrapper.v"]
add_files -norecurse $wrapper_file
update_compile_order -fileset sources_1

puts ">>> Block design created successfully."
puts ">>> Address segments:"
set addr_segs [get_bd_addr_segs]
foreach seg $addr_segs {
    puts "  $seg : offset=[get_property OFFSET $seg] range=[get_property RANGE $seg]"
}

# =========================================================================
# 3. Add RTL sources -- Viterbi decoder core
# =========================================================================
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

# Add FPGA-specific sources
add_files -norecurse [list \
    "$fpga_src/top_ps7.v"              \
    "$fpga_src/viterbi_axi_framebuf.v" \
]

# Mark SystemVerilog files
set sv_names [list project.v viterbi_core.v acs_core.v traceback_v2.v \
                   branch_metric.v expected_bits.v pm_bank.v survivor_mem.v]
foreach f [get_files -of_objects [current_fileset]] {
    if {[file tail $f] in $sv_names} {
        set_property file_type SystemVerilog $f
        puts "  -> Set SystemVerilog: [file tail $f]"
    }
}

# =========================================================================
# 4. Add constraints
# =========================================================================
add_files -fileset constrs_1 -norecurse "$constr_dir/ps7_pins.xdc"

# =========================================================================
# 5. Set top module
# =========================================================================
set_property top top_ps7 [current_fileset]
update_compile_order -fileset sources_1

# =========================================================================
# Summary
# =========================================================================
puts "============================================="
puts "Project created: $proj_name"
puts "Board:           PYNQ-Z2 ($part)"
puts "Top module:      top_ps7"
puts "Block design:    system (PS7 + AXI-Lite export)"
puts "Frame buffer:    0x43C00000 (4 KB)"
puts "Project dir:     $proj_dir"
puts "============================================="
