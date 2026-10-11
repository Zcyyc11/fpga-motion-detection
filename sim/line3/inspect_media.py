"""Read-only media audit: event neighbours and exact RTL overlay bounds."""
import argparse
import json
from pathlib import Path
import sys
import cv2
import numpy as np
from compare import read_csv

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'sim'))
from view_sim import read_ppm, red_box_bounds


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--wave', type=Path)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=False)
    result = {}
    old = ROOT/'report/line3_20261009/run_ead15e0_01'
    for mode, suffix in [('clean',''),('algo','_algo')]:
        cap = cv2.VideoCapture(str(old/mode/('track_result'+suffix+'.mp4')))
        panels = []
        for f in [42,43,44,101,102,103]:
            cap.set(cv2.CAP_PROP_POS_FRAMES, f)
            ok, frame = cap.read()
            if not ok:
                raise ValueError('Cannot decode ' + str(f))
            panel = cv2.resize(frame,(640,360))
            cv2.rectangle(panel,(0,332),(320,359),(230,230,230),-1)
            cv2.putText(panel, mode+' decoded frame '+str(f),(8,353),cv2.FONT_HERSHEY_SIMPLEX,.55,(0,0,0),1,cv2.LINE_AA)
            panels.append(panel)
        cap.release()
        ok, png = cv2.imencode('.png',np.vstack([np.hstack(panels[i:i+3]) for i in (0,3)]))
        if not ok:
            raise ValueError('PNG encoding failed')
        png.tofile(str(a.out/(mode+'_alarm_frames.png')))
        _, rows = read_csv(old/mode/'target_audit.csv')
        wrong = [r for r in rows if r['merged']=='False' and abs(float(r['vx']))>1 and (float(r['vx'])>0)!=(float(r['truth_vx'])>0)]
        obs=json.loads((old/(mode+'_observed')/'observations.json').read_text(encoding='utf-8'))
        changes=[]
        prev=0
        for r in obs['alarms']:
            if r['cross_out']!=prev:
                changes.append(r)
            prev=r['cross_out']
        result[mode] = dict(direction_errors=wrong,cross_out_counter_changes=changes,
                            recovery_frames=[r for r in obs['frames'] if r['frame'] in [31,32,33,41,42,43,66,67,68]])
    if a.wave:
        _, rows=read_csv(a.wave/'bbox_rtl.csv')
        bb={int(r['frame']):{k:int(v) for k,v in r.items()} for r in rows}
        frames=sorted(a.wave.glob('frame_*.ppm'),key=lambda p:int(p.stem.split('_')[1]))
        checks=[]
        for p in frames:
            k=int(p.stem.split('_')[1])
            img=read_ppm(p)
            got,nred=red_box_bounds(img)
            row=bb.get(k-1)
            exp=tuple(row[f]*2 for f in ['b_x1','b_y1','b_x2','b_y2']) if row and row['b_valid'] else None
            checks.append(dict(frame=k, expected=exp,actual=got,red_pixels=nred,passed=got==exp,
                               shape=list(img.shape)))
        result['rtl_overlay']=checks
        result['rtl_frame_set_complete']=[r['frame'] for r in checks]==list(range(12))
        masks=sorted(a.wave.glob('mask_*.ppm'),key=lambda p:int(p.stem.split('_')[1]))
        result['mask_frames']=[int(p.stem.split('_')[1]) for p in masks]
        result['mask_shapes']=[list(read_ppm(p).shape) for p in masks]
        result['rtl_pass']=result['rtl_frame_set_complete'] and all(r['passed'] for r in checks) and result['mask_frames']==list(range(12))
    save(a.out/'details.json',result)
    print(json.dumps({k:len(v['direction_errors']) for k,v in result.items() if k in ['clean','algo']}))
    return 0 if result.get('rtl_pass',True) else 2


if __name__=='__main__':
    raise SystemExit(main())
