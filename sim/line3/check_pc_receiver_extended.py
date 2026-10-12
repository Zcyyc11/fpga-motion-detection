"""Additional receiver checks from the independent Astra audit; board_test remains false."""
from pathlib import Path
import argparse, copy, importlib.util, json
import numpy as np
def packet():
    return dict(version=1,source='simulated',frame_id=123,width=640,height=360,coordinate_space='i3-2x',targets=[dict(id=17,valid=True,x1=37,y1=71,x2=82,y2=99),dict(id=23,valid=True,x1=333,y1=241,x2=400,y2=280)])

def enhanced(source,dest):
    spec=importlib.util.spec_from_file_location('receiver_under_test',source);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
    cases=[]
    def check(name,fn):
        try:fn();cases.append(dict(name=name,pass_=True))
        except Exception as e:cases.append(dict(name=name,pass_=False,error=repr(e)))
    def equal(a,b):
        assert a==b,(a,b)
    def reject(change):
        p=packet();change(p)
        try:m.parse_frame(json.dumps(p).encode())
        except m.ProtocolError:return
        raise AssertionError('invalid packet accepted')
    for name,change in [
        ('wrong height',lambda p:p.update(height=361)),('float height',lambda p:p.update(height=360.0)),
        ('y1 overflow',lambda p:p['targets'][1].update(y1=360,y2=370)),
        ('y2 overflow',lambda p:p['targets'][1].update(y2=360)),
        ('inverted y',lambda p:p['targets'][1].update(y1=282)),
        ('bool coordinate',lambda p:p['targets'][0].update(x1=True)),
        ('second target wrong id',lambda p:p['targets'][1].update(id=256)),
        ('invalid false coordinates still checked',lambda p:p['targets'][1].update(valid=False,y2=360)),
        ('duplicate id',lambda p:p['targets'][1].update(id=17)),
        ('wrong source',lambda p:p.update(source='board-unverified'))]:check(name,lambda change=change:reject(change))
    for name,target_list in [('asymmetric two targets',packet()['targets']),('single pixel corners',[dict(id=1,valid=True,x1=0,y1=0,x2=0,y2=0),dict(id=2,valid=True,x1=639,y1=359,x2=639,y2=359)]),('valid false',[dict(id=3,valid=False,x1=21,y1=24,x2=63,y2=75)])]:
        def geometry(target_list=target_list):
            p=packet();p['targets']=copy.deepcopy(target_list);before=copy.deepcopy(p);calls=[]
            original=m.cv2.rectangle
            def spy(img,p1,p2,color,thickness,*args,**kwargs):
                calls.append((p1,p2,color,thickness));return original(img,p1,p2,color,thickness,*args,**kwargs)
            m.cv2.rectangle=spy
            try:img=m.render(p)
            finally:m.cv2.rectangle=original
            expected=[((2*t['x1'],48+2*t['y1']),(2*t['x2']+1,49+2*t['y2']),(90,210,120),2) for t in target_list if t['valid']]
            equal([c for c in calls if c[2]==(90,210,120)],expected)
            equal(p,before);equal(img.shape,(768,1280,3))
            for t in target_list:
                if t['valid']:
                    equal(tuple(int(x) for x in img[48+2*t['y2'],2*t['x2']]),(90,210,120))
        check(name,geometry)
    def stream():
        packets=[]
        for i in [9,10,10,7,13]:p=packet();p['frame_id']=i;packets.append(p)
        raw=b''.join(json.dumps(p).encode()+b'\n' for p in packets)
        s=m.receive([raw[i:i+7] for i in range(0,len(raw),7)],dest/'stream')
        equal((s['accepted'],s['rejected'],s['missing_frames'],s['last_frame'],s['exit_code']),(3,2,2,13,1))
    check('fragmented sequence duplicates gaps',stream)
    def board():
        p=packet();p['source']='board-unverified';s=m.receive([json.dumps(p).encode()+b'\n'],dest/'board',expected_source='board-unverified')
        equal((s['accepted'],s['board_test'],s['protocol_status']),(1,False,'proposal-not-agreed'))
    check('source label cannot prove board test',board)
    return cases

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args()
    args.out.mkdir(parents=True,exist_ok=False)
    tests=enhanced(Path(__file__).with_name('pc_receiver.py'),args.out)
    result=dict(passed=sum(t['pass_'] for t in tests),total=len(tests),tests=tests,board_test=False)
    (args.out/'tests.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result,indent=2))
    raise SystemExit(0 if result['passed']==result['total'] else 1)
