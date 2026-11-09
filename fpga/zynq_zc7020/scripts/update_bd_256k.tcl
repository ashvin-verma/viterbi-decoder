# =============================================================================
# update_bd_256k.tcl -- One-time migration of the existing PS7 project:
#   * widen the frame-buffer AXI window from 4 KB to 256 KB
#     (trellis capture BRAM lives at +0x10000 .. +0x3FFFF)
#   * add ber_tester.v to the sources
# Usage (from fpga/zynq_zc7020):
#   vivado -mode batch -source scripts/update_bd_256k.tcl
# =============================================================================
set proj_dir  "./vivado_project_ps7"
set proj_name "viterbi_ps7"
open_project "$proj_dir/$proj_name.xpr"

open_bd_design [get_files system.bd]
set segs [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps7/Data]]
puts ">>> Address segments: $segs"
foreach seg $segs {
    if {[get_property OFFSET $seg] eq "0x43C00000"} {
        set_property range 256K $seg
        puts ">>> $seg range -> [get_property RANGE $seg]"
    }
}
validate_bd_design
save_bd_design
generate_target all [get_files system.bd]

set ber_src [file normalize "./src/ber_tester.v"]
if {[llength [get_files -quiet $ber_src]] == 0} {
    add_files -norecurse $ber_src
    puts ">>> Added $ber_src"
}
update_compile_order -fileset sources_1
close_project
puts ">>> BD update complete."
