"""Compare real TX pin samples to independently logged UART input records."""
import argparse, csv, hashlib, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'line3'))
from uart_receiver import receive
from verify_uart_capture import verify

p=argparse.ArgumentParser();p.add_argument('--sim',required=True);p.add_argument('--out',required=True)
a=p.parse_args();sim=Path(a.sim);out=Path(a.out);out.mkdir(parents=True,exist_ok=False)
assert not (sim/'probe_faults.txt').read_text().strip(), 'probe reported UART faults'
raw=bytes(int(row['byte_hex'],16) for row in csv.DictReader((sim/'uart_bytes.csv').open()))
frames={};sealed=[]
with (sim/'tx_inputs.csv').open() as f:
    rows=csv.reader(f);next(rows)
    for row in rows:
        kind,fid,video,when=row[:4];fid=int(fid);vals=list(map(int,row[4:]))
        frame=frames.setdefault(fid,dict(frame_id=fid,input_frame_ref='UART input window '+str(fid),targets=[],events=[]))
        if kind=='T':
            frame['targets'].append(dict(zip(['id','x1','y1','x2','y2','flags'],vals)))
        elif kind=='E':
            frame['events'].append(dict(zip(['id','type','center_x'],vals)))
        elif kind=='H':
            assert len(frame['targets'])==vals[0], 'input count mismatch'
            sealed.append(frame)
        else: raise ValueError(kind)
(out/'raw_from_tx.bin').write_bytes(raw)
expected=out/'expected.jsonl'
expected.write_text(''.join(json.dumps(f)+'\n' for f in sealed),encoding='utf-8')
receive([raw],out/'capture','simulated',save_images=0)
result=verify(out/'capture',expected)
result['inputs_sha256']={n:hashlib.sha256((sim/n).read_bytes()).hexdigest() for n in ['uart_bytes.csv','tx_inputs.csv','probe_faults.txt']}
(out/'comparison.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result));raise SystemExit(result['exit_code'])
