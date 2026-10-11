"""Build isolated board_top copies; preserve every failed attempt and source byte."""
import sys,pathlib,subprocess,shutil,difflib,json
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from task_tools import *

mode=int(sys.argv[1]); assert mode in (0,1)
repo=WORK/'integration'
CANDIDATE=json.loads((OUT/'integration_revision.json').read_text(encoding='utf-8'))['sha']
d=WORK/f'board_integrated_mode{mode}'
d.mkdir(exist_ok=False)
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',CANDIDATE,'--','src/rtl','board','build/scripts/build_vivado.tcl'],cwd=repo,text=True,encoding='utf-8').splitlines()
manifest=[]
for rel in paths:
    if not rel.endswith(('.v','.xdc','.tcl')): continue
    p=d/rel;p.parent.mkdir(parents=True,exist_ok=True)
    p.write_bytes(subprocess.check_output(['git','show',CANDIDATE+':'+rel],cwd=repo))
    manifest.append(dict(path=rel,sha256=digest(p)))
tcl=d/'build/scripts/build_vivado.tcl'
original=tcl.read_text(encoding='utf-8')
shutil.copy2(tcl,d/'build/scripts/build_vivado_original.tcl')
needle='set_property top $TOP [current_fileset]'
assert original.count(needle)==1
# The original parses MODE_BG but never applies it to the sources_1 fileset.
# A separate, reviewable adaptation enables real parameter selection and limits jobs.
assert original.count('set_property generic [format')==1
modified=original
modified=modified.replace(' -jobs 8',' -jobs 2').replace('create_project -force ','create_project ')
# New copy only; original tcl is kept byte-for-byte beside it.
tcl.write_text(modified,encoding='utf-8',newline='\n')
patch=''.join(difflib.unified_diff(original.splitlines(True),modified.splitlines(True),fromfile='a/build/scripts/build_vivado.tcl',tofile='b/build/scripts/build_vivado.tcl'))
(OUT/f'board_mode{mode}_build_adaptation.patch').write_text(patch,encoding='utf-8')
ip=WORK/'vivado-library'
ipsha=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ip,text=True).strip()
save(f'board_mode{mode}_inputs.json',dict(source_sha=CANDIDATE,mode=mode,files=manifest,ip_sha=ipsha,ip_url='https://github.com/Digilent/vivado-library',
    source_tree=str(d),clock='125 MHz external; generated 74.25 MHz pixel clock',scope='board_top internal pattern + HDMI output; no HDMI input, no hardware test',
    adaptations=['limit jobs to 2','remove create_project -force in fresh directory']))
rec,txt=run(f'board_integrated_mode{mode}',[Path('D:/AMD2025.2/2025.2/Vivado/bin/vivado.bat'),'-mode','batch','-source',tcl,'-nojournal','-log',d/'vivado.log','-tclargs',str(mode)],d,env={'MOTION_IP_REPO':str(ip)},timeout=5400)
out=OUT/f'board_mode{mode}';out.mkdir()
for p in (d/'build/reports').glob('*'):
    if p.is_file():shutil.copy2(p,out/p.name)
bit=d/'build/bitstream/board_top.bit'
save(f'board_mode{mode}_result.json',dict(command=rec,bit_exists=bit.exists(),bit_sha256=digest(bit) if bit.exists() else None,
    effective_generic=f'EFFECTIVE_GENERIC=MODE_BG={mode}' in txt,
    reports=[p.name for p in out.iterdir()],scope='routed board_top internal pattern output only; no board tested'))
print(txt[-4000:])
