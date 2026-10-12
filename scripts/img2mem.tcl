proc img2mem {bmpfile w h {memfile ""}} {   ;# bmpfile/w/h/memfile = 图/宽/高/输出文件
    if {![file exists $bmpfile]} {
        puts "img2mem: ERROR - file not found: $bmpfile"
        return 0
    }
    if {$memfile eq ""} { set memfile "data/image.mem" }

    set fh [open $bmpfile rb]
    fconfigure $fh -translation binary
    set data [read $fh]
    close $fh

    binary scan [string range $data 0 1] a2 magic
    if {$magic ne "BM"} {
        puts "img2mem: ERROR - $bmpfile is not a BMP file (magic='$magic')"
        puts "         JPG/PNG are not supported here: open it in Paint and"
        puts "         'Save as -> BMP picture -> 24-bit bitmap' first."
        return 0
    }
    binary scan [string range $data 10 13] i off
    binary scan [string range $data 14 17] i hdrsize
    binary scan [string range $data 18 21] i bw
    binary scan [string range $data 22 25] i bh
    binary scan [string range $data 28 29] s bpp
    binary scan [string range $data 30 33] i comp

    if {$hdrsize < 40} {
        puts "img2mem: ERROR - old BITMAPCOREHEADER is not supported; re-save as 24-bit BMP"
        return 0
    }
    if {$comp != 0} {
        puts "img2mem: ERROR - compressed BMP (compression=$comp) is not supported"
        return 0
    }
    if {$bpp != 24} {
        puts "img2mem: ERROR - need a 24-bit BMP, this one is $bpp bpp"
        puts "         In Paint: Save as -> BMP picture -> 24-bit bitmap"
        return 0
    }
    set bottom_up [expr {$bh > 0}]
    set hh [expr {abs($bh)}]
    puts "img2mem: $bmpfile -> ${bw}x${hh}, $bpp bpp, uncompressed"

    if {$bw != $w || $hh != $h} {
        puts "img2mem: ERROR - size mismatch: the file is ${bw}x${hh}, but the design expects ${w}x${h}."
        puts "         In Paint: Resize -> Pixels -> ${w} x ${h}, then save as 24-bit BMP."
        puts "         (Or change IMG_W/IMG_H/ADDR_W in tb/tb_image_top.v to match your picture.)"
        return 0
    }

    set stride [expr {((3 * $bw + 3) / 4) * 4}]
    set pixdata [string range $data $off end]
    binary scan $pixdata c* bytes
    if {[llength $bytes] < $stride * $hh} {
        puts "img2mem: ERROR - file is truncated (need [expr {$stride * $hh}] bytes of pixels, got [llength $bytes])"
        return 0
    }

    set lines {}
    for {set y 0} {$y < $hh} {incr y} {
        set ry [expr {$bottom_up ? ($hh - 1 - $y) : $y}]
        set base [expr {$ry * $stride}]
        for {set x 0} {$x < $bw} {incr x} {
            set p [expr {$base + $x * 3}]
            set b [expr {[lindex $bytes $p] & 0xFF}]
            set g [expr {[lindex $bytes [expr {$p + 1}]] & 0xFF}]
            set r [expr {[lindex $bytes [expr {$p + 2}]] & 0xFF}]
            lappend lines [format "%02X%02X%02X" $r $g $b]
        }
    }

    set fh [open $memfile w]
    fconfigure $fh -translation lf
    puts $fh [join $lines "\n"]
    close $fh

    puts "img2mem: wrote $memfile with [llength $lines] pixels (= [expr {$w * $h}])"
    puts "img2mem: next:  set_src mem   then Run Simulation (look for the \[TB\]\[REF\] verdict)"
    return 1
}

puts "img2mem.tcl loaded. Usage:  img2mem <bmpfile> <W> <H> <memfile>"
puts "   example:  img2mem data/in/myphoto.bmp 128 128 data/image.mem"
