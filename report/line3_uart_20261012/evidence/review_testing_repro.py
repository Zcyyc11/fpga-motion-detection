"""Independent read-only UART review; every input is simulated."""
import hashlib
import json
from pathlib import Path
import random
import shutil
import struct
import subprocess
import sys

WORK = Path('D:/line3_uart_20261012/work')
ROOT = Path('D:/line3_uart_20261012/review_testing')
sys.path.insert(0, str(WORK / 'sim/line3'))
import uart_receiver as rx
import verify_uart_capture as verifier
from uart_protocol import Decoder, Frames

results = []
observations = []

def record(name, condition, detail=None):
    results.append({'name': name, 'pass': bool(condition), 'detail': detail})

def write_jsonl(path, rows):
    path.write_text(''.join(json.dumps(x, ensure_ascii=False) + '\n' for x in rows), encoding='utf-8')

def compare(capture, wanted, name):
    result = verifier.verify(capture, wanted)
    (ROOT / (name + '.json')).write_text(json.dumps(result, indent=2), encoding='utf-8')
    return result

def body_packet(body):
    return body + bytes([sum(body) & 255])

def strip_frame(f):
    return {'frame_id': f['frame_id'],
            'targets': [{k: t[k] for k in ('id', 'x1', 'y1', 'x2', 'y2', 'flags')} for t in f['targets']],
            'events': [{k: e[k] for k in ('id', 'type', 'center_x')} for e in f['events']]}

# Independently recorded bytes and expected numeric values, not decoder-generated gold.
raw = bytes.fromhex('5a341201a1 a53412070a0014001e0028000056 c334120701140025')
expected = [{'frame_id': 4660,
             'targets': [{'id': 7, 'x1': 10, 'y1': 20, 'x2': 30, 'y2': 40, 'flags': 0}],
             'events': [{'id': 7, 'type': 1, 'center_x': 20}],
             'input_frame_ref': 'SIMULATED independent hex fixture / frame 4660'}]
expected_path = ROOT / 'independent_reference.jsonl'
write_jsonl(expected_path, expected)
baseline = ROOT / 'independent_baseline'
stats = rx.receive([raw], baseline, source='simulated', save_images=0)
actual = verifier.load_jsonl(baseline / 'frames.jsonl')
record('all decoded fields match independent literal table', strip_frame(actual[0]) == {k: v for k, v in expected[0].items() if k != 'input_frame_ref'})
record('verifier accepts independently specified exact table', compare(baseline, expected_path, 'verify_clean')['exit_code'] == 0)

for field in ['id', 'x1', 'y1', 'x2', 'y2', 'flags']:
    changed = json.loads(json.dumps(expected))
    changed[0]['targets'][0][field] += 1
    path = ROOT / ('reference_changed_' + field + '.jsonl')
    write_jsonl(path, changed)
    record('verifier rejects changed target ' + field, compare(baseline, path, 'verify_target_' + field)['exit_code'] != 0)
for field in ['id', 'type', 'center_x']:
    changed = json.loads(json.dumps(expected))
    changed[0]['events'][0][field] += 1
    path = ROOT / ('reference_changed_event_' + field + '.jsonl')
    write_jsonl(path, changed)
    record('verifier rejects changed event ' + field, compare(baseline, path, 'verify_event_' + field)['exit_code'] != 0)

changed = json.loads(json.dumps(expected))
changed[0].pop('input_frame_ref')
path = ROOT / 'reference_missing_mapping.jsonl'
write_jsonl(path, changed)
proc = subprocess.run([sys.executable, '-X', 'utf8', str(WORK / 'sim/line3/verify_uart_capture.py'),
                       '--capture', str(baseline), '--expected', str(path), '--out', str(ROOT / 'verify_missing_mapping.json')], capture_output=True, text=True, encoding='utf-8')
(ROOT / 'verify_missing_mapping.stdout.txt').write_text(proc.stdout, encoding='utf-8')
(ROOT / 'verify_missing_mapping.stderr.txt').write_text(proc.stderr, encoding='utf-8')
record('verifier CLI rejects absent mapping and saves diagnostic', proc.returncode == 1 and 'input_frame_ref' in proc.stdout)

mutated_raw = ROOT / 'raw_changed'
shutil.copytree(baseline, mutated_raw)
(mutated_raw / 'raw_stream.bin').write_bytes(raw + b'\x00')
record('verifier rejects raw hash mismatch', compare(mutated_raw, expected_path, 'verify_raw_changed')['exit_code'] != 0)

# Capture mixing: this frame table/reference says x1=11, original raw still says x1=10.
mixed = ROOT / 'mixed_frame_table'
shutil.copytree(baseline, mixed)
mixed_rows = json.loads(json.dumps(actual))
mixed_rows[0]['targets'][0]['x1'] = 11
write_jsonl(mixed / 'frames.jsonl', mixed_rows)
mixed_expected = json.loads(json.dumps(expected))
mixed_expected[0]['targets'][0]['x1'] = 11
mixed_expected_path = ROOT / 'reference_for_mixed_table.jsonl'
write_jsonl(mixed_expected_path, mixed_expected)
mixed_result = compare(mixed, mixed_expected_path, 'verify_mixed_table')
observations.append({'name': 'raw/frame-table linkage', 'raw_decoded_x1': 10, 'frame_table_x1': 11, 'reference_x1': 11,
                     'result': mixed_result, 'raw_hash_unchanged': hashlib.sha256((mixed / 'raw_stream.bin').read_bytes()).hexdigest() == stats['raw_sha256']})

# Vary every numeric field and packet ordering; independent expected values are
# constructed before bytes, and only the actual path calls the production decoder.
rng = random.Random(20261012)
for case in range(8):
    rows, pieces = [], []
    for fid in [65534, 65535, 0, 1]:
        count = rng.randrange(17)
        row = {'frame_id': fid, 'targets': [], 'events': []}
        pieces.append(body_packet(struct.pack('<BHB', 0x5A, fid, count)))
        for identity in rng.sample(range(256), count):
            x1, y1 = rng.randrange(640), rng.randrange(360)
            x2, y2 = rng.randrange(x1, 640), rng.randrange(y1, 360)
            t = dict(id=identity, x1=x1, y1=y1, x2=x2, y2=y2, flags=0)
            row['targets'].append(t)
            pieces.append(body_packet(struct.pack('<BHBHHHHB', 0xA5, fid, identity, x1, y1, x2, y2, 0)))
            if rng.randrange(3) == 0:
                e = dict(id=identity, type=rng.choice([1, 2]), center_x=rng.randrange(640))
                row['events'].append(e)
                pieces.append(body_packet(struct.pack('<BHBBH', 0xC3, fid, identity, e['type'], e['center_x'])))
        rows.append(row)
    stream = b''.join(pieces)
    frames, errors = [], []
    assembler = Frames(frames.append, lambda _: None, errors.append)
    decoder = Decoder(assembler.accept, assembler.error)
    position = 0
    while position < len(stream):
        size = rng.randrange(1, 31)
        decoder.feed(stream[position:position+size])
        position += size
    decoder.feed(final=True)
    assembler.finish()
    record('independent mixed fields fragmentation seed case ' + str(case), not errors and [strip_frame(f) for f in frames] == rows,
           {'bytes': len(stream), 'frames': len(frames), 'errors': errors})

source_hashes = {str(p.relative_to(WORK)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (WORK / 'sim/line3').glob('*uart*.py')}
report = {'board_test': False, 'source': 'SIMULATED', 'tests': results, 'passed': sum(r['pass'] for r in results), 'total': len(results),
          'observations': observations, 'source_sha256': source_hashes}
(ROOT / 'independent_results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(any(not r['pass'] for r in results))
