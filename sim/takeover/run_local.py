"""Retained, isolated Vivado test: copies exact inputs and validates a PASS marker."""
import argparse, hashlib, json, re, subprocess, time
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('--top',required=True)
p.add_argument('--out',required=True)
p.add_argument('--files',nargs='+',required=True)
p.add_argument('--settings',default='D:/AMD2025.2/2025.2/Vivado/settings64.bat')
p.add_argument('--generic',action='append',default=[])
a=p.parse_args()
if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',a.top):raise ValueError('invalid top')
out=Path(a.out).resolve();out.mkdir(parents=True,exist_ok=False)
manifest={};files=[]
for i,name in enumerate(a.files):
 src=Path(name).resolve();dst=out/(str(i)+'_'+src.name)
 dst.write_bytes(src.read_bytes());files.append(dst)
 manifest[str(src)]=hashlib.sha256(dst.read_bytes()).hexdigest()
(out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
(out/'files.f').write_text('\n'.join('"'+f.name+'"' for f in files),encoding='utf-8')
(out/'finish.tcl').write_text('run all\nquit\n',encoding='ascii')
for v in [str(out),a.settings,*a.generic]:
 if any(c in v for c in '%!^&|<>"\n\r'):raise ValueError('unsafe command')
generics=''.join(' -generic_top "'+g+'"' for g in a.generic)
(out/'run.bat').write_text('@echo off\ncall "'+a.settings+'"\nif errorlevel 1 exit /b 10\ncall xvlog.bat --relax -sv -f files.f\nif errorlevel 1 exit /b 11\ncall xelab.bat '+a.top+generics+' -s check\nif errorlevel 1 exit /b 12\ncall xsim.bat check -tclbatch finish.tcl\nexit /b %errorlevel%\n',encoding='ascii',newline='\r\n')
start=time.time()
with (out/'console.raw').open('xb') as log:
 proc=subprocess.Popen(['cmd.exe','/d','/c',str(out/'run.bat')],cwd=out,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
 (out/'process.json').write_text(json.dumps(dict(pid=proc.pid,status='running')),encoding='utf-8')
 rc=proc.wait()
text=(out/'console.raw').read_bytes().decode('utf-8',errors='replace')
fail=[l for l in text.splitlines() if re.search(r'\b(FAIL|FATAL|ERROR)\b',l)]
result=dict(passed=rc==0 and not fail and 'TAKEOVER_PASS' in text,returncode=rc,failures=fail,seconds=round(time.time()-start,2),board_test=False)
(out/'process.json').write_text(json.dumps(dict(pid=proc.pid,status='finished',**result),indent=2),encoding='utf-8')
(out/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result),flush=True)
raise SystemExit(0 if result['passed'] else 1)
