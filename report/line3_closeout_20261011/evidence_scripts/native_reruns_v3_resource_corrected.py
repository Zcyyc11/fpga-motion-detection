"""Run unchanged, eager-loader CLI; compare every expected CSV key and value."""
import pathlib,sys,csv,shutil,ctypes,subprocess,json
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from task_tools import *

class Memory(ctypes.Structure):
    _fields_=[('length',ctypes.c_ulong),('load',ctypes.c_ulong)]+[(s,ctypes.c_ulonglong) for s in ['total_phys','avail_phys','total_page','avail_page','total_virtual','avail_virtual','avail_extended']]

src=BASE/'captain_repo/src/ps'
reference=list(csv.DictReader((src/'cdnet_official_results.csv').open(encoding='utf-8')))
expected={(r['seq'],r['variant']):r for r in reference}
assert len(reference)==len(expected)==72
prior=json.loads((BASE/'audit_astra_20261010_214132/A2_unwrapped.json').read_text(encoding='utf-8'))
done={r['seq'] for r in prior}
seqs=sorted({r['seq'] for r in reference}-done)
source_hashes={}
for p in src.glob('*.py'):
    frozen=subprocess.check_output(['git','show',FROZEN+':src/ps/'+p.name],cwd=BASE/'captain_repo')
    assert p.read_bytes()==frozen,p
    source_hashes[p.name]=digest(p)
save('native_source_hashes_v2.json',source_hashes)
records=[]
for seq in seqs:
    name=seq.replace('/','__')
    d=WORK/'native_v2'/name;d.mkdir(parents=True,exist_ok=False)
    for p in src.glob('*.py'):shutil.copy2(p,d/p.name)
    m=Memory();m.length=ctypes.sizeof(Memory);ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
    memory={k:getattr(m,k) for k,t in m._fields_}
    if seq=='badWeather/snowFall':
        # 5801 frames: uint8 grayscale + uint8 labels + quarter-size uint64 sums.
        estimate=5801*480*720*(1+1+8/4)+1024**3
        safe=m.avail_page>estimate+2*1024**3 and m.avail_phys>1.5*1024**3
        save('snow_memory_gate.json',dict(memory=memory,estimated_process_bytes=estimate,safe_to_attempt=safe,
            strategy='one unchanged eager-loader process; no concurrent Vivado; OS-managed paging; no frame truncation'))
        if not safe:
            rec=dict(seq=seq,status='resource_gate_blocked',keys=0,memory=memory)
            save('native/'+name+'.json',rec);records.append(rec);continue
    r,t=run('native_'+name,[PY,'-I','-B','-X','utf8',d/'cdnet_official.py','--data-root',DATA,'--set','r12','--seq',seq],d,timeout=1800)
    out=d/'cdnet_official_results_r12.csv'
    rows=list(csv.DictReader(out.open(encoding='utf-8'))) if out.exists() else []
    got={(x['seq'],x['variant']):x for x in rows}
    want={k:v for k,v in expected.items() if k[0]==seq}
    differences=[{'key':k,'got':got.get(k),'expected':want.get(k)} for k in sorted(got.keys()|want.keys()) if got.get(k)!=want.get(k)]
    assert all(digest(d/n)==h for n,h in source_hashes.items())
    rec=dict(seq=seq,exit_code=r['exit_code'],keys=len(got),rows=len(rows),expected_keys=len(want),differences=differences,
             pass_=r['exit_code']==0 and len(rows)==len(got)==6 and not differences,seconds=r['seconds'],source_unchanged=True)
    if out.exists():shutil.copy2(out,OUT/('native_'+name+'.csv'))
    save('native/'+name+'.json',rec);records.append(rec)
    print(json.dumps(rec,ensure_ascii=False),flush=True)
save('native_new_summary.json',records)
assert all(r.get('pass_') for r in records if r.get('status')!='resource_gate_blocked')
