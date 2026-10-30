# -*- coding: utf-8 -*-
"""Run Vivado in a fresh retained directory and validate this run's evidence.

Settings priority: --vivado-settings, VIVADO_SETTINGS, XILINX_VIVADO, PATH.
Scratch priority: --scratch-root, SIM_SCRATCH_ROOT, OS temp/fpga_sim.
The file list uses quoted ASCII relative paths. Source files are only copied.
Exit 0 means simulation evidence passed; frame completeness is checked only
when --expect-frames is given. No golden-model comparison is performed here.
"""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
CSV_FIELDS = ['frame', 'b_valid', 'b_x1', 'b_y1', 'b_x2', 'b_y2', 'b_cnt']


def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decode_log(raw):
    """Tool paths can be GBK while testbench $display is UTF-8.
    Retain undecodable bytes as visible escapes and fail validation.
    """
    lines, encodings, bad = [], set(), []
    for number, line in enumerate(raw.splitlines(keepends=True), 1):
        for encoding in ('utf-8', 'gb18030'):
            try:
                lines.append(line.decode(encoding))
                encodings.add(encoding)
                break
            except UnicodeDecodeError:
                continue
        else:
            lines.append(line.decode('utf-8', errors='backslashreplace'))
            bad.append(number)
    return ''.join(lines).replace('\r\r\n', '\n').replace('\r\n', '\n'), sorted(encodings), bad


def inspect_run(text, rc, csv_path, top, expected, first_frame):
    failures = []
    stages = [s for s in ('xvlog', 'xelab', 'xsim') if '=== ' + s + ' ===' in text]
    done = '仿真结束' in text
    x_hits = [int(n) for n in re.findall(r'\bx_hits\s*=\s*(\d+)', text, re.I)]
    errors = [line for line in text.splitlines()
              if re.match(r'^\s*(?:!!\s*)?(?:\[(?:ERROR|FATAL)\]|(?:ERROR|FATAL)\b)', line, re.I)]
    if rc != 0:
        failures.append('子进程非零退出：%s' % rc)
    if stages != ['xvlog', 'xelab', 'xsim']:
        failures.append('工具阶段不完整：' + ', '.join(stages))
    if re.search(r'engine\s+failed\s+to\s+start', text, re.I):
        failures.append('仿真引擎未启动；检查 Vivado settings 和运行日志')
    if errors:
        failures.append('日志中存在 ERROR/FATAL')
    if re.search(r'\bTIMEOUT\b', text, re.I):
        failures.append('仿真报告超时')
    if not done:
        failures.append('没有本次仿真结束标记')
    if any(n != 0 for n in x_hits) or 'X 检查：掩码流出现' in text:
        failures.append('检测到未知态 X')
    if top == 'tb_md_pipeline' and not x_hits:
        failures.append('缺少 x_hits 检查结果')
    frames, csv_error = [], None
    require_csv = top == 'tb_md_pipeline' or expected is not None
    if require_csv or csv_path.exists():
        try:
            with csv_path.open(encoding='utf-8-sig', newline='') as stream:
                reader = csv.DictReader(stream)
                if reader.fieldnames != CSV_FIELDS:
                    raise ValueError('表头与 bbox_rtl.csv 约定不一致')
                for row in reader:
                    if None in row or any(v is None or not re.fullmatch(r'\d+', v) for v in row.values()):
                        raise ValueError('存在缺列、额外列或非负整数以外的值（含 X/Z）')
                    frames.append(int(row['frame']))
            if not frames:
                raise ValueError('CSV 没有检测记录')
            if frames != list(range(frames[0], frames[0] + len(frames))):
                raise ValueError('帧号重复、乱序或中间缺帧')
            log_frames = [int(n) for n in re.findall(r'第\s+(\d+)\s+帧检测', text)]
            if log_frames != frames:
                raise ValueError('日志与 CSV 的帧号集合或顺序不一致')
        except (OSError, ValueError, csv.Error) as exc:
            csv_error = str(exc)
            failures.append('CSV 校验失败：' + csv_error)
    simulation_passed = not failures
    completeness = dict(checked=expected is not None, expected_count=expected,
                        first_frame=first_frame if expected is not None else None,
                        actual_count=len(frames), missing=[], unexpected=[], passed=None)
    if expected is not None:
        wanted = set(range(first_frame, first_frame + expected))
        completeness.update(missing=sorted(wanted - set(frames)),
                            unexpected=sorted(set(frames) - wanted),
                            passed=frames == list(range(first_frame, first_frame + expected)))
        if not completeness['passed']:
            failures.append('帧范围不完整；查看 completeness.missing/unexpected')
    return dict(passed=not failures, simulation_passed=simulation_passed,
                subprocess_returncode=rc, stages=stages, done=done, x_hits=x_hits,
                errors=errors, failures=failures, csv_frames=frames, csv_error=csv_error,
                completeness=completeness, golden_comparison_performed=False)


def safe_path(value, label):
    # CALL expands percent signs twice; reject ambiguous shell syntax.
    if any(ord(c) < 32 or c in '%!^&|<>"' for c in str(value)):
        raise ValueError(label + ' 包含 cmd 不安全字符；请使用中文、英文、数字和空格路径')
    return Path(value).expanduser().resolve()


def git_state():
    info = {}
    for name, args in [('commit', ['rev-parse', 'HEAD']), ('status', ['status', '--porcelain'])]:
        p = subprocess.run(['git', '-C', str(ROOT), *args], capture_output=True, check=False)
        info[name] = p.stdout.decode('utf-8', errors='backslashreplace').strip() if p.returncode == 0 else None
    return info


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--top', default='tb_md_pipeline')
    ap.add_argument('--vivado-settings', help='settings64.bat 的完整路径')
    ap.add_argument('--scratch-root', help='独立运行目录的父目录；默认 SIM_SCRATCH_ROOT 或系统临时目录')
    ap.add_argument('--expect-frames', type=int, help='要求 CSV 恰好包含指定帧数；未指定则不宣称完整性通过')
    ap.add_argument('--first-frame', type=int, default=0, help='预期帧号起点；与 --expect-frames 配合')
    args = ap.parse_args()
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', args.top):
        ap.error('--top 必须是简单 Verilog 模块名，不能是路径或命令')
    if args.expect_frames is not None and args.expect_frames <= 0:
        ap.error('--expect-frames 必须大于 0')
    if args.first_frame < 0 or (args.first_frame and args.expect_frames is None):
        ap.error('--first-frame 必须非负，且只能与 --expect-frames 配合')
    if os.name != 'nt':
        ap.error('本入口调用 Windows Vivado .bat，需要在 Windows 下运行')
    env = dict(os.environ)
    run = None
    try:
        setting = args.vivado_settings or env.get('VIVADO_SETTINGS')
        setting_source = '--vivado-settings' if args.vivado_settings else 'VIVADO_SETTINGS'
        if not setting and env.get('XILINX_VIVADO'):
            setting = str(Path(env['XILINX_VIVADO']) / 'settings64.bat')
            setting_source = 'XILINX_VIVADO'
        if setting:
            setting = safe_path(setting, 'Vivado settings')
            if not setting.is_file() or setting.suffix.lower() != '.bat':
                print('配置失败：settings 批处理不存在或不是 .bat：%s' % setting)
                print('请用 --vivado-settings 指向已安装 Vivado 的 settings64.bat')
                return 10
            env['VIVADO_SETTINGS'] = str(setting)
        else:
            setting_source = 'PATH（当前 shell 的 Vivado 环境）'
        scratch = safe_path(args.scratch_root or env.get('SIM_SCRATCH_ROOT')
                            or str(Path(tempfile.gettempdir()) / 'fpga_sim'), 'scratch')
        if scratch == ROOT or ROOT in scratch.parents:
            raise ValueError('scratch 必须在源码目录外，避免在工程内生成仿真产物')
        rtl = sorted((ROOT / 'src/rtl').glob('*.v')) + sorted((ROOT / 'src/rtl/board').glob('*.v'))
        tb = ROOT / 'sim/tb' / (args.top + '.v')
        if not rtl or not tb.is_file():
            raise ValueError('缺少 RTL 或仿真台：%s' % tb)
        scratch.mkdir(parents=True, exist_ok=True)
        run = Path(tempfile.mkdtemp(prefix='run_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ_'), dir=scratch))
        sim = run / 'sim'
        (sim / 'logs').mkdir(parents=True)
        (sim / 'wave').mkdir()
        files = rtl + [tb, ROOT / 'sim/run_sim.bat', ROOT / 'build/scripts/run_sim.py']
        sources = {}
        for source in files:
            rel = source.relative_to(ROOT)
            dest = run / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest)
            sources[rel.as_posix()] = sha256(dest)
            if sha256(source) != sources[rel.as_posix()]:
                raise ValueError('复制过程中源文件发生变化：%s' % source)
        paths = ['../' + p.relative_to(ROOT).as_posix() for p in rtl] + ['tb/' + tb.name]
        (sim / 'files.f').write_text(''.join('"' + p + '"\n' for p in paths), encoding='ascii')
        command = 'call "%s" "%s" "sim_%s" "files.f"' % (sim / "run_sim.bat", args.top, args.top)
        env['FPGA_SIM_ISOLATED_RUN'] = '1'
        try:
            git = git_state()
        except OSError:
            git = dict(commit=None, status=None)
        manifest = dict(source_root=str(ROOT), run_dir=str(run), sources=sources, git=git,
                        created_utc=datetime.now(timezone.utc).isoformat(), command=command,
                        cwd=str(sim), arguments=vars(args), settings_source=setting_source,
                        settings=str(setting) if setting else None,
                        settings_sha256=sha256(setting) if setting else None,
                        python=sys.version, filelist_encoding='ascii', filelist_paths='quoted_relative')
        save_json(run / 'manifest.json', manifest)
        print('Vivado 环境来源：' + setting_source)
        print('本次运行目录（全部保留）：' + str(run), flush=True)
        start = time.monotonic()
        raw_path = sim / 'logs/sim_run.raw'
        with raw_path.open('wb') as stream:
            proc = subprocess.run(command, cwd=sim, shell=True, env=env,
                                  stdout=stream, stderr=subprocess.STDOUT, check=False)
        text, encodings, bad = decode_log(raw_path.read_bytes())
        (sim / 'logs/sim_run.log').write_text(text, encoding='utf-8', newline='\n')
        result = inspect_run(text, proc.returncode, sim / 'wave/bbox_rtl.csv',
                             args.top, args.expect_frames, args.first_frame)
        result.update(run_dir=str(run), seconds=round(time.monotonic() - start, 3),
                      log_encodings=encodings, undecodable_lines=bad, raw_log_sha256=sha256(raw_path))
        if bad:
            result['passed'] = result['simulation_passed'] = False
            result['failures'].append('日志存在无法解码的行；原始字节已保留')
        result['artifacts'] = {p.relative_to(run).as_posix(): sha256(p)
                               for p in sorted((sim / 'wave').glob('*')) if p.is_file()}
        save_json(run / 'result.json', result)
        frames = result['csv_frames']
        print('仿真流程：' + ('通过' if result['simulation_passed'] else '失败'))
        print('检测记录：%d 条，帧号 %s' % (len(frames), str(frames)))
        print('帧完整性：' + ('未检查（可指定 --expect-frames）；未进行模型一致性比较'
              if args.expect_frames is None else str(result['completeness'])))
        for failure in result['failures']:
            print('失败原因：' + failure)
        for line in result['errors'][:8]:
            print(line)
        print('日志：' + str(sim / 'logs/sim_run.log'))
        print('结果：' + str(run / 'result.json'))
        if proc.returncode in (10, 11, 12):
            return proc.returncode
        return 0 if result['passed'] else 2
    except (OSError, ValueError, UnicodeError) as exc:
        message = '运行失败：%s' % exc
        print(message)
        if run is not None:
            save_json(run / 'result.json', dict(passed=False, simulation_passed=False,
                                               failures=[message], run_dir=str(run)))
            print('已保留运行目录：' + str(run))
        return 2


if __name__ == '__main__':
    sys.exit(main())
