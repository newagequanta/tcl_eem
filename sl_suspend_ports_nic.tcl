puts [open "flash:TCL_Scripts/remove_potential_suspend_ports.tcl" w+] {
::cisco::eem::event_register_syslog pattern "LINEPROTO-5-UPDOWN" maxrun 600
#-
# Copyright (c) 2009 Joe Marcus Clarke <jclarke@cisco.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
#
# This policy listens for link up syslog messages, and removes the port from
# the list of down ports.
#
# This policy uses the following environment variables:
#
# suspend_ports_config      : Path to configuration file.
#

if { ![info exists suspend_ports_config] } {
    set result "ERROR: Policy cannot be run: variable suspend_ports_config has not been set"
    error $result $errorInfo
}

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

array set arr_einfo [event_reqinfo]
puts "output of array"; #TEST
puts [array get arr_einfo]; #TEST
#E.g. array(msg) = {*Nov 13 08:13:46.020: %LINEPROTO-5-UPDOWN: Line protocol on Interface GigabitEthernet0/1, changed state to up}
if { ! [regexp {Interface ([^,]+), changed state to up} $arr_einfo(msg) -> iface] } {
    exit
}

#replace longform interface names to shortform to match storage on suspend_ports_config
regsub {GigabitEthernet} $iface "Gi" iface
regsub {TenGigabitEthernet} $iface "Te" iface
regsub {FastEthernet} $iface "Fa" iface


while { 1 } {
    set results [run_cli [list "show event manager policy pending | include tm_suspend_ports.tcl"]]
    if { ! [regexp {tm_suspend_ports.tcl} $results] } {
	break
    }
    after 1000
}

if { [catch {open $suspend_ports_config "r"} result] } {
    exit
}

set fd $result
set contents [read $fd]
close $fd

set contents [string trim $contents]
array set ports [split $contents]

if { [info exists ports($iface)] } {
    array unset ports $iface

    set fd [open $suspend_ports_config "w"]
    puts -nonewline $fd [array get ports]
    close $fd
}
}
