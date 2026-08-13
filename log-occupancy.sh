#!/bin/bash
# Logs Lemon Gym Raudondvaris occupancy to occupancy.csv
# Timestamps are ALWAYS Europe/Vilnius, so local and cloud runs stay consistent.
# Usage: ./log-occupancy.sh

set -euo pipefail
export TZ="Europe/Vilnius"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV="$DIR/occupancy.csv"
URL="https://www.lemongym.lt/wp-json/api/async-render-block?pid=NTY3&bid=YWNmL2NsdWJzLW9jY3VwYW5jeQ==&rest_language=en"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

[ -f "$CSV" ] || echo "date,time,weekday,club,occupancy_percent" > "$CSV"

if ! PCT=$(curl -sf --compressed --max-time 30 -A "$UA" "$URL" | python3 -c "
import sys, json, re
try:
    content = json.load(sys.stdin)['data']['content']
except Exception:
    sys.exit(1)
m = re.search(r'Raudondvaris.*?percentage[^>]*>\s*(\d+)%', content, re.S)
if not m:
    sys.exit(1)
print(m.group(1))
"); then
    echo "$(date '+%Y-%m-%d %H:%M') FETCH FAILED - nothing logged" >&2
    exit 1
fi

echo "$(date '+%Y-%m-%d'),$(date '+%H:%M'),$(date '+%a'),Raudondvaris,$PCT" >> "$CSV"
echo "$(date '+%Y-%m-%d %H:%M') Raudondvaris ${PCT}%"
