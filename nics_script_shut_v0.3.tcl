puts [open "flash:TCL_Scripts/cli_open_demo.tcl" w+] {
::cisco::eem::event_register_none
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

proc run_cli { clist } {
    set rbuf ""

    if {[llength $clist] < 1} {
        return -code ok $rbuf
    }

    if {[catch {cli_open} result]} {
        return -code error $result
    } else {
        array set cliarr $result
    }

    if {[catch {cli_exec $cliarr(fd) "enable"} result]} {
        return -code error $result
    }

    foreach cmd $clist {
        if {[catch {cli_exec $cliarr(fd) $cmd} result]} {
            return -code error $result
        }

        append rbuf $result
    }

    if {[catch {cli_close $cliarr(fd) $cliarr(tty_id)} result]} {
        puts "WARNING: $result"
    }

    return -code ok $rbuf
}

#setting variables for calcuations later
set SECS_IN_DAYS 86400
set DOWN 0
set UP 1
set ADMIN_DOWN 2
set DO_NOT_TOUCH 3

#linux epoch in seconds
set now [clock seconds]
set susp_time [expr $suspend_ports_days * $SECS_IN_DAYS]

#create empty array to be populated later with ports to be suspended
array set suspend_ports [list]

if { [catch {open $suspend_ports_config "r"} result] } {
    #if file does not exist, create an empty array
    array set ports [list]
} else {
    #set the file descriptor to the file in $result
    #set contents the the contents of the file $fd points to
    set fd $result
    set contents [read $fd]
    close $fd

    #string trim delets begining spaces
    #it seems the ports should be in a single line seperated by spaces
    set contents [string trim $contents]
    #this should put each port into an array element
    array set ports [split $contents]
}

set result [run_cli [list "show interface descrip | in Gi|Fa|Te"]]
set fo [open "flash:TCL_Scripts/sample_out.txt" "w"] 
foreach line [split $result "\n"] {
    puts "in Loop"; #TEST
    set line [string trim $line]
    regsub -all {\s+} $line " " line
    set elems [split $line]
    puts [llength $elems]; #TEST
    set iface [lindex $elems 0]
    if { ! [regexp {Gi} $iface] } {
    continue
    }
    
    if { [lindex $elems 1] == "admin" && [lindex $elems 2] == "down" } {
        set status $ADMIN_DOWN
    } elseif { [ llength $elems ] > 3 && [lindex $elems 3] == "DND" } {
        set status $DO_NOT_TOUCH
    } elseif { [lindex $elems 1] == "down" } {
        set status $DOWN 
    } elseif { [lindex $elems 1] == "up" && [lindex $elems 2] == "up" } {
        set status $UP
    } else {
        set status $DOWN
    }
    puts "Interface - $iface Status - $status"; #TEST

    if { [info exists ports($iface)] } {
        if { $status == $UP || $status == $ADMIN_DOWN || $status == $DO_NOT_TOUCH} {
            array unset ports $iface
    } else {
        if { [expr $now - $ports($iface)] >= $susp_time } {
            set suspend_ports($iface) $ports($iface)
            }
        }
    } else {
        if { $status == $DOWN } {
            set ports($iface) $now
        }
      }
    
}

puts [array get ports]; #TEST
puts "Suspend ports [array get suspend_ports]"; #TEST
#open and update the $suspend_ports_config
set fd [open $suspend_ports_config "w"]
puts -nonewline $fd [array get ports]
close $fd

#ios_config wont work when EEM invokes TCL, it is a AAA issue
#use the contruct provided by Joe
set cli_cmd [list "config t"]
foreach interface [array names suspend_ports] {
    set if_line "interface $interface"
    puts $if_line; #TEST
    set cli_cmd [concat $cli_cmd [list "interface $interface" "shut"]]
    action_syslog msg "Shutting down port $interface since it was last used on [clock format $suspend_ports($interface)]"
}

lappend cli_cmd "end" "write mem"
if { [catch {run_cli $cli_cmd} result] } {
    action_syslog priority err msg "Failed to shutdown ports: '$result'"
}
}