"""Additive local verification. Never reads or prints credentials."""
from pathlib import Path
import datetime, hashlib, json, os, subprocess, time

OUT = Path(__file__).resolve().parent
BASE = OUT.parent
WORK = Path('D:/line3_closeout_20261011_1000_work')
PY = 'D:/666666/Anaconda/python.exe'
FROZEN = 'b4bf9300ac7f499f0c1c72ed3ef28317066f49a5'
CANDIDATE = 'dc9f05fab3b625f962c4b40ffc70e7d4054a21ac'
DATA = Path('D:/cdnet2014_line3_20261010_1700/dataset')

def save(name, value):
    p = OUT / name
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open('x', encoding='utf-8', newline='\n') as f:
        json.dump(value, f, ensure_ascii=False, indent=2)

def digest(p):
    h = hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda: f.read(1024*1024), b''): h.update(b)
    return h.hexdigest()

def run(name, argv, cwd=None, env=None, timeout=3600):
    logs=OUT/'commands'; logs.mkdir(exist_ok=True)
    e=dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8',
           PYTHONDONTWRITEBYTECODE='1', GIT_OPTIONAL_LOCKS='0',
           GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='Never')
    e.update(env or {})
    rec=dict(argv=list(map(str,argv)),cwd=str(cwd or BASE),
             start_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    start=time.monotonic()
    with (logs/(name+'.raw')).open('xb') as f:
        try:
            cp=subprocess.run(rec['argv'],cwd=rec['cwd'],env=e,stdout=f,stderr=subprocess.STDOUT,timeout=timeout)
            rec['exit_code']=cp.returncode
        except subprocess.TimeoutExpired:
            rec.update(exit_code=124,timeout=True)
        except OSError as ex:
            rec.update(exit_code=127,launch_error=str(ex))
    rec['seconds']=round(time.monotonic()-start,3)
    raw=(logs/(name+'.raw')).read_bytes()
    for enc in ('utf-8','gb18030'):
        try: text=raw.decode(enc); rec['encoding']=enc; break
        except UnicodeDecodeError: pass
    else:
        text=raw.decode('utf-8',errors='backslashreplace'); rec['encoding']='escaped undecodable bytes'
    (logs/(name+'.txt')).write_text(text,encoding='utf-8')
    save('commands/'+name+'.json',rec)
    print(name,rec['exit_code'],rec['seconds'],flush=True)
    return rec,text

def protected(name):
    roots=[BASE/'captain_repo',BASE/'audit_claude_20261010_210242',BASE/'audit_astra_20261010_214132']
    rows=[dict(path=p.relative_to(BASE).as_posix(),size=p.stat().st_size,sha256=digest(p))
          for root in roots for p in sorted(root.rglob('*')) if p.is_file()]
    save(name,rows)
    return rows
