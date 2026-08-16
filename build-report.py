#!/usr/bin/env python3
"""Rebuild report.html from occupancy.csv.

Everything on the page (headline figures, annotations, axis range, day
dividers) is derived from the data at render time, so this script never
needs editing as readings accumulate.

Usage: python3 build-report.py
"""
import csv, json, collections, os

HERE = os.path.dirname(os.path.abspath(__file__))

rows = list(csv.DictReader(open(os.path.join(HERE, 'occupancy.csv'))))
dates = sorted({r['date'] for r in rows})
day_index = {d: i for i, d in enumerate(dates)}

points = []
for r in rows:
    hh, mm = r['time'].split(':')
    points.append({
        'm': day_index[r['date']] * 1440 + int(hh) * 60 + int(mm),
        'v': int(r['occupancy_percent']),
        'd': r['date'], 't': r['time'], 'w': r['weekday'],
    })

buckets = collections.defaultdict(list)
for p in points:
    buckets[p['m'] // 60 * 60].append(p['v'])
hourly = [{'m': k, 'avg': round(sum(v) / len(v), 1), 'n': len(v),
           'min': min(v), 'max': max(v)} for k, v in sorted(buckets.items())]

data = json.dumps({'points': points, 'hourly': hourly}, separators=(',', ':'))

tpl = open(os.path.join(HERE, 'report-template.html')).read()
assert '__DATA__' in tpl, 'template lost its __DATA__ placeholder'
out = os.path.join(HERE, 'report.html')
open(out, 'w').write(tpl.replace('__DATA__', data))

print(f'{out}: {len(points)} readings, '
      f'{points[0]["w"]} {points[0]["t"]} -> {points[-1]["w"]} {points[-1]["t"]}')
