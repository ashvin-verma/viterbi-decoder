connect
targets -set -filter {name =~ "*A9*#0"}

set BASE 0x43C00000

# Read initial status
set s0 [mrd -force -value [expr {$BASE + 0x004}]]
puts "INITIAL_STATUS: 0x$s0"

# Soft reset first
mwr -force [expr {$BASE + 0x000}] 0x00000002
after 10
mwr -force [expr {$BASE + 0x000}] 0x00000000
after 10

set s1 [mrd -force -value [expr {$BASE + 0x004}]]
puts "AFTER_RESET_STATUS: 0x$s1"

# Write FRAME_LEN = 15
mwr -force [expr {$BASE + 0x008}] 15
set fl [mrd -force -value [expr {$BASE + 0x008}]]
puts "FRAME_LEN_READBACK: 0x$fl"

# Write input bytes: 0x1c, 0x2f, 0xf1, 0x0e, then 11 bytes of 0x00
# Word 0: {0x0e, 0xf1, 0x2f, 0x1c} = 0x0EF12F1C
mwr -force [expr {$BASE + 0x400}] 0x0EF12F1C
# Words 1-3: all zeros
mwr -force [expr {$BASE + 0x404}] 0x00000000
mwr -force [expr {$BASE + 0x408}] 0x00000000
mwr -force [expr {$BASE + 0x40C}] 0x00000000

# Trigger
mwr -force [expr {$BASE + 0x000}] 0x00000001

# Poll
for {set i 0} {$i < 500} {incr i} {
    set s [expr 0x[mrd -force -value [expr {$BASE + 0x004}]]]
    puts "POLL_$i: $s (busy=[expr {$s & 1}] done=[expr {($s>>1)&1}] count=[expr {($s>>8)&0xFF}])"
    if {$s & 0x02} break
    after 5
}

# Final status
set final [expr 0x[mrd -force -value [expr {$BASE + 0x004}]]]
puts "FINAL: status=$final busy=[expr {$final & 1}] done=[expr {($final>>1)&1}] count=[expr {($final>>8)&0xFF}]"

# Read output words
set count [expr {($final >> 8) & 0xFF}]
set nw [expr {($count + 3) / 4}]
puts "Reading $nw output words ($count bytes):"
for {set w 0} {$w < $nw} {incr w} {
    set addr [expr {$BASE + 0x800 + $w * 4}]
    set val [mrd -force -value $addr]
    puts "  OUT_W$w: 0x$val"
}

# Also read unmapped address for sanity
set dead [mrd -force -value [expr {$BASE + 0x00C}]]
puts "UNMAPPED_READ: 0x$dead"

disconnect
