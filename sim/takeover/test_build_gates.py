"""Exercise the actual Tcl bit-stage control flow with mocked Vivado results."""
import argparse
from pathlib import Path
import tkinter

p = argparse.ArgumentParser()
p.add_argument('--script', default='build/scripts/build_vivado.tcl')
a = p.parse_args()
source = Path(a.script).read_text(encoding='utf-8')
body = source[source.index('proc stage_bit {} {'):source.index('# ---------------------------------------------------------------- 调度')]
for setup, hold, drc, allowed in [('1.0','0.1','',True),('-0.1','0.1','',False),
                                ('1.0','-0.1','',False),('','0.1','',False),
                                ('1.0','0.1','UCIO-1',False)]:
    t = tkinter.Tcl()
    t.eval('''
        set XPR dummy; set PROJ_DIR dummy; set TOP board_top
        set BUILD_DIR dummy; set REPORT_DIR dummy; set wrote 0
        foreach name {open_project open_run report_utilization report_timing_summary
                      report_clock_interaction report_drc close_design close_project puts} {
            proc $name {args} {}
        }
        rename file real_file
        proc file {op args} {
            if {$op eq "exists"} { return [expr {[string match *runs* $args]}] }
            if {$op eq "mkdir"} { return }
            if {$op eq "copy"} { set ::wrote 1; return }
            return [real_file $op {*}$args]
        }
        proc get_timing_paths {args} {
            if {[lsearch $args -setup]>=0} {return setup}; return hold
        }
        proc get_property {prop path} {return [set ::$path]}
        proc get_drc_violations {args} {return $::drc}
        proc write_bitstream {args} {set ::wrote 1}
    ''')
    for k, v in [('setup',setup),('hold',hold),('drc',drc)]:
        t.setvar(k,v)
    t.eval(body)
    error = bool(int(t.eval('catch {stage_bit} detail')))
    wrote = bool(int(t.getvar('wrote')))
    assert (not error) == allowed and wrote == allowed, (setup,hold,drc,error,wrote)
print('PASS build gates: setup/hold/missing timing/DRC block bit delivery')
