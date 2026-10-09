"""Strict, order-independent CSV comparison; no intersection-only success."""
import argparse
import csv
import json
from pathlib import Path


def read_csv(path):
    with Path(path).open(encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        fields = reader.fieldnames
        rows = list(reader)
    if not fields or len(set(fields)) != len(fields):
        raise ValueError('Missing or duplicate header: ' + str(path))
    if any(None in row or any(v is None for v in row.values()) for row in rows):
        raise ValueError('Malformed CSV row: ' + str(path))
    return fields, rows


def compare(expected, actual, keys=('frame',)):
    ef, er = read_csv(expected)
    af, ar = read_csv(actual)
    differences = []
    if set(ef) != set(af):
        return [dict(kind='schema', key='', field='', expected=ef, actual=af)]
    if not set(keys) <= set(ef):
        raise ValueError('Key absent from header')
    maps = []
    for name, rows in [('expected', er), ('actual', ar)]:
        index = {}
        for line, row in enumerate(rows, 2):
            key = tuple(row[k] for k in keys)
            if key in index:
                differences.append(dict(kind='duplicate_' + name, key=key,
                                        field='', expected='unique', actual=line))
            index[key] = row
        maps.append(index)
    em, am = maps
    for key in sorted(em.keys() | am.keys()):
        if key not in em or key not in am:
            differences.append(dict(kind='unexpected' if key not in em else 'missing',
                                    key=key, field='', expected=em.get(key), actual=am.get(key)))
        else:
            for field in ef:
                if em[key][field] != am[key][field]:
                    differences.append(dict(kind='value', key=key, field=field,
                                            expected=em[key][field], actual=am[key][field]))
    return differences


def write_csv(path, fields, rows):
    with Path(path).open('w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('expected', type=Path)
    parser.add_argument('actual', type=Path)
    parser.add_argument('--keys', default='frame')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        parser.error('Output exists; use a new path')
    try:
        diffs = compare(args.expected, args.actual, tuple(args.keys.split(',')))
    except (ValueError, OSError) as exc:
        diffs = [dict(kind='invalid_input', error=str(exc))]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(diffs, ensure_ascii=False, indent=2), encoding='utf-8')
    print('PASS' if not diffs else 'FAIL', len(diffs), args.out)
    return 0 if not diffs else 2


if __name__ == '__main__':
    raise SystemExit(main())
