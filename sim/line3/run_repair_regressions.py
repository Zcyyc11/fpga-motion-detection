"""Freeze a Git revision and retain a full repair regression outside the checkout."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[2]

# The legacy guard tests remove generated fixtures to simulate missing inputs.
# Preserve them by renaming, restricted to this isolated run. Test semantics stay missing.
PRESERVE_WORKER=r'''
import json, os, runpy, shutil, sys
from pathlib import Path
root=Path(sys.argv[1]).resolve()
saved=root/'retained_removed_fixtures'
saved.mkdir()
records=[]
def retain(path,*args,**kwargs):
    source=Path(path).resolve()
    if not source.is_relative_to(root) or source==root or source.is_relative_to(saved):
        raise RuntimeError('Refusing out-of-run move: '+str(source))
    if not source.exists():
        if kwargs.get('ignore_errors'): return
        raise FileNotFoundError(source)
    dest=saved/(str(len(records))+'_'+source.name)
    source.rename(dest)
    records.append(dict(source=str(source),retained=str(dest)))
    (saved/'manifest.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
os.remove=retain
os.unlink=retain
shutil.rmtree=retain
script=sys.argv[2]
sys.argv=sys.argv[2:]
runpy.run_path(script,run_name='__main__')
'''


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out',type=Path,required=True,help='New ASCII directory outside repository')
    ap.add_argument('--settings',type=Path,required=True)
    a=ap.parse_args()
    out=a.out.resolve()
    if out.is_relative_to(ROOT) or not str(out).isascii():
        ap.error('Output must be outside source, with ASCII path')
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    if subprocess.check_output(['git','diff','HEAD','--','src','sim','build/scripts','docs'],cwd=ROOT):
        ap.error('Commit source, tests and documentation before freezing revision')
    out.mkdir(parents=True,exist_ok=False)
    clone=out/'checkout'
    subprocess.run(['git','clone','--shared','--no-checkout',str(ROOT),str(clone)],check=True)
    subprocess.run(['git','checkout','--detach',revision],cwd=clone,check=True)
    env=dict(os.environ,PYTHONUTF8='1',PYTHONIOENCODING='utf-8',PYTHONDONTWRITEBYTECODE='1',
             MOTION_PYTHON=sys.executable)
    jobs=[
        ('boundaries',['build/scripts/test_verification_boundaries.py','--out',out/'boundaries']),
        ('runner',['build/scripts/test_sim_runner.py','--out',out/'runner']),
        ('tools',['sim/line3/check_tools.py','--out',out/'tools']),
        ('repairs',['sim/line3/check_repairs.py','--out',out/'repairs']),
        ('docs',['build/scripts/check_doc_commands.py']),
        ('docs_self',['build/scripts/check_doc_commands.py','--self-test']),
        ('rtl_default',['build/scripts/run_sim.py','--vivado-settings',a.settings,
                        '--scratch-root',out/'rtl_default','--expect-frames','12']),
        ('rtl_fd',['sim/line3/run_rtl.py','--settings',a.settings,'--out',out/'fd_scratch','--evidence',out/'rtl_fd']),
        ('rtl_bg',['sim/line3/run_rtl.py','--settings',a.settings,'--mode','bg','--out',out/'bg_scratch','--evidence',out/'rtl_bg']),
        ('rtl_compat',['sim/line3/run_rtl.py','--settings',a.settings,'--drain-frames','1','--out',out/'compat_scratch','--evidence',out/'rtl_compat']),
        ('contracts',['sim/line3/check_rtl_contracts.py','--settings',a.settings,'--out',out/'contracts']),
    ]
    worker=out/'preserve_worker.py'
    worker.write_text(PRESERVE_WORKER,encoding='utf-8')
    # Last: its original CSVs are restored, while removed fixtures are retained above.
    jobs.append(('data_guard',[worker,out,clone/'build/scripts/test_data_guard.py',
                               '--tmpdir',out/'data_guard','--keep']))
    results=[]
    for name,args in jobs:
        command=[sys.executable,'-X','utf8',*map(str,args)]
        start=time.monotonic()
        with (out/(name+'.txt')).open('wb') as stream:
            proc=subprocess.run(command,cwd=clone,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=1800)
        results.append(dict(name=name,argv=command,cwd=str(clone),exit_code=proc.returncode,
                            seconds=round(time.monotonic()-start,3)))
        (out/'jobs.json').write_text(json.dumps(dict(revision=revision,jobs=results),indent=2),encoding='utf-8')
        print(name,'exit='+str(proc.returncode),flush=True)
    status=subprocess.check_output(['git','status','--porcelain'],cwd=clone,text=True)
    (out/'checkout_status.txt').write_text(status,encoding='utf-8')
    return 0 if all(r['exit_code']==0 for r in results) and not status else 2


if __name__=='__main__':
    raise SystemExit(main())
