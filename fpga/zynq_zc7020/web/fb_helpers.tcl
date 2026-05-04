# =============================================================================
# fb_helpers.tcl -- TCL procedures for persistent XSDB session
#
# Sourced once into a long-running XSDB process. Provides high-level
# commands that batch all AXI register operations into single calls,
# minimizing Python<->XSDB roundtrips.
#
# Register Map (base = 0x43C00000):
#   0x000  CTRL       [0]=trigger, [1]=soft_reset
#   0x004  STATUS     [0]=busy, [1]=done, [15:8]=output byte count
#   0x008  FRAME_LEN  [8:0]=input byte count
#   0x400  INPUT_BUF  256-byte write buffer (64 x 32-bit words)
#   0x800  OUTPUT_BUF 256-byte read buffer  (64 x 32-bit words)
# =============================================================================

set ::FB_BASE 0x43C00000

proc fb_addr {offset} {
    return [format "0x%08X" [expr {$::FB_BASE + $offset}]]
}

# -----------------------------------------------------------------------------
# fb_ping -- Health check: read STATUS register
# Returns: decimal status value
# -----------------------------------------------------------------------------
proc fb_ping {} {
    set val [mrd -force -value [fb_addr 0x004]]
    return $val
}

# -----------------------------------------------------------------------------
# fb_decode {frame_len word_list}
#   frame_len  - number of input bytes (1-256)
#   word_list  - TCL list of 32-bit words (decimal), written to INPUT_BUF
#
# Returns: TCL list {out_count word0 word1 ...}
# -----------------------------------------------------------------------------
proc fb_decode {frame_len word_list} {
    set addr_ctrl      [fb_addr 0x000]
    set addr_status    [fb_addr 0x004]
    set addr_frame_len [fb_addr 0x008]
    set addr_in_base   [expr {$::FB_BASE + 0x400}]
    set addr_out_base  [expr {$::FB_BASE + 0x800}]

    # 1. Write FRAME_LEN
    mwr -force $addr_frame_len $frame_len

    # 2. Write input words to INPUT_BUF
    set widx 0
    foreach w $word_list {
        set addr [format "0x%08X" [expr {$addr_in_base + $widx * 4}]]
        mwr -force $addr $w
        incr widx
    }

    # 3. Trigger frame processing
    mwr -force $addr_ctrl 0x00000001

    # 4. Poll STATUS for done (bit 1), up to 2000 iterations (~2s)
    for {set i 0} {$i < 2000} {incr i} {
        set s [mrd -force -value $addr_status]
        if {$s & 0x02} break
        after 1
    }

    # 5. Read final status
    set status [mrd -force -value $addr_status]
    set out_count [expr {($status >> 8) & 0xFF}]

    # 6. Read output buffer words
    set n_out_words [expr {($out_count + 3) / 4}]
    set result [list $out_count]
    for {set w 0} {$w < $n_out_words} {incr w} {
        set addr [format "0x%08X" [expr {$addr_out_base + $w * 4}]]
        set val [mrd -force -value $addr]
        lappend result $val
    }

    return $result
}
