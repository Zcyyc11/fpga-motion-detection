"""Run the r1 pipeline and combined interface checks in separate xsim workdirs."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,sys,time
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description='Run pipeline, bridge, and digital HDMI simulations')
parser.add_argument('label',help='New result directory name under evidence')
args=parser.parse_args()
configured=os.environ.get('VIVADO_BIN')
found=shutil.which('xvlog.bat')
if not configured and not found:
    parser.error('Set VIVADO_BIN to the Vivado bin directory or add it to PATH')
vivado=Path(configured).resolve() if configured else Path(found).resolve().parent
for tool in ('xvlog','xelab','xsim'):
    if not (vivado/(tool+'.bat')).is_file():
        parser.error(f'{tool}.bat was not found in {vivado}')
out=root/'evidence'/args.label
out.mkdir(parents=True,exist_ok=False)
rtl=sorted((root/'src/rtl').glob('*.v'))
cases=[('pipeline','tb_pipeline_r1','PIPELINE_R1_PASS',rtl+[root/'sim/tb_md_pipeline.v',root/'sim/tb_pipeline_r1.sv']),
       ('bridge','tb_combined_bridge','COMBINED_BRIDGE_PASS',rtl+[root/'src/rtl/board/combined_top.v',root/'src/rtl/board/gray_conv.v',root/'src/rtl/board/hdmi_in_ctrl.v',root/'sim/hdmi_boundary_stubs.sv',root/'sim/tb_combined_bridge.sv'])]
cases.append(('hdmi','tb_hdmi_restore','HDMI_RESTORE_PASS',rtl+[root/'src/rtl/board/combined_top.v',root/'src/rtl/board/gray_conv.v',root/'src/rtl/board/hdmi_in_ctrl.v',root/'sim/hdmi_boundary_stubs.sv',root/'sim/tb_hdmi_restore.sv']))
results={'board_verified':False,'tests':[]}
for name,top,marker,sources in cases:
    dest=out/name;dest.mkdir();(dest/'wave').mkdir()
    item={'name':name,'sources':{str(s.relative_to(root)):hashlib.sha256(s.read_bytes()).hexdigest() for s in sources},'commands':[],'passed':False}
    for tool,args in [('xvlog',['-sv',*sources]),('xelab',[top,'-s',top+'_sim']),('xsim',[top+'_sim','-runall'])]:
        cmd=[str(vivado/(tool+'.bat')),*map(str,args)]
        run=subprocess.run(cmd,cwd=dest,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        (dest/(tool+'.log')).write_bytes(run.stdout)
        item['commands'].append({'argv':cmd,'returncode':run.returncode})
        if run.returncode:break
        if tool=='xsim': item['passed']=marker in run.stdout.decode('utf-8',errors='replace') and b'Fatal:' not in run.stdout
    results['tests'].append(item)
    print(name,item['passed'],flush=True)
results['passed']=all(x['passed'] for x in results['tests'])
(out/'result.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
sys.exit(0 if results['passed'] else 1)
