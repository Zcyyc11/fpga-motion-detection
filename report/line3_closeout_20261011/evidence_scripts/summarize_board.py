"""Parse completed routed reports; never equate positive WNS with board acceptance."""
import sys,pathlib,re,json
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from task_tools import *
results=[]
for mode in (0,1):
    rec=json.loads((OUT/f'board_mode{mode}_result.json').read_text(encoding='utf-8'))
    d=OUT/f'board_mode{mode}'
    text=(d/'impl_timing_summary.rpt').read_text(encoding='utf-8')
    util=(d/'impl_utilization.rpt').read_text(encoding='utf-8')
    assert rec['command']['exit_code']==0 and rec['bit_exists'] and rec['effective_generic']
    assert 'Design State : Routed' in text
    values=re.search(r'WNS\(ns\).*?\n\s*-+[^\n]*\n\s*([^\n]+)',text,re.S).group(1).split()
    assert len(values)==12,values
    timing=dict(zip(['WNS','TNS','setup_failing','setup_total','WHS','THS','hold_failing','hold_total','WPWS','TPWS','pulse_failing','pulse_total'],values))
    assert all(float(timing[k])>=0 for k in ['WNS','WHS','WPWS'])
    assert all(int(timing[k])==0 for k in ['setup_failing','hold_failing','pulse_failing'])
    resources={}
    for key,label in [('LUT','Slice LUTs'),('FF','Slice Registers'),('BRAM','Block RAM Tile'),('DSP','DSPs')]:
        resources[key]=int(re.search(r'\|\s*'+re.escape(label)+r'\s*\|\s*(\d+)',util).group(1))
    counts={n:int(re.search(r'checking '+n+r' \((\d+)\)',text).group(1)) for n in ['no_clock','unconstrained_internal_endpoints','no_input_delay','no_output_delay']}
    diag=d/'diagnostics'
    route=(diag/'route_status.rpt').read_text(encoding='utf-8')
    routing_errors=int(re.search(r'# of nets with routing errors\.+\s*:\s*(\d+)',route).group(1))
    routable=int(re.search(r'# of routable nets\.+\s*:\s*(\d+)',route).group(1))
    fully_routed=int(re.search(r'# of fully routed nets\.+\s*:\s*(\d+)',route).group(1))
    assert routing_errors==0 and routable==fully_routed
    drc=(diag/'drc.rpt').read_text(encoding='utf-8')
    methodology=(diag/'methodology.rpt').read_text(encoding='utf-8')
    rules=re.findall(r'^\|\s*([A-Z][A-Z0-9-]+)\s*\|\s*(Warning|Critical Warning|Error)\s*\|.*?\|\s*(\d+)\s*\|',drc,re.M)
    method_rules=re.findall(r'^\|\s*([A-Z][A-Z0-9-]+)\s*\|\s*(Warning|Critical Warning|Error)\s*\|.*?\|\s*(\d+)\s*\|',methodology,re.M)
    results.append(dict(mode=mode,source_sha=json.loads((OUT/f'board_mode{mode}_inputs.json').read_text(encoding='utf-8'))['source_sha'],
        timing=timing,resources=resources,constraint_counts=counts,drc_rules=rules,methodology_rules=method_rules,
        routing_errors=routing_errors,routable_nets=routable,fully_routed_nets=fully_routed,
        bit_sha256=rec['bit_sha256'],build_exit_code=0,
        scope='board_top internal pattern + HDMI output; constrained routed paths passed; unconstrained external paths and warnings remain; not board-tested'))
save('board_verified_summary.json',results)
print(json.dumps(results,ensure_ascii=False,indent=2))
