connect
after 1000

puts "=== Programming PL ==="
targets -set -filter {name =~ "xc7z020*"}
fpga -file ./vivado_project_ps7/viterbi_ps7.bit
after 1000

puts "=== Initializing PS7 ==="
targets -set -filter {name =~ "*A9*#0"}
catch {stop}
after 200
rst -processor
after 500

source ./vivado_project_ps7/viterbi_ps7.gen/sources_1/bd/system/ip/system_ps7_0/ps7_init.tcl
ps7_init
ps7_post_config
after 500

puts "=== Testing GPIO with -force ==="
mwr -force 0x41200000 0x00000080
after 10

set status [mrd -force -value 0x41210000]
set uo  [expr {$status & 0xFF}]
set uio [expr {($status >> 8) & 0xFF}]
puts "uo_out  = 0x[format %02X $uo]"
puts "uio_out = 0x[format %02X $uio]"
puts "  byte_in_ready  = [expr {($uo >> 0) & 1}]"
puts "  byte_out_valid = [expr {($uo >> 1) & 1}]"
puts "  rx_sym_ready   = [expr {($uo >> 2) & 1}]"

puts "=== SUCCESS ==="
disconnect
exit
