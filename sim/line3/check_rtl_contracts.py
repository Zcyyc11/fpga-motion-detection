"""Run directed real RTL tests and retained source mutations in isolated copies."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'src/ps'))
import rtl_golden as golden
import numpy as np


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--settings',type=Path,required=True)
    ap.add_argument('--out',type=Path,required=True)
    a=ap.parse_args()
    out=a.out.resolve()
    settings=a.settings.resolve()
    if not settings.is_file() or not str(out).isascii() or any(c in str(out)+str(settings) for c in '%!&^\n\r"'):
        ap.error('Use existing settings and safe ASCII output path')
    out.mkdir(parents=True,exist_ok=False)
    mutations={
        'correct':None,
        'threshold_69':('threshold.v','parameter integer THRESH = 70','parameter integer THRESH = 69'),
        'wrap_early':('pattern_gen.v','(obj_x + DX16) > X_MAX16','(obj_x + DX16) >= X_MAX16'),
        'no_wrap':('pattern_gen.v','(obj_x + DX16) > X_MAX16',"1'b0"),
        'morph_shift':('morph3x3.v',"out_x     <= in_x - 16'd1;","out_x     <= in_x;"),
        'old_morph':('morph3x3.v',None,None),
    }
    results=[]
    for name, mutation in mutations.items():
        dest=out/name
        dest.mkdir()
        sources=[ROOT/'src/rtl'/n for n in ('threshold.v','morph_open.v','morph3x3.v','pattern_gen.v')]
        sources+=[ROOT/'sim/tb/tb_contracts.v']
        original={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
        for p in sources: shutil.copy2(p,dest/p.name)
        if mutation:
            filename,old,new=mutation
            p=dest/filename
            if name=='old_morph':
                p.write_bytes(subprocess.check_output(['git','show',
                    '08b944790b629546a584ade37e77818535f72c57:src/rtl/morph3x3.v'],cwd=ROOT))
            else:
                s=p.read_text(encoding='utf-8')
                assert s.count(old)==1,(name,s.count(old))
                p.write_text(s.replace(old,new),encoding='utf-8')
        batch='\n'.join(['@echo off','setlocal','call "'+str(settings)+'"','if errorlevel 1 exit /b 1',
            'call xvlog.bat -sv '+' '.join(p.name for p in sources),'if errorlevel 1 exit /b 2',
            'call xelab.bat tb_contracts -s contracts','if errorlevel 1 exit /b 3',
            'call xsim.bat contracts -runall','exit /b %errorlevel%',''])
        (dest/'run.bat').write_text(batch,encoding='ascii',newline='\r\n')
        with (dest/'console.raw').open('wb') as stream:
            proc=subprocess.run(['cmd.exe','/d','/c',str(dest/'run.bat')],cwd=dest,
                                stdout=stream,stderr=subprocess.STDOUT,timeout=180)
        raw=(dest/'console.raw').read_bytes()
        try: log=raw.decode('utf-8')
        except UnicodeDecodeError: log=raw.decode('gb18030',errors='replace')
        (dest/'console.txt').write_text(log.replace('\r\n','\n'),encoding='utf-8',newline='\n')
        done='CONTRACTS_DONE threshold=6 pattern=384' in log
        fatal='Fatal:' in log or 'FATAL:' in log
        result=dict(case=name,exit_code=proc.returncode,done=done,fatal=fatal,mutation=mutation,
                    original_sha256=original,
                    tested_sha256={p.name:hashlib.sha256((dest/p.name).read_bytes()).hexdigest() for p in sources})
        if name=='correct' and done:
            rows=list(csv.DictReader((dest/'morph.csv').open(encoding='utf-8')))
            comparisons=[]
            for f in range(7):
                frame_rows=[r for r in rows if int(r['frame'])==f]
                actual=np.zeros((10,10),bool)
                keys=[(int(r['x']),int(r['y'])) for r in frame_rows]
                for r in frame_rows: actual[int(r['y']),int(r['x'])]=bool(int(r['mask']))
                stimulus=np.zeros((10,10),bool)
                # Independent geometric answer: a width-4 rectangle survives opening.
                answer=np.zeros((10,10),bool)
                if f in (0,2): stimulus[:]=True; answer[1:8,1:8]=True
                if f==3: stimulus[:,:4]=True; answer[1:8,1:4]=True
                if f==4: stimulus[:,6:]=True; answer[1:8,6:8]=True
                if f==5: stimulus[:4,:]=True; answer[1:4,1:8]=True
                if f==6: stimulus[6:,:]=True; answer[6:8,1:8]=True
                reference=golden.open3(stimulus)
                comparisons.append(dict(frame=f,unique=len(set(keys))==len(keys),
                    rows=len(frame_rows),actual_pixels=int(actual.sum()),model_pixels=int(reference.sum()),
                    differences=np.argwhere(actual!=reference).tolist(),
                    independent_differences=np.argwhere(actual!=answer).tolist(),
                    full_coordinate_domain=set(keys)=={(x,y) for x in range(1,8) for y in range(1,8)}))
            result['morph_comparison']=comparisons
            # Old one-cell boundary crop is an explicit model mutant, tested against literals.
            full=np.ones((10,10),bool)
            eroded=golden._win(full,'and')
            wrong=golden._win(eroded,'or')
            wrong[0,:]=wrong[-1,:]=False
            wrong[:,0]=wrong[:,-1]=False
            fixed=golden.open3(full)
            result['old_boundary_model_mutant_detected']=int(wrong.sum())==64 and int(fixed.sum())==49
            result['pass']=proc.returncode==0 and not fatal and result['old_boundary_model_mutant_detected'] and all(
                r['unique'] and r['full_coordinate_domain'] and not r['differences'] and not r['independent_differences'] for r in comparisons)
        else:
            # A compile failure is NOT a successful fault detection.
            marker=('THRESHOLD value=70' if name=='threshold_69' else
                    'MORPH ' if name in ('morph_shift','old_morph') else 'PATTERN frame=')
            result['pass']=name!='correct' and fatal and marker in log and not done
        results.append(result)
        (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
        print(name,result['pass'],flush=True)
    return 0 if all(r['pass'] for r in results) else 2


if __name__=='__main__':
    raise SystemExit(main())
