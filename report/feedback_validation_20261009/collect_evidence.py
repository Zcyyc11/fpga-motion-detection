"""Retain compact review evidence in Git; keep every full run artifact on disk."""
from pathlib import Path
import hashlib
import json
import shutil

root = Path(__file__).resolve().parent
run = root/'run_20261010_r2'
dest = root/'evidence'
dest.mkdir(exist_ok=False)
files = list(run.glob('*.json')) + list(run.glob('*.log')) + list(run.glob('*.csv'))
for folder in ['line3','line3/cases','line3/clean','line3/algo','boundaries','runner','tools','rtl_drained_framediff','rtl_drained_bg']:
    for pattern in ['*.json','*.csv']:
        files.extend((run/folder).glob(pattern))
for folder in ['rtl_drained_framediff','rtl_drained_bg']:
    files.append(run/folder/'console.txt')
manifest = []
for p in sorted(set(files)):
    q = dest/p.relative_to(run)
    q.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(p,q)
    manifest.append({'source':str(p),'evidence':q.relative_to(root).as_posix(),'bytes':q.stat().st_size,'sha256':hashlib.sha256(q.read_bytes()).hexdigest()})
for p in Path('D:/666666/Temp/codex_feedback_20261010_rtl_r2/default').glob('run_*/result.json'):
    for rel in ['result.json','manifest.json','sim/wave/bbox_rtl.csv','sim/logs/sim_run.log']:
        source = p.parent/rel
        q = dest/'rtl_default'/rel
        q.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,q)
        manifest.append({'source':str(source),'evidence':q.relative_to(root).as_posix(),'bytes':q.stat().st_size,'sha256':hashlib.sha256(q.read_bytes()).hexdigest()})
(root/'evidence_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Preserved',len(manifest),'evidence files;',sum(x['bytes'] for x in manifest),'bytes')
