#!/usr/bin/env python3
"""Rebuild report.html from occupancy.csv.

Everything on the page (headline figures, annotations, axis range, day
dividers) is derived from the data at render time, so this script never
needs editing as readings accumulate.

Usage: python3 build-report.py
"""
import csv, json, collections, datetime, os

HERE = os.path.dirname(os.path.abspath(__file__))

rows = list(csv.DictReader(open(os.path.join(HERE, 'occupancy.csv'))))
dates = sorted({r['date'] for r in rows})
# Days since the first reading -- NOT a dense 0,1,2 index. A day with no
# readings (logger down) must stay a real gap on the axis, not be collapsed.
_d0 = datetime.date.fromisoformat(dates[0])
day_index = {d: (datetime.date.fromisoformat(d) - _d0).days for d in dates}

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

# ---- estimated fill for logger outages -------------------------------------
# Displayed as a dashed red line and NEVER written to occupancy.csv: the CSV
# stays measurement-only. Each gap is filled from the average shape of the same
# time-of-day on days we did measure, then offset linearly so the estimate
# meets the real readings at both ends instead of stepping at the joins.
SLOT = 10                      # minutes per estimated sample
GAP_MIN = 20                   # gaps longer than this get an estimate

profile = collections.defaultdict(list)
for pt in points:
    profile[pt['m'] % 1440 // SLOT * SLOT].append(pt['v'])
profile = {k: sum(v) / len(v) for k, v in profile.items()}

def shape(minute_of_day):
    """Typical value at this time of day, or None if never observed."""
    k = minute_of_day % 1440 // SLOT * SLOT
    for d in range(0, 1440, SLOT):                 # nearest observed slot
        for c in (k - d, k + d):
            v = profile.get(c % 1440)
            if v is not None:
                return v
    return None

segments = []
for a, b in zip(points, points[1:]):
    span = b['m'] - a['m']
    if span <= GAP_MIN:
        continue
    inner = list(range(a['m'] + SLOT, b['m'], SLOT))
    if not inner:
        continue
    sa, sb = shape(a['m']), shape(b['m'])
    seg = [{'m': a['m'], 'v': a['v'], 'real': True}]
    for m in inner:
        base = shape(m)
        if base is None or sa is None or sb is None:
            f = (m - a['m']) / span                # nothing to model on
            est = a['v'] + (b['v'] - a['v']) * f
        else:
            f = (m - a['m']) / span                # blend the endpoint offsets
            corr = (a['v'] - sa) * (1 - f) + (b['v'] - sb) * f
            est = base + corr
        seg.append({'m': m, 'v': max(0, round(est, 1))})
    seg.append({'m': b['m'], 'v': b['v'], 'real': True})
    segments.append({'pts': seg, 'mins': span})

data = json.dumps({'points': points, 'hourly': hourly, 'estimates': segments},
                  separators=(',', ':'))

tpl = open(os.path.join(HERE, 'report-template.html')).read()
assert '__DATA__' in tpl, 'template lost its __DATA__ placeholder'
out = os.path.join(HERE, 'report.html')
open(out, 'w').write(tpl.replace('__DATA__', data))

print(f'{out}: {len(points)} readings, '
      f'{points[0]["w"]} {points[0]["t"]} -> {points[-1]["w"]} {points[-1]["t"]}')
