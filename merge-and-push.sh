#!/bin/bash
# Folds the local launchd readings (occupancy-local.csv) into the shared
# occupancy.csv that GitHub Actions also writes to, then pushes.
#
# The two loggers deliberately write to DIFFERENT files: launchd appends
# locally every 10 min, Actions commits remotely a few times an hour. If both
# appended to occupancy.csv directly, every pull would conflict. This runs
# hourly, unions the two on timestamp, and pushes one tidy commit.
#
# Safe to run any time; a no-op when there is nothing new.

set -uo pipefail
export TZ="Europe/Vilnius"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1

LOCAL="$DIR/occupancy-local.csv"
SHARED="$DIR/occupancy.csv"

stamp() { date '+%Y-%m-%d %H:%M'; }

[ -f "$LOCAL" ] || { echo "$(stamp) merge: no local readings yet"; exit 0; }

# Get the latest cloud readings first. If we are offline, stop cleanly -
# the local file keeps accumulating and the next run will catch up.
if ! git pull --rebase --quiet origin main 2>/dev/null; then
    echo "$(stamp) merge: pull failed (offline?), will retry next run" >&2
    exit 0
fi

python3 - "$LOCAL" "$SHARED" <<'PY'
import csv, sys
local, shared = sys.argv[1], sys.argv[2]
rows = {}
for f in (shared, local):                      # local wins ties; values match anyway
    try:
        for r in csv.DictReader(open(f)):
            rows[(r['date'], r['time'])] = r
    except FileNotFoundError:
        pass
merged = [rows[k] for k in sorted(rows)]
with open(shared, 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=['date','time','weekday','club','occupancy_percent'])
    w.writeheader()
    w.writerows(merged)
print(len(merged))
PY

# Rebuild the report so the dashed estimates are recomputed against the
# newly-merged data: gaps shrink as real readings arrive, and the time-of-day
# model behind each estimate improves with every extra day observed.
python3 "$DIR/build-report.py" >/dev/null 2>&1 || echo "$(stamp) merge: report rebuild failed" >&2

git add "$SHARED" "$DIR/report.html"
if git diff --cached --quiet; then
    echo "$(stamp) merge: nothing new"
    exit 0
fi

git commit -q -m "Local readings through $(stamp)"
for i in 1 2 3; do
    git pull --rebase --quiet origin main && git push --quiet origin main && {
        echo "$(stamp) merge: pushed $(( $(wc -l < "$SHARED") - 1 )) total readings"
        exit 0
    }
    sleep 5
done
echo "$(stamp) merge: push failed after 3 attempts" >&2
exit 1
