"""Frozen-ref, isolated xsim checks. No RTL writes; retain failures and byte hashes."""
import argparse
from collections import deque
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

p=argparse.ArgumentParser()
p.add_argument('--repo',required=True);p.add_argument('--ref',default='HEAD')
p.add_argument('--out',required=True);p.add_argument('--jobs',default='all')
p.add_argument('--settings',default='D:/AMD2025.2/2025.2/Vivado/settings64.bat')
a=p.parse_args();repo=Path(a.repo).resolve();out=Path(a.out).resolve();here=Path(__file__).resolve().parent
out.mkdir(parents=True,exist_ok=False)
def git(*args):return subprocess.check_output(['git','-C',str(repo),*args])
def save(path,obj):path.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
sha=git('rev-parse',a.ref).decode().strip()
names=git('ls-tree','-r','--name-only',sha).decode().splitlines()
sources={}
for name in names:
 if (name.startswith('src/rtl/') and name.endswith('.v')) or name in ['sim/tb/tb_multi_bbox.v','sim/tb/tb_track_alarm.v','sim/tb/tb_axi_lite_slave.v','sim/tb/tb_regs.v']:
  dest=out/'source'/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(git('show',sha+':'+name));sources[name]=hashlib.sha256(dest.read_bytes()).hexdigest()
for src in here.glob('tb_*.v'):
 if '_before_' in src.name:continue
 dest=out/'source/sim/line3/verify_cleanup'/src.name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(src.read_bytes());sources[str(dest.relative_to(out/'source'))]=hashlib.sha256(dest.read_bytes()).hexdigest()
save(out/'source_manifest.json',dict(ref=a.ref,commit=sha,files=sources,created_utc=datetime.now(timezone.utc).isoformat()))

def components(mask):
 left=set(mask);boxes=[]
 while left:
  start=min(left);left.remove(start);q=deque([start]);points=[start]
  while q:
   x,y=q.popleft()
   for pt in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
    if pt in left:left.remove(pt);q.append(pt);points.append(pt)
  xs,ys=zip(*points);boxes.append([min(xs),min(ys),max(xs),max(ys),len(points)])
 return sorted(boxes)

def mask_for(name):
 if name=='full16_64':return {(2+4*i+dx,2+dy) for i in range(16) for dx in range(2) for dy in range(32)}
 if name in ('full16','overflow','label_full'):
  n={'full16':16,'overflow':5,'label_full':17}[name]
  return {(2+4*i+dx,2+dy) for i in range(n) for dx in range(2) for dy in range(2)}
 if name=='bridge':return {(x,2) for x in (2,3,6,7)}|{(x,3) for x in range(2,8)}
 if name=='reuse':return {(x,2) for x in (2,3,6,7)}|{(x,3) for x in range(2,8)}|{(x,4) for x in (2,3,6,7,12,13)}|{(x,5) for x in (2,3,6,7,12,13)}
 raise ValueError(name)

jobs={n:('tb_multi_bbox_limits',['multi_bbox.v'],['RUN_LIMIT=4'] if n=='overflow' else []) for n in ['full16','overflow','label_full','bridge','reuse']}
jobs['full16_64']=('tb_multi_bbox_limits',['multi_bbox.v'],['MINIMUM=64'])
jobs.update(wrap=('tb_track_id_wrap',['track.v','alarm.v'],[]),cfg=('tb_cfg_enable_verify',None,[]),
 axi_channels=('tb_axi_channels_verify',['board/axi_lite_slave.v'],[]),
 axi_original=('tb_axi_lite_slave',['board/axi_lite_slave.v'],[]),
 track_original=('tb_track_alarm',['track.v','alarm.v'],[]),regs_original=('tb_regs',['regs.v'],[]),
 bbox_original=('tb_multi_bbox',['multi_bbox.v'],[]))
selected=list(jobs) if a.jobs=='all' else a.jobs.split(',')
results=[]
for name in selected:
 top,rtl,generics=jobs[name];d=out/name;d.mkdir()
 if name in ['full16','full16_64','overflow','label_full','bridge','reuse']:
  mask=mask_for(name);gold=components(mask)
  (d/'pixels.txt').write_text(''.join(f'{x} {y} {int((x,y) in mask)}\n' for y in range(max(y for x,y in mask)+3) for x in range(76)),encoding='ascii')
  save(d/'expected_components.json',gold)
 rtl_files=[out/'source/src/rtl'/s for s in rtl] if rtl else sorted((out/'source/src/rtl').glob('*.v'))
 tb=out/'source/sim/line3/verify_cleanup'/f'{top}.v'
 if not tb.exists():tb=out/'source/sim/tb'/f'{top}.v'
 (d/'files.f').write_text('\n'.join('"'+f.as_posix()+'"' for f in rtl_files+[tb])+'\n',encoding='utf-8')
 (d/'finish.tcl').write_text(('run 110 ms\n' if name=='wrap' else 'run 20 ms\n')+'quit\n',encoding='ascii')
 generic=''.join(' -generic_top "'+g+'"' for g in generics)
 # All command paths are locally configured; reject cmd metacharacters.
 for path in [str(d),a.settings]:
  if any(c in path for c in '%!^&|<>"\n\r'):raise ValueError('unsafe command path')
 (d/'run.bat').write_text('@echo off\ncall "'+a.settings+'"\nif errorlevel 1 exit /b 10\ncall xvlog.bat --relax -sv -f files.f\nif errorlevel 1 exit /b 11\ncall xelab.bat '+top+generic+' -s check\nif errorlevel 1 exit /b 12\ncall xsim.bat check -tclbatch finish.tcl\nexit /b %errorlevel%\n',encoding='ascii',newline='\r\n')
 start=time.monotonic()
 with (d/'console.raw').open('xb') as log:
  proc=subprocess.Popen(['cmd.exe','/d','/c',str(d/'run.bat')],cwd=d,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
  save(d/'process.json',dict(pid=proc.pid,status='running',top=top));rc=proc.wait()
 save(d/'process.json',dict(pid=proc.pid,status='finished',returncode=rc,seconds=round(time.monotonic()-start,2)))
 lines=[]
 for b in (d/'console.raw').read_bytes().splitlines():
  try:lines.append(b.decode('utf-8'))
  except UnicodeDecodeError:lines.append(b.decode('gb18030',errors='backslashreplace'))
 text='\n'.join(lines);(d/'console.txt').write_text(text,encoding='utf-8')
 failures=[s for s in lines if re.search(r'\b(FAIL|ERROR|FATAL)\b',s)]
 done=('VERIFY_DONE' in text) if not name.endswith('_original') else bool(re.search(r'(?:===.*PASS|RESULT: PASS)',text))
 if not done:failures.append('missing completion marker')
 if name in ['full16','full16_64','overflow','label_full','bridge','reuse']:
  rows=[list(map(int,m)) for m in re.findall(r'^BOX (\d+) (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)$',text,re.M)]
  observed=sorted(r[1:6] for r in rows);save(d/'observed_boxes.json',rows)
  if rows and ([r[0] for r in rows]!=list(range(len(rows))) or [r[-1] for r in rows]!=[0]*(len(rows)-1)+[1]):failures.append('id sequence or last marker')
  if name=='label_full':
   if len(observed)!=16 or len(set(map(tuple,observed)))!=16 or any(b not in gold for b in observed):failures.append('label saturation corrupts or duplicates retained components')
  elif name=='overflow':
   # Reduced MAX_RUN deliberately degrades the fifth component: characterize
   # it while requiring the four retained runs and no fabricated pixels.
   retained=gold[:4]
   extras=[b for b in observed if b not in retained]
   if len(set(map(tuple,observed)))!=len(observed) or any(b not in observed for b in retained) or any(b not in [[18,2,19,2,2],[18,3,19,3,2],gold[4]] for b in extras) or sum(b[4] for b in observed)>len(mask):failures.append('run overflow corrupts retained components')
  elif observed!=gold:failures.append('component oracle mismatch')
 result=dict(job=name,commit=sha,passed=(rc==0 and not failures),returncode=rc,failures=failures,board_test=False)
 save(d/'result.json',result);results.append(result);print(json.dumps(result,ensure_ascii=False),flush=True)
save(out/'summary.json',results)
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
