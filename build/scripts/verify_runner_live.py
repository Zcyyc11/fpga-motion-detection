"""Retained actual Vivado runs; never deletes or alters the source checkout."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time


def hashes(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file() and '.git' not in p.parts}


def save(p, obj):
    p.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, required=True)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--ascii-root', type=Path, required=True)
    ap.add_argument('--settings', type=Path, required=True)
    a = ap.parse_args()
    repo, out, ascii_root = a.repo.resolve(), a.out.resolve(), a.ascii_root.resolve()
    assert str(ascii_root).isascii()
    out.mkdir(parents=True, exist_ok=False)
    ascii_root.mkdir(parents=True, exist_ok=False)
    initial = hashes(repo)
    variants = [('english', ascii_root / 'plain', True, None),
                ('chinese', out / '中文工程', True, None),
                ('space', ascii_root / 'space project', True, None),
                ('chinese_space', out / '中文 空格工程', True, None),
                ('expect12', out / '完整性检查', False, 'frames'),
                ('compile_error', out / '编译错误', False, 'compile'),
                ('x_state', out / '未知态', False, 'x')]
    results = []
    for name, source, expected_ok, injection in variants:
        source.mkdir(parents=True)
        for rel in ['build/scripts/run_sim.py', 'sim/run_sim.bat', 'sim/tb/tb_md_pipeline.v']:
            p = source / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(repo / rel, p)
        shutil.copytree(repo / 'src/rtl', source / 'src/rtl')
        if injection in ('compile', 'x'):
            tb = source / 'sim/tb/tb_md_pipeline.v'
            shutil.copy2(tb, source / 'tb_before_injection.v')
            text = tb.read_text(encoding='utf-8')
            if injection == 'compile':
                text += '\nintentional invalid syntax for compile-failure regression;\n'
            else:
                assert 'initial x_hits = 0;' in text
                text = text.replace('initial x_hits = 0;', 'initial x_hits = 1;')
            tb.write_text(text, encoding='utf-8')
        before = hashes(source)
        scratch = source.parent / (source.name + '_runs')
        cmd = [sys.executable, '-X', 'utf8', str(source / 'build/scripts/run_sim.py'),
               '--vivado-settings', str(a.settings.resolve()), '--scratch-root', str(scratch)]
        if injection == 'frames': cmd += ['--expect-frames', '12']
        env = dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8', PYTHONDONTWRITEBYTECODE='1')
        start = time.monotonic()
        proc = subprocess.run(cmd, cwd=source, env=env, capture_output=True, timeout=180)
        logdir = out / 'entry_logs'
        logdir.mkdir(exist_ok=True)
        (logdir / (name + '.stdout.txt')).write_bytes(proc.stdout)
        (logdir / (name + '.stderr.txt')).write_bytes(proc.stderr)
        summaries = list(scratch.glob('*/result.json'))
        assert len(summaries) == 1, summaries
        result = json.loads(summaries[0].read_text(encoding='utf-8'))
        run = summaries[0].parent
        manifest = json.loads((run / 'manifest.json').read_text(encoding='utf-8'))
        copied_ok = all(hashlib.sha256((run / rel).read_bytes()).hexdigest() == h
                        for rel, h in manifest['sources'].items())
        preserved = before == hashes(source)
        passed = (proc.returncode == 0) == expected_ok and result['passed'] == expected_ok and copied_ok and preserved
        if expected_ok:
            passed = passed and result['csv_frames'] == list(range(11)) and result['x_hits'] == [0]
        if injection == 'frames':
            passed = passed and result['simulation_passed'] and result['completeness']['missing'] == [11]
        if injection == 'compile':
            passed = passed and result['stages'] == ['xvlog'] and result['errors']
        if injection == 'x':
            passed = passed and any('未知态' in s for s in result['failures'])
        row = dict(name=name, passed=bool(passed), expected_success=expected_ok,
                   command=cmd, source=str(source), result=str(summaries[0]),
                   rc=proc.returncode, seconds=round(time.monotonic()-start, 2),
                   source_unchanged=preserved, copied_hashes_match=copied_ok,
                   simulation_passed=result['simulation_passed'], csv_frames=result['csv_frames'],
                   failures=result['failures'], encodings=result['log_encodings'])
        results.append(row)
        save(out / 'results.json', results)
        print(json.dumps(row, ensure_ascii=False), flush=True)
    assert initial == hashes(repo), 'source checkout changed'
    assert all(r['passed'] for r in results), results
    print(f'Live runner checks: {len(results)}/{len(results)} PASS (negative cases fail as expected)')


if __name__ == '__main__':
    main()
