"""Runner contract regression with a fake Vivado toolchain; retains every file.

The fake tools exercise the real CLI and generated batch file without requiring
Vivado. They do not validate RTL. Actual Vivado runs are recorded separately.
"""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def hashes(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file() and '.git' not in p.parts}


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


EMITTER = r'''
import os, sys
from pathlib import Path
m = os.environ['SIM_TEST_MODE']
if m == 'no_output':
    sys.exit(0)
frames = list(range(11))
if m == 'duplicate': frames[-1] = 9
if m == 'gap': frames[-1] = 12
if m == 'reverse': frames.reverse()
if m == 'empty_csv': frames = []
if m != 'no_csv':
    Path('wave').mkdir(exist_ok=True)
    rows = ['frame,b_valid,b_x1,b_y1,b_x2,b_y2,b_cnt']
    rows += [f'{f},1,2,3,4,5,6' for f in frames]
    if m == 'csv_x': rows[-1] = '10,1,x,3,4,5,6'
    Path('wave/bbox_rtl.csv').write_text('\n'.join(rows)+'\n', encoding='utf-8')
lines = [f't=123  第 {f} 帧检测: bbox=(2,3)-(4,5)  cnt=6  valid=1' for f in frames]
if m != 'no_done': lines += ['---- 仿真结束：共跑 13 个视频帧 ----']
if m != 'no_x_check': lines += ['---- X 检查：掩码流未出现未知态（x_hits=0）----']
extra = {
    'engine': 'Simulation engine failed to start',
    'engine_caps': 'SIMULATION ENGINE FAILED TO START',
    'bracket_error': '[ERROR] a failure',
    'fatal': 'FATAL: a failure',
    'lower_fatal': 'fatal: a failure',
    'error': 'ERROR: a failure',
    'x_chinese': '!! X 检查：掩码流出现 3 次未知态',
    'x_numeric': 'x_hits=3',
    'timeout': '!! TIMEOUT：仿真未在预期时间内结束',
}.get(m)
if extra: lines += [extra]
if m == 'mixed': sys.stdout.buffer.write('工具目录：中文工程\r\n'.encode('gb18030'))
if m == 'bad_bytes': sys.stdout.buffer.write(b'\xff\n')
sys.stdout.buffer.write(('\n'.join(lines)+'\n').encode('utf-8'))
sys.exit(7 if m == 'nonzero' else 0)
'''


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[2])
    ap.add_argument('--out', type=Path, required=True)
    a = ap.parse_args()
    repo, out = a.repo.resolve(), a.out.resolve()
    if os.name != 'nt':
        ap.error('Windows cmd.exe is required for these batch integration tests')
    if out == repo or repo in out.parents:
        ap.error('--out must be outside the source checkout')
    out.mkdir(parents=True, exist_ok=False)
    source_before = hashes(repo)
    tools = out / 'fake tools'
    tools.mkdir()
    (tools / 'emit.py').write_text(EMITTER, encoding='utf-8')
    def bat(name, body):
        (tools / name).write_bytes(('@echo off\n' + body + '\n').replace('\n', '\r\n').encode('ascii'))
    bat('settings64.bat', 'set "PATH=%~dp0;%PATH%"\nexit /b 0')
    bat('failed_settings.bat', 'exit /b 1')
    bat('xvlog.bat', 'if "%SIM_TEST_MODE%"=="compile" exit /b 1\nexit /b 0')
    bat('xelab.bat', 'if "%SIM_TEST_MODE%"=="elaborate" exit /b 1\nexit /b 0')
    bat('xsim.bat', '"%SIM_TEST_PYTHON%" -X utf8 "%~dp0emit.py"\nexit /b %errorlevel%')
    results = []

    def record(name, passed, **detail):
        results.append(dict(name=name, passed=bool(passed), **detail))
        save(out / 'results.json', results)
        print(('PASS ' if passed else 'FAIL ') + name, flush=True)

    def case(mode, good=False, extra=None, settings='settings64.bat', checks=None, env_patch=None):
        root = out / mode / '中文 source space'
        root.mkdir(parents=True)
        for rel in ['build/scripts/run_sim.py', 'sim/run_sim.bat', 'sim/tb/tb_md_pipeline.v']:
            dest = root / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(repo / rel, dest)
        shutil.copytree(repo / 'src/rtl', root / 'src/rtl')
        logs = root / 'sim/logs'
        logs.mkdir()
        (logs / 'sim_run.log').write_text('仿真结束\nx_hits=0\n', encoding='utf-8')
        before = hashes(root)
        scratch = out / mode / 'scratch space'
        if mode == 'scratch_file': scratch.write_text('keep', encoding='ascii')
        env = dict(os.environ, SIM_SCRATCH_ROOT=str(scratch), VIVADO_SETTINGS=str(tools / settings),
                   SIM_TEST_MODE=mode, SIM_TEST_PYTHON=sys.executable,
                   PYTHONUTF8='1', PYTHONIOENCODING='utf-8', PYTHONDONTWRITEBYTECODE='1')
        env.pop('XILINX_VIVADO', None)
        env.update(env_patch or {})
        cmd = [sys.executable, '-X', 'utf8', str(root / 'build/scripts/run_sim.py'), *(extra or [])]
        p = subprocess.run(cmd, cwd=root, env=env, capture_output=True, timeout=40)
        (root.parent / 'stdout.raw').write_bytes(p.stdout)
        (root.parent / 'stderr.raw').write_bytes(p.stderr)
        summaries = list(scratch.glob('*/result.json')) if scratch.is_dir() else []
        result = json.loads(summaries[0].read_text(encoding='utf-8')) if len(summaries) == 1 else None
        ok = (p.returncode == 0 if good else p.returncode != 0)
        if checks:
            ok = ok and checks(result, summaries, before, hashes(root))
        record(mode, ok, rc=p.returncode, command=cmd, results=[str(s) for s in summaries])
        return root, scratch, result, env, cmd

    def isolated(result, paths, before, after):
        if result is None or before != after or not result['simulation_passed']:
            return False
        run = paths[0].parent
        manifest = json.loads((run / 'manifest.json').read_text(encoding='utf-8'))
        fl = (run / 'sim/files.f').read_text(encoding='ascii').splitlines()
        return (result['csv_frames'] == list(range(11))
                and result['completeness']['checked'] is False
                and all(s.startswith('"../src/rtl/') or s.startswith('"tb/') for s in fl)
                and (run / 'sim/logs/sim_run.raw').is_file()
                and all(hashlib.sha256((run / rel).read_bytes()).hexdigest() == h
                        for rel, h in manifest['sources'].items()))

    root, scratch, result, env, cmd = case('healthy', good=True, checks=isolated)
    prior = hashes(scratch)
    p = subprocess.run(cmd, cwd=root, env=env, capture_output=True, timeout=40)
    (root.parent / 'second_stdout.raw').write_bytes(p.stdout)
    now = hashes(scratch)
    record('second_run_is_distinct_and_preserves_first', p.returncode == 0
           and len(list(scratch.glob('*/result.json'))) == 2
           and all(now.get(k) == v for k, v in prior.items()))
    case('mixed', good=True, checks=isolated)
    for mode in ['compile', 'elaborate', 'engine', 'engine_caps', 'bracket_error', 'fatal',
                 'lower_fatal', 'error', 'x_chinese', 'x_numeric', 'no_x_check', 'no_done',
                 'nonzero', 'timeout', 'no_output', 'no_csv', 'empty_csv', 'csv_x',
                 'duplicate', 'gap', 'reverse', 'bad_bytes']:
        case(mode)
    case('missing_settings', settings='missing.bat')
    case('failed_settings', settings='failed_settings.bat')
    case('scratch_file')
    case('invalid_top', extra=['--top', '../tb_md_pipeline'])
    case('expect12', extra=['--expect-frames', '12'], checks=lambda r, p, b, n:
         r is not None and r['simulation_passed'] and not r['passed']
         and r['completeness']['missing'] == [11] and r['csv_frames'] == list(range(11)))
    case('expect11', good=True, extra=['--expect-frames', '11'], checks=lambda r, p, b, n:
         r is not None and r['completeness']['passed'] and r['passed'])
    case('negative_count', extra=['--expect-frames', '-1'])
    case('settings_cli_priority', good=True, settings='missing.bat',
         extra=['--vivado-settings', str(tools / 'settings64.bat')], checks=isolated)
    case('xilinx_settings', good=True, checks=isolated,
         env_patch={'VIVADO_SETTINGS': '', 'XILINX_VIVADO': str(tools)})
    case('path_environment', good=True, checks=isolated,
         env_patch={'VIVADO_SETTINGS': '', 'PATH': str(tools) + os.pathsep + os.environ['PATH']})
    case('no_tools', env_patch={'VIVADO_SETTINGS': '', 'PATH': str(Path(os.environ['SystemRoot']) / 'System32')})
    case('source_scratch_rejected', extra=['--scratch-root', str(out / 'source_scratch_rejected/中文 source space/sim')])
    case('scratch_cli_priority', good=True,
         extra=['--scratch-root', str(out / 'scratch_cli_priority/scratch space')], checks=isolated,
         env_patch={'SIM_SCRATCH_ROOT': str(out / 'not chosen')})
    case('missing_top', extra=['--top', 'tb_missing'])
    case('unsafe_top', extra=['--top', 'tb_md_pipeline&echo_bad'])
    case('zero_count', extra=['--expect-frames', '0'])
    case('expect_offset', extra=['--expect-frames', '11', '--first-frame', '1'],
         checks=lambda r, p, b, n: r is not None and r['completeness']['missing'] == [11]
         and r['completeness']['unexpected'] == [0])
    # Direct batch use must not overwrite project artifacts. Only the Python
    # launcher supplies the isolation flag after allocating a fresh directory.
    before = hashes(root)
    direct_env = dict(env)
    direct_env.pop('FPGA_SIM_ISOLATED_RUN', None)
    p = subprocess.run('call run_sim.bat', cwd=root / 'sim', env=direct_env,
                       shell=True, capture_output=True, timeout=40)
    (out / 'direct_batch.raw').write_bytes(p.stdout + p.stderr)
    record('direct_batch_requires_isolated_launcher', p.returncode != 0 and before == hashes(root))
    # Read the template without importing it: the old module writes files on import.
    tree = ast.parse((repo / 'build/scripts/fix_bat_eol.py').read_text(encoding='utf-8'))
    template = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign)
                    and any(isinstance(t, ast.Name) and t.id == 'SIM_BAT' for t in n.targets))
    actual = (repo / 'sim/run_sim.bat').read_bytes()
    record('batch_template_ascii_crlf', actual == template.replace('\r\n', '\n').replace('\n', '\r\n').encode('ascii'))
    attrs = (repo / '.gitattributes').read_text(encoding='utf-8')
    record('checkout_retains_batch_crlf', any(l.strip() == '*.bat text eol=crlf' for l in attrs.splitlines()))
    record('source_checkout_unchanged', hashes(repo) == source_before)
    print(f'{sum(r["passed"] for r in results)}/{len(results)} PASS; evidence: {out}')
    return 0 if all(r['passed'] for r in results) else 1


if __name__ == '__main__':
    sys.exit(main())
