"""Validate the delivered line3 evidence and optionally make a scoped overlay ZIP."""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import zipfile
from compare import compare, read_csv

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT/'report/line3_20261009'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--zip',type=Path)
    a=ap.parse_args()
    if a.out.exists() or (a.zip and a.zip.exists()):
        ap.error('Refusing to overwrite delivery evidence')
    checks=[]
    def check(name, ok, details=None):
        checks.append(dict(name=name,passed=bool(ok),details=details))
    def read(rel):
        return json.loads((REPORT/rel).read_text(encoding='utf-8'))
    manifest=read('run_ead15e0_01/manifest.json')
    changed=[p for p,h in manifest['protected_sha256_before'].items() if sha(ROOT/p)!=h]
    check('124_baseline_files_unchanged',len(manifest['protected_sha256_before'])==124 and not changed,changed)
    tools=read('tool_acceptance_02/acceptance.json')
    check('18_tool_checks',len(tools)==18 and all(r['passed'] for r in tools))
    for prefix in ['run_ead15e0_01','tool_acceptance_02/software_rerun']:
        r=read(prefix+'/results.json')
        check(prefix+'_cases',sum(c['status']=='FAIL' for c in r['cases'])==5 and len(r['cases'])==25)
        for mode, hits in [('clean',210),('algo',186)]:
            v=r[mode]
            check(prefix+'_'+mode,v['matched_visible']==hits and v['truth_visible']==210 and
                  v['false_boxes']==v['id_switches']==v['track_breaks']==0 and
                  v['video']['decoded_frames']==120 and v['observer_video_equal'])
    for rtl,media in [('rtl_fd03','media_fd03'),('rtl_bg01','media_bg01')]:
        r=read(rtl+'/result.json')
        check(rtl+'_model',r['pass'] and r['csv_rows']==12 and not compare(REPORT/rtl/'expected.csv',REPORT/rtl/'bbox_rtl.csv'))
        check(rtl+'_frame_set',[int(x['frame']) for x in read_csv(REPORT/rtl/'bbox_rtl.csv')[1]]==list(range(12)))
        ppms=list((REPORT/rtl/'wave').glob('*.ppm'))
        check(rtl+'_portable_ppm',len(ppms)==24 and all(sha(p)==r['files'][p.name] for p in ppms))
        m=read(media+'/details.json')
        check(media,m['rtl_pass'] and len(m['rtl_overlay'])==12)
    files=sorted(set([*ROOT.glob('sim/line3/*.py'),ROOT/'docs/line3_run.md',
                      *[p for p in REPORT.rglob('*') if p.is_file()],
                      ROOT/'skill/line3_strict_evidence/README.md']))
    encoding_errors=[]
    broken=[]
    for p in files:
        if p.suffix in ['.py','.md','.json','.csv','.txt','.log','.bat']:
            try:
                s=p.read_text(encoding='utf-8-sig')
                if '\ufffd' in s:
                    encoding_errors.append(str(p.relative_to(ROOT)))
                if p.suffix=='.py':
                    ast.parse(s)
                if p.suffix=='.md':
                    for link in re.findall(r'\[[^\]]*\]\(([^)]+)\)',s):
                        if '://' not in link and not link.startswith('#') and not (p.parent/link.split('#')[0]).exists():
                            broken.append([str(p.relative_to(ROOT)),link])
            except (UnicodeError,SyntaxError) as e:
                encoding_errors.append([str(p.relative_to(ROOT)),str(e)])
    check('utf8_and_python_syntax',not encoding_errors,encoding_errors)
    check('markdown_links',not broken,broken)
    draft=(REPORT/'report_draft.md').read_text(encoding='utf-8')
    check('nine_report_chapters',re.findall(r'^## (\d+)\.',draft,re.M)==list(map(str,range(1,10))))
    check('new_paths_ascii',all(str(p.relative_to(ROOT)).isascii() for p in files))
    result=dict(checks=checks,passed=all(r['passed'] for r in checks),
                files={p.relative_to(ROOT).as_posix():sha(p) for p in files},
                scope='Line3 overlay only; baseline ead15e0 source required; no board or full CDnet claim')
    a.out.parent.mkdir(parents=True,exist_ok=True)
    a.out.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    if a.zip and result['passed']:
        a.zip.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(a.zip,'x',compression=zipfile.ZIP_DEFLATED) as z:
            for p in files:
                z.write(p,p.relative_to(ROOT).as_posix())
            z.writestr('delivery_validation.json',a.out.read_bytes())
        with zipfile.ZipFile(a.zip) as z:
            assert z.testzip() is None
            for p in files:
                assert hashlib.sha256(z.read(p.relative_to(ROOT).as_posix())).hexdigest()==sha(p)
        receipt=dict(zip=os.path.abspath(a.zip),sha256=sha(a.zip),entries=len(files)+1,crc_pass=True,byte_match=True)
        a.zip.with_suffix('.receipt.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
        print(json.dumps(receipt))
    print(json.dumps(dict(passed=result['passed'],checks=len(checks),failed=[r['name'] for r in checks if not r['passed']])))
    return 0 if result['passed'] else 2


if __name__=='__main__':
    raise SystemExit(main())
