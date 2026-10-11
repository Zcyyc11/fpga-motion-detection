"""Small counterexamples that bound the review's broad claims."""
from pathlib import Path
import csv
import hashlib
import io
import json
import os
import sys

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[2]
out = Path(__file__).resolve().parent/'run_20261010_r2'
sys.path.insert(0, str(root/'src/ps'))
import multi_track as mt
import rtl_golden as rg

def box(x):
    return dict(cx=float(x),cy=15.,x0=x-5,x1=x+5,y0=10,y1=20,area=121)

rule = mt.AlarmRule(line_x=50,inside='left')
rule.update(0,{1:box(30)},{1:{'vx':-10}})
rule.update(1,{1:box(70)},{1:{'vx':-10}})
base = (root/'src/ps/rtl_golden.py').read_text(encoding='utf-8')
altered = {'__name__':'isolated','__file__':str(root/'src/ps/rtl_golden.py')}
exec(compile(base.replace('THRESH = 70','THRESH = 1000'),'<mutated>','exec'),altered)
bg = rg.run(mode='bg')[1]
bg_mut = altered['run'](mode='bg')[1]
xs = [rg.obj_x_at(t,**{k:rg.DEF[k] for k in ('w','obj_w','x0','dx')}) for t in range(12)]
old_csv = Path(os.environ['LOCALAPPDATA'])/'Temp/ind_review_20261009/out/mutC.csv'
data = {'counterexample_cross_out_count':rule.n_cross_out,'counterexample_cross_out_events':rule.events,
        'counterexample_inputs':'inside=left; cx:30->70; vx:-10 in both observations (inconsistent velocity)',
        'background_threshold1000_changed_frames':[i for i,(x,y) in enumerate(zip(bg,bg_mut)) if x!=y],
        'default_x_positions':xs,'default_wraps':[i for i in range(1,12) if xs[i]<xs[i-1]],
        'reviewer_mutC_path':str(old_csv),'reviewer_mutC_exists':old_csv.exists()}
if old_csv.exists():
    raw = old_csv.read_bytes()
    (out/'reviewer_mutC_original.csv').write_bytes(raw)
    rows = list(csv.reader(io.StringIO(raw.decode('utf-8-sig'))))
    data.update(reviewer_mutC_sha256=hashlib.sha256(raw).hexdigest(),reviewer_mutC_last_row=rows[-1],
                reviewer_mutC_matches_unmodified_model=[list(map(str,row)) for row in rg.run()[1]]==rows[1:])
(out/'supplement_checks.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(data,ensure_ascii=False,indent=2))
