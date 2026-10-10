
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
