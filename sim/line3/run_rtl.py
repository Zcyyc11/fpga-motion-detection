"""Isolated xsim adapter. Copies only RTL/testbench; never edits shared entrypoints."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'src/ps'))
import rtl_golden as golden
from compare import compare, write_csv, read_csv


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--settings', type=Path, required=True)
    ap.add_argument('--out', type=Path, required=True, help='New ASCII scratch directory')
    ap.add_argument('--evidence', type=Path, required=True, help='New evidence directory')
    ap.add_argument('--mode', choices=['framediff','bg'], default='framediff')
    ap.add_argument('--drain-frames', type=int, choices=[0, 1], default=0,
                    help='Add one video frame to finish collecting the original 12 expected frames')
    a = ap.parse_args()
    settings, scratch, evidence = a.settings.resolve(), a.out.resolve(), a.evidence.resolve()
    if not settings.is_file():
        ap.error('settings64.bat missing')
    if any(ord(c)>127 for c in str(scratch)) or any(c in str(scratch)+str(settings) for c in '%!&^\n\r"'):
        ap.error('Use plain ASCII scratch and settings paths without shell metacharacters')
    if scratch.exists() or evidence.exists():
        ap.error('Output directory exists; choose new directories')
    scratch.mkdir(parents=True)
    evidence.mkdir(parents=True)
    (scratch/'wave').mkdir()
    (scratch/'rtl').mkdir()
    copies = {}
    for source in sorted((ROOT/'src/rtl').glob('*.v')) + [ROOT/'sim/tb/tb_md_pipeline.v']:
        target = scratch/'rtl'/source.name
        shutil.copy2(source,target)
        copies[str(source.relative_to(ROOT))] = hashlib.sha256(source.read_bytes()).hexdigest()
    (scratch/'files.f').write_text('\n'.join('rtl/'+p.name for p in sorted((scratch/'rtl').glob('*.v')))+'\n',encoding='ascii')
    mode = '0' if a.mode == 'framediff' else '1'
    batch = '\n'.join(['@echo off', 'setlocal', 'call "'+str(settings)+'"', 'if errorlevel 1 exit /b 1',
                       'call xvlog.bat -sv -f files.f','if errorlevel 1 exit /b 2',
                       'call xelab.bat -debug typical -timescale 1ns/1ps tb_md_pipeline -generic_top "MODE_BG='+mode+'" -generic_top "FRAMES='+str(12+a.drain_frames)+'" -s line3_sim',
                       'if errorlevel 1 exit /b 3', 'call xsim.bat line3_sim -runall','exit /b %errorlevel%',''])
    with (scratch/'run.bat').open('w',encoding='ascii',newline='\r\n') as f:
        f.write(batch)
    start = time.perf_counter()
    timed_out = False
    with (scratch/'console.txt').open('wb') as f:
        try:
            proc = subprocess.run(['cmd.exe','/d','/c',str(scratch/'run.bat')],cwd=scratch,stdout=f,
                                  stderr=subprocess.STDOUT,timeout=240)
            exit_code = proc.returncode
        except subprocess.TimeoutExpired:
            # Preserve partial evidence; do not claim that descendant tools finished.
            timed_out, exit_code = True, 124
    raw = (scratch/'console.txt').read_bytes()
    try:
        log = raw.decode('utf-8')
    except UnicodeDecodeError:
        log = raw.decode('gb18030',errors='replace')
    (evidence/'console.txt').write_text(log.replace('\r\n','\n'),encoding='utf-8',newline='\n')
    # Read machine-verifiable ASCII markers as well as the completion banner.
    result = dict(settings=str(settings), scratch=str(scratch), mode=a.mode, exit_code=exit_code,
                  timed_out=timed_out, drain_frames=a.drain_frames, expected_frames=12,
                  seconds=round(time.perf_counter()-start,3), source_sha256=copies,
                  simulation_done='仿真结束' in log, x_hits_zero='x_hits=0' in log,
                  files={})
    result['errors'] = [line for line in log.splitlines() if any(s in line for s in ('ERROR:','FATAL:','TIMEOUT','engine failed'))]
    (evidence/'wave').mkdir()
    for file in (scratch/'wave').glob('*'):
        if file.suffix == '.csv':
            shutil.copy2(file,evidence/file.name)
        if file.suffix == '.ppm':
            shutil.copy2(file,evidence/'wave'/file.name)
        result['files'][file.name] = hashlib.sha256(file.read_bytes()).hexdigest()
    _, rows = golden.run(mode=a.mode)
    fields=['frame','b_valid','b_x1','b_y1','b_x2','b_y2','b_cnt']
    write_csv(evidence/'expected.csv', fields,[dict(zip(fields,r)) for r in rows])
    if (evidence/'bbox_rtl.csv').exists():
        result['strict_full_diff'] = compare(evidence/'expected.csv',evidence/'bbox_rtl.csv')
        result['csv_rows'] = len(read_csv(evidence/'bbox_rtl.csv')[1])
    else:
        result['strict_full_diff'] = [{'kind':'missing_csv'}]
        result['csv_rows'] = 0
    result['pass'] = all([exit_code==0,not timed_out,result['simulation_done'],result['x_hits_zero'],
                          not result['errors'],not result['strict_full_diff']])
    (evidence/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    shutil.copy2(scratch/'run.bat', evidence/'invocation.bat')
    print(json.dumps(result,ensure_ascii=False,indent=2))
    return 0 if result['pass'] else 2


if __name__=='__main__':
    raise SystemExit(main())
