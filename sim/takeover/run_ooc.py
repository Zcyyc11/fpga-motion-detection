"""OOC synthesis with frozen copied sources; no board or full-chip claim."""
import argparse,hashlib,json,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--top',required=True);p.add_argument('--out',required=True);p.add_argument('--files',nargs='+',required=True);p.add_argument('--period',default='13.468');a=p.parse_args()
out=Path(a.out).resolve();out.mkdir(parents=True,exist_ok=False)
manifest={};sources=[]
for i,f in enumerate(a.files):
 src=Path(f).resolve();dst=out/(str(i)+'_'+src.name);dst.write_bytes(src.read_bytes());sources.append(dst)
 manifest[str(src)]=hashlib.sha256(dst.read_bytes()).hexdigest()
(out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
script='set_param general.maxThreads 4\n'
script+='read_verilog {'+' '.join(str(s).replace('\\','/') for s in sources)+'}\n'
script+=f'synth_design -top {a.top} -part xc7z020clg400-1 -mode out_of_context\n'
script+=f'create_clock -name clk -period {float(a.period)} [get_ports clk]\n'
script+='report_utilization -file utilization.rpt\nreport_utilization -hierarchical -file hierarchy.rpt\nreport_timing_summary -file timing.rpt\nwrite_checkpoint post_synth.dcp\nputs OOC_DONE\nexit\n'
(out/'run.tcl').write_text(script,encoding='utf-8')
(out/'run.bat').write_text('@echo off\ncall D:/AMD2025.2/2025.2/Vivado/settings64.bat\ncall vivado.bat -mode batch -source run.tcl -log vivado.log -journal vivado.jou\nexit /b %errorlevel%\n',encoding='ascii',newline='\r\n')
with (out/'console.raw').open('xb') as log:
 proc=subprocess.Popen(['cmd.exe','/d','/c',str(out/'run.bat')],cwd=out,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
 (out/'process.json').write_text(json.dumps(dict(pid=proc.pid,status='running')),encoding='utf-8');rc=proc.wait()
text=(out/'console.raw').read_bytes().decode('utf-8',errors='replace')
result=dict(pid=proc.pid,status='finished',returncode=rc,synthesis_completed=rc==0 and 'OOC_DONE' in text,board_test=False)
(out/'process.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result),flush=True)
raise SystemExit(0 if result['synthesis_completed'] else 1)
