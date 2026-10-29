"""Read the routed checkpoint and preserve constraint coverage reports."""
import pathlib,sys,shutil
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from task_tools import *
for mode in map(int,sys.argv[1:] or (0,1)):
    d=WORK/f'board_integrated_mode{mode}'
    checkpoint=d/'build/vivado/fpga_motion_detection.runs/impl_1/board_top_routed.dcp'
    if not checkpoint.exists():
        save(f'board_mode{mode}_diagnostics_skipped.json',dict(reason='routed checkpoint absent',path=str(checkpoint)))
        continue
    check=d/'postroute_diagnostics';check.mkdir()
    script='''open_checkpoint {%s}
report_route_status -file route_status.rpt
report_timing_summary -report_unconstrained -check_timing_verbose -file timing_unconstrained.rpt
report_methodology -file methodology.rpt
report_drc -file drc.rpt
report_clocks -file clocks.rpt
report_clock_interaction -file clock_interaction.rpt
check_timing -verbose -file check_timing.rpt
exit
''' % checkpoint.as_posix()
    (check/'check.tcl').write_text(script,encoding='ascii')
    rec,txt=run(f'board_mode{mode}_diagnostics',['<DRIVE>/AMD2025.2/2025.2/Vivado/bin/vivado.bat','-mode','batch','-source','check.tcl','-nojournal','-log','vivado.log'],check,timeout=600)
    target=OUT/f'board_mode{mode}'/'diagnostics';target.mkdir(parents=True)
    for p in check.glob('*.rpt'):shutil.copy2(p,target/p.name)
    print(txt[-1500:])
