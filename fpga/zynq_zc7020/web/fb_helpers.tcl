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
# fb_program {bit_path ps7_init_path}
#   Program PL, init PS7, verify frame buffer. Every step is checked.
#   Returns "OK <status>" or "FAIL <step>: <message>".
#   NOTE: never issues rst -system on the xc7z020 target -- that leaves the
#   DAP in "APB AP transaction error" until the board is power cycled.
# -----------------------------------------------------------------------------
proc fb_arm_present {} {
    return [expr {[catch {targets -set -filter {name =~ "*A9*#0"}}] == 0}]
}

proc fb_program {bit_path ps7_init_path} {
    if {![fb_arm_present]} {
        return "FAIL no_arm: ARM core not visible on JTAG (power-cycle the board)"
    }
    if {[catch {targets -set -filter {name =~ "xc7z020*"}} e]} {
        return "FAIL target_pl: $e"
    }
    if {[catch {fpga -file $bit_path} e]} {
        return "FAIL fpga: $e"
    }
    after 1000
    if {![fb_arm_present]} {
        return "FAIL no_arm_after_fpga: ARM core vanished after programming PL"
    }
    catch {stop}
    after 200
    # rst -processor occasionally fails with an AHB AP transaction error right
    # after PL reconfiguration. ps7_init only needs a halted core, so accept a
    # failed reset as long as the core reports Stopped.
    if {[catch {rst -processor} e]} {
        after 500
        if {[catch {rst -processor} e2]} {
            catch {stop}
            if {[catch {state} st] || ![string match "Stopped*" $st]} {
                return "FAIL rst_processor: $e2"
            }
        }
    }
    after 500
    if {$ps7_init_path ne ""} {
        # ps7_init.tcl defines globals with top-level `set`; it must be
        # sourced (and its procs run) at global scope, not inside this proc.
        if {[catch {uplevel #0 [list source $ps7_init_path]} e]} { return "FAIL source_ps7_init: $e" }
        if {[catch {uplevel #0 ps7_init} e]} { return "FAIL ps7_init: $e" }
        if {[catch {uplevel #0 ps7_post_config} e]} { return "FAIL ps7_post_config: $e" }
    }
    after 500
    if {[catch {fb_ping} v]} {
        return "FAIL fb_ping: $v"
    }
    return "OK $v"
}

# -----------------------------------------------------------------------------
# fb_read_words {offset n} -- block read n 32-bit words starting at offset
# -----------------------------------------------------------------------------
proc fb_read_words {offset n} {
    set out {}
    set addr [expr {$::FB_BASE + $offset}]
    while {$n > 0} {
        set c [expr {$n > 512 ? 512 : $n}]
        if {$c == 1} {
            lappend out [mrd -force -value [format 0x%08X $addr]]
        } else {
            foreach v [mrd -force -value [format 0x%08X $addr] $c] { lappend out $v }
        }
        incr addr [expr {$c * 4}]
        incr n -$c
    }
    return $out
}

# -----------------------------------------------------------------------------
# fb_hwconfig -- {ver G1 G0 D K} word written into the bitstream (0 = old bit)
# -----------------------------------------------------------------------------
proc fb_hwconfig {} {
    return [mrd -force -value [fb_addr 0x014]]
}

# -----------------------------------------------------------------------------
# fb_trellis {read_pm} -- read back the trellis captured during the last frame
# Returns 4 lines: "entries steps" / pm words / survivor words / best words
# -----------------------------------------------------------------------------
proc fb_trellis {read_pm} {
    set entries [expr {[mrd -force -value [fb_addr 0x00C]] & 0x1FFFF}]
    set steps   [expr {[mrd -force -value [fb_addr 0x010]] & 0x7FF}]
    set pm {}
    if {$read_pm && $entries > 0} {
        set pm [fb_read_words 0x20000 [expr {($entries + 3) / 4}]]
    }
    set sv {}
    if {$entries > 0} { set sv [fb_read_words 0x10000 [expr {($entries + 31) / 32}]] }
    set best {}
    if {$steps > 0} { set best [fb_read_words 0x14000 [expr {($steps + 3) / 4}]] }
    return "$entries $steps\nPM $pm\nSV $sv\nBS $best"
}

# -----------------------------------------------------------------------------
# fb_ber_point {thresh maxerrs timeout_ms seed}
#   Run the on-chip BER tester at one channel crossover threshold until
#   maxerrs decoded errors or timeout_ms elapses.
#   Returns: status bits_lo bits_hi errs_lo errs_hi flips_lo flips_hi
#            chbits_lo chbits_hi cycles_lo cycles_hi
# -----------------------------------------------------------------------------
proc fb_ber_point {thresh maxerrs timeout_ms seed} {
    set b [expr {$::FB_BASE + 0x100}]
    mwr -force [format 0x%08X [expr {$b + 0x08}]] [format 0x%08X $thresh]
    mwr -force [format 0x%08X [expr {$b + 0x0C}]] 0
    mwr -force [format 0x%08X [expr {$b + 0x10}]] 0
    mwr -force [format 0x%08X [expr {$b + 0x14}]] [format 0x%08X $maxerrs]
    mwr -force [format 0x%08X [expr {$b + 0x18}]] [format 0x%08X $seed]
    mwr -force [format 0x%08X $b] 1
    set t0 [clock milliseconds]
    while {1} {
        after 25
        set st [mrd -force -value [format 0x%08X [expr {$b + 0x04}]]]
        if {!($st & 1)} break
        if {[clock milliseconds] - $t0 > $timeout_ms} {
            mwr -force [format 0x%08X $b] 2
            after 1
            break
        }
    }
    set st [mrd -force -value [format 0x%08X [expr {$b + 0x04}]]]
    set vals [mrd -force -value [format 0x%08X [expr {$b + 0x20}]] 10]
    return [concat $st $vals]
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
