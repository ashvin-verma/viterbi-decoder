# bench_jtag.tcl -- time the JTAG/XSDB path for the same operations as bench_net.py
#   xsdb bench_jtag.tcl
# Reads + one frame decode only; does NOT reprogram the PL (that is what has
# wedged the DAP before, and Linux owns the PL when booted from SD).
connect
targets -set -filter {name =~ "APU*"}
source [file join [file dirname [info script]] .. web fb_helpers.tcl]

proc ms {script n} {
    set t [lindex [time {uplevel 1 $script} $n] 0]
    return [format %.1f [expr {$t / 1000.0}]]
}

puts "ping (single mrd), mean of 50 (ms):          [ms {fb_ping} 50]"
set words {}
for {set i 0} {$i < 15} {incr i} {
    set b [expr {$i * 4}]
    lappend words [expr {$b | (($b+1) << 8) | (($b+2) << 16) | (($b+3) << 24)}]
}
puts "decode 60-byte frame, mean of 5 (ms):        [ms {fb_decode 60 $words} 5]"
set t0 [clock milliseconds]
set tr [fb_trellis 1]
set dt [expr {[clock milliseconds] - $t0}]
set n 0
foreach line [split $tr "\n"] { if {[regexp {^(PM|SV|BS) (.*)} $line -> tag rest]} { incr n [llength $rest] } }
puts "trellis readback ($n words) (ms):         $dt"
if {$dt > 0} { puts "trellis readback (words/s):                 [expr {$n * 1000 / $dt}]" }
disconnect
