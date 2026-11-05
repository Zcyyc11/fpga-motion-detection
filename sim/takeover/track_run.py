"""Retained xsim snapshots and hashes for track/alarm directed regressions."""
from pathlib import Path
import argparse, datetime, hashlib, json, shutil, subprocess
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser()
p.add_argument('--label',required=True)
p.add_argument('--tb',default='sim/takeover/track_resource_tb.sv')
p.add_argument('--top',default='track_resource_tb')
a=p.parse_args()
run=Path('<ABS>/fpga_takeover_20261017')/('track_'+a.label+'_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
run.mkdir()
sources=['src/rtl/track.v','src/rtl/alarm.v',a.tb]
manifest={}
for s in sources:
    dest=run/Path(s).name
    shutil.copy2(ROOT/s,dest)
    manifest[s]=hashlib.sha256(dest.read_bytes()).hexdigest()
(run/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
commands=['@echo off','call "<VIVADO_2025_2>/2025.2/Vivado/settings64.bat"',
          'call xvlog -sv '+' '.join('"'+Path(s).name+'"' for s in sources),
          'if errorlevel 1 exit /b 1','call xelab '+a.top+' -s snapshot',
          'if errorlevel 1 exit /b 1','call xsim snapshot -runall','exit /b %errorlevel%']
(run/'run.cmd').write_text('\n'.join(commands)+'\n',encoding='ascii')
with (run/'console.log').open('wb') as f:
    result=subprocess.run(['cmd','/d','/c',str(run/'run.cmd')],cwd=run,stdout=f,stderr=subprocess.STDOUT)
print(run)
def decode(raw):
    lines=[]
    for line in raw.splitlines(keepends=True):
        for encoding in ('utf-8','gb18030'):
            try:
                lines.append(line.decode(encoding));break
            except UnicodeDecodeError:
                continue
        else:
            lines.append(line.decode('utf-8',errors='backslashreplace'))
    return ''.join(lines)
text=decode((run/'console.log').read_bytes())
(run/'console_utf8.log').write_text(text,encoding='utf-8')
for line in text.splitlines():
    if any(x in line for x in ['FAIL','DONE','PASS','ERROR','Fatal','Error']):print(line)
passed=result.returncode==0 and not any(x in text for x in ['FAIL','Fatal','ERROR:']) and ('DONE' in text or 'PASS' in text)
(run/'result.json').write_text(json.dumps({'returncode':result.returncode,'passed':passed}),encoding='utf-8')
raise SystemExit(0 if passed else 1)
