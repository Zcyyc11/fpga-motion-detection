"""Freeze this integration and IP, then run Vivado without overwriting any run."""
from pathlib import Path
import argparse,datetime,hashlib,json,os,shutil,subprocess,sys

root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser()
p.add_argument('output',type=Path)
p.add_argument('--ip-repo',type=Path,default=root/'ip_repository')
p.add_argument('--vivado-bin',type=Path,default=None,help='Vivado bin directory; otherwise use VIVADO_BIN or PATH')
args=p.parse_args();out=args.output.resolve()
if args.vivado_bin is None:
    configured=os.environ.get('VIVADO_BIN')
    found=shutil.which('vivado.bat')
    if not configured and not found:
        p.error('Set VIVADO_BIN or pass --vivado-bin with the Vivado bin directory')
    args.vivado_bin=Path(configured) if configured else Path(found).parent
args.vivado_bin=args.vivado_bin.resolve()
args.ip_repo=args.ip_repo.resolve()
if not (args.vivado_bin/'vivado.bat').is_file():
    p.error('vivado.bat was not found in the selected bin directory')
out.mkdir(parents=True,exist_ok=False)
frozen=out/'frozen';frozen.mkdir()
for folder in ['src','board','build/scripts','sim']:
    shutil.copytree(root/folder,frozen/folder,ignore=shutil.ignore_patterns('*.bak*'))
for ip_name in ['rgb2dvi','dvi2rgb']:
    ip=args.ip_repo/'ip'/ip_name
    if not ip.is_dir():ip=args.ip_repo/ip_name
    if not ip.is_dir():raise SystemExit(ip_name+' IP missing')
    shutil.copytree(ip,out/'ip_repository'/ip_name)
for license_file in args.ip_repo.iterdir():
    if license_file.is_file() and license_file.name.lower().startswith('license'):
        shutil.copy2(license_file,out/'ip_repository'/license_file.name)
def hashes(path):
    return {str(x.relative_to(path)).replace('\\','/'):hashlib.sha256(x.read_bytes()).hexdigest() for x in sorted(path.rglob('*')) if x.is_file()}
(out/'source_manifest.json').write_text(json.dumps({'source_root':str(root),'source_hashes':hashes(frozen),'ip_hashes':hashes(out/'ip_repository'),'board_verified':False},indent=2),encoding='utf-8')
env=os.environ.copy();env['MOTION_IP_REPO']=str(out/'ip_repository')
cmd=[str(args.vivado_bin/'vivado.bat'),'-mode','batch','-nojournal','-nolog','-source',str(frozen/'build/scripts/build_vivado.tcl'),'-tclargs',str(out)]
state={'status':'running','runner_pid':os.getpid(),'command':cmd,'started':datetime.datetime.now(datetime.timezone.utc).isoformat(),'board_verified':False}
with (out/'console.log').open('wb') as log:
    child=subprocess.Popen(cmd,cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT)
    state['pid']=child.pid
    (out/'process.json').write_text(json.dumps(state,indent=2),encoding='utf-8')
    print(json.dumps(state),flush=True)
    rc=child.wait()
state.update(status='finished',returncode=rc,finished=datetime.datetime.now(datetime.timezone.utc).isoformat())
(out/'process.json').write_text(json.dumps(state,indent=2),encoding='utf-8')
print(json.dumps(state),flush=True)
sys.exit(rc)
