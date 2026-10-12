array set ALGO_DEF {
    pass      {ALGO_PASS         out_pass.bmp     PASS}   ;# pass-through
    gray      {ALGO_GRAY         out_gray.bmp     GRAY}   ;# grayscale
    threshold {ALGO_THRESHOLD    out_thresh.bmp   THRESHOLD}   ;# color detect
    dilate    {ALGO_MORPH_DILATE out_dilate.bmp   MORPH_DILATE}   ;# dilate
    erode     {ALGO_MORPH_ERODE  out_erode.bmp    MORPH_ERODE}   ;# erode
    scale2x   {ALGO_SCALE_2X     out_scale2x.bmp  SCALE_2X}   ;# scale x2
    sharpen   {ALGO_SHARPEN      out_sharpen.bmp  SHARPEN}   ;# sharpen
}

set ::DSH_PROJ_ROOT [file normalize [file join [file dirname [info script]] ..]]

set M_ALGO_BEGIN {// ### ALGO_SELECT_BEGIN ###}
set M_ALGO_END   {// ### ALGO_SELECT_END ###}
set M_NAME_BEGIN {// ### OUT_NAME_BEGIN ###}
set M_NAME_END   {// ### OUT_NAME_END ###}
set M_MODE_BEGIN {// ### MODE_BEGIN ###}
set M_MODE_END   {// ### MODE_END ###}

proc replace_block {txt mbegin mend body} {   ;# txt/mbegin/mend/body = 原文/起始标记/结束标记/新内容
    set i [string first $mbegin $txt]
    set j [string first $mend $txt]
    if {$i < 0 || $j < 0 || $j < $i} {
        error "marker not found: $mbegin / $mend"
    }
    set i_end [expr {$i + [string length $mbegin]}]

    return "[string range $txt 0 [expr {$i_end - 1}]]\n$body\n[string range $txt $j end]"
}

proc set_algo {args} {   ;# args = 算法名（省略则列出全部）
    global ALGO_DEF M_ALGO_BEGIN M_ALGO_END M_NAME_BEGIN M_NAME_END

    if {[llength $args] != 1} {
        puts "set_algo: available algorithms are"
        foreach k [lsort [array names ALGO_DEF]] {
            lassign $ALGO_DEF($k) macro bmp tag
            puts [format "    %-10s -> macro %-18s output %-16s tag %s" $k $macro $bmp $tag]
        }
        return
    }
    set algo [lindex $args 0]
    if {![info exists ALGO_DEF($algo)]} {
        puts "set_algo: unknown algorithm '$algo' (call 'set_algo' with no argument to list them)"
        return
    }
    lassign $ALGO_DEF($algo) macro bmp tag

    set root $::DSH_PROJ_ROOT
    set tb         [file join $root tb tb_image_top.v]
    if {![file exists $tb]} {
        puts "set_algo: cannot find $tb"
        return
    }
    set root_fwd [string map {\\ /} $root]

    set algo_body ""
    foreach k [lsort [array names ALGO_DEF]] {
        lassign $ALGO_DEF($k) m _b _t
        if {$m eq $macro} {
            append algo_body "`define $m\n"
        } else {
            append algo_body "// `define $m\n"
        }
    }

    set name_body ""
    append name_body "`ifdef PATH_MODE_ABS\n"
    append name_body "  `define IMG_MEM_PATH \"$root_fwd/data/image.mem\"\n"
    append name_body "  `define BMP_PATH     \"$root_fwd/out/$bmp\"\n"
    append name_body "  `define REF_BMP_PATH \"$root_fwd/out/out_ref.bmp\"\n"
    append name_body "`else\n"
    append name_body "  `define IMG_MEM_PATH \"../../data/image.mem\"\n"
    append name_body "  `define BMP_PATH     \"../../out/$bmp\"\n"
    append name_body "  `define REF_BMP_PATH \"../../out/out_ref.bmp\"\n"
    append name_body "`endif\n"
    append name_body "`define ALGO_TAG \"$tag\"\n"

    set fh [open $tb r]
    fconfigure $fh -encoding utf-8 -translation lf
    set txt [read $fh]
    close $fh

    set txt [replace_block $txt $M_ALGO_BEGIN $M_ALGO_END $algo_body]
    set txt [replace_block $txt $M_NAME_BEGIN $M_NAME_END $name_body]

    set fh [open $tb w]
    fconfigure $fh -encoding utf-8 -translation lf
    puts -nonewline $fh $txt
    close $fh

    puts "set_algo: switched to '$algo'  (macro $macro, output out/$bmp, tag $tag)"
    puts "set_algo: now Run Simulation and look for the \[TB\]\[REF\] verdict line"
}

proc set_src {args} {   ;# args = mem | pattern（数据源）
    global M_MODE_BEGIN M_MODE_END

    if {[llength $args] != 1} {
        puts "set_src: usage: set_src mem | set_src pattern"
        puts "   mem     : read the picture from data/image.mem (use your own image)"
        puts "   pattern : generate the built-in test pattern in RTL (no external file)"
        return
    }
    set which [lindex $args 0]
    if {$which eq "mem"} {
        set body "`define CFG_SCRIPT_MODE\n`define PATH_MODE_ABS\n// `define CFG_GUI_MODE"
    } elseif {$which eq "pattern"} {
        set body "// `define CFG_SCRIPT_MODE\n// `define PATH_MODE_ABS\n`define CFG_GUI_MODE"
    } else {
        puts "set_src: unknown source '$which' (use mem or pattern)"
        return
    }

    set root $::DSH_PROJ_ROOT
    set tb         [file join $root tb tb_image_top.v]
    if {![file exists $tb]} { puts "set_src: cannot find $tb"; return }

    set fh [open $tb r]
    fconfigure $fh -encoding utf-8 -translation lf
    set txt [read $fh]
    close $fh

    if {[catch {set txt [replace_block $txt $M_MODE_BEGIN $M_MODE_END $body]} err]} {
        puts "set_src: $err"
        return
    }

    set fh [open $tb w]
    fconfigure $fh -encoding utf-8 -translation lf
    puts -nonewline $fh $txt
    close $fh

    if {$which eq "mem"} {
        puts "set_src: picture source = data/image.mem  (create it with scripts/img2mem.tcl)"
    } else {
        puts "set_src: picture source = built-in RTL test pattern"
    }
    puts "set_src: now Run Simulation and look for the \[TB\]\[REF\] verdict line"
}

proc set_paths {} {   ;# no arg: rewrite absolute paths for the current location
    global ALGO_DEF M_ALGO_BEGIN M_ALGO_END M_NAME_BEGIN M_NAME_END

    set root $::DSH_PROJ_ROOT
    set tb         [file join $root tb tb_image_top.v]
    if {![file exists $tb]} { puts "set_paths: cannot find $tb"; return }
    set root_fwd [string map {\\ /} $root]

    set fh [open $tb r]
    fconfigure $fh -encoding utf-8 -translation lf
    set txt [read $fh]
    close $fh

    set i [string first $M_ALGO_BEGIN $txt]
    set j [string first $M_ALGO_END   $txt]
    if {$i < 0 || $j < 0} { puts "set_paths: ALGO markers not found"; return }
    set body [string range $txt $i $j]

    set algo ""
    foreach line [split $body "\n"] {
        set t [string trim $line]
        if {[string match "//*" $t]} { continue }
        foreach k [array names ALGO_DEF] {
            lassign $ALGO_DEF($k) macro _b _t
            if {[string first "`define $macro" $t] == 0} {
                set algo $k
                break
            }
        }
        if {$algo ne ""} { break }
    }
    if {$algo eq ""} { puts "set_paths: no algorithm macro is enabled in the TB"; return }
    lassign $ALGO_DEF($algo) macro bmp tag
    puts "set_paths: current algorithm = $algo"

    set name_body ""
    append name_body "`ifdef PATH_MODE_ABS\n"
    append name_body "  `define IMG_MEM_PATH \"$root_fwd/data/image.mem\"\n"
    append name_body "  `define BMP_PATH     \"$root_fwd/out/$bmp\"\n"
    append name_body "  `define REF_BMP_PATH \"$root_fwd/out/out_ref.bmp\"\n"
    append name_body "`else\n"
    append name_body "  `define IMG_MEM_PATH \"../../data/image.mem\"\n"
    append name_body "  `define BMP_PATH     \"../../out/$bmp\"\n"
    append name_body "  `define REF_BMP_PATH \"../../out/out_ref.bmp\"\n"
    append name_body "`endif\n"
    append name_body "`define ALGO_TAG \"$tag\"\n"

    if {[catch {set txt [replace_block $txt $M_NAME_BEGIN $M_NAME_END $name_body]} err]} {
        puts "set_paths: $err"
        return
    }

    set fh [open $tb w]
    fconfigure $fh -encoding utf-8 -translation lf
    puts -nonewline $fh $txt
    close $fh

    puts "set_paths: absolute paths now point at $root"
    puts "set_paths: now Run Simulation"
}

puts "set_algo.tcl loaded. Usage:  set_algo <pass|gray|threshold|dilate|erode|scale2x|sharpen>"
