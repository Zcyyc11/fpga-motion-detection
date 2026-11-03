"""Reproducible black-box xsim checks. Each run gets its own evidence directory."""
import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("label")
parser.add_argument("--source", type=Path, default=ROOT / "src/rtl/attach_z2_interaction.v")
args = parser.parse_args()
configured = os.environ.get('VIVADO_BIN')
found = shutil.which('xvlog.bat')
if not configured and not found:
    parser.error('Set VIVADO_BIN to the Vivado bin directory or add it to PATH')
bin_dir = Path(configured).resolve() if configured else Path(found).resolve().parent
for tool in ('xvlog', 'xelab', 'xsim'):
    if not (bin_dir / (tool + '.bat')).is_file():
        parser.error(f'{tool}.bat was not found in {bin_dir}')
out = ROOT / "evidence" / args.label
out.mkdir(parents=True, exist_ok=False)
sources = [args.source.resolve(), ROOT / "sim/tb_attach_protocol.sv"]
manifest = {"board_verified": False, "started": time.time(), "sources": {}, "commands": [], "tests": []}
for source in sources:
    manifest["sources"][str(source)] = hashlib.sha256(source.read_bytes()).hexdigest()

def run(tool, arguments, logfile):
    command = [str(bin_dir / (tool + ".bat")), *map(str, arguments)]
    result = subprocess.run(command, cwd=out, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out / logfile).write_bytes(result.stdout)
    manifest["commands"].append({"argv": command, "returncode": result.returncode, "log": logfile})
    return result.returncode, result.stdout.decode("utf-8", errors="replace")

rc, _ = run("xvlog", ["-sv", *sources], "compile.log")
if rc == 0:
    rc, _ = run("xelab", ["tb_attach_protocol", "-s", "attach_protocol_sim"], "elaborate.log")
if rc == 0:
    for test in range(3):
        rc_test, log = run("xsim", ["attach_protocol_sim", "-testplusarg", f"TEST{test}", "-runall"], f"test_{test}.log")
        passed = rc_test == 0 and f"ATTACH_PROTOCOL_PASS test={test}" in log and "CHECK_FAIL" not in log
        manifest["tests"].append({"test": test, "passed": passed, "returncode": rc_test})
        print(f"test {test}: {'PASS' if passed else 'FAIL'}", flush=True)
manifest["passed"] = len(manifest["tests"]) == 3 and all(t["passed"] for t in manifest["tests"])
manifest["finished"] = time.time()
(out / "result.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
print(out)
raise SystemExit(0 if manifest["passed"] else 1)
