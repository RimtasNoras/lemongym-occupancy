#!/bin/bash
# Logs Lemon Gym Raudondvaris occupancy to occupancy.csv
# Timestamps are ALWAYS Europe/Vilnius, so local and cloud runs stay consistent.
# On failure it prints a diagnosis to stderr and exits non-zero WITHOUT writing a row.
# Usage: ./log-occupancy.sh

set -uo pipefail
export TZ="Europe/Vilnius"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV="$DIR/occupancy.csv"
URL="https://www.lemongym.lt/wp-json/api/async-render-block?pid=NTY3&bid=YWNmL2NsdWJzLW9jY3VwYW5jeQ==&rest_language=en"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

fail() { echo "$(date '+%Y-%m-%d %H:%M') FETCH FAILED - $1 - nothing logged" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || fail "curl not installed"

BODY=$(mktemp)
trap 'rm -f "$BODY"' EXIT

HTTP=$(curl -s --compressed --max-time 30 -A "$UA" -o "$BODY" -w '%{http_code}' "$URL")
CURL_RC=$?

[ "$CURL_RC" -eq 0 ] || fail "curl exit $CURL_RC (6=DNS 7=refused 28=timeout 35=TLS 60=cert)"
[ "$HTTP" = "200" ] || fail "HTTP $HTTP"

PCT=$(python3 -c "
import sys, json, re
raw = open(sys.argv[1], encoding='utf-8', errors='replace').read()
try:
    content = json.loads(raw)['data']['content']
except Exception as e:
    sys.stderr.write('unparseable JSON (%s); first 200 bytes: %r' % (type(e).__name__, raw[:200]))
    sys.exit(2)
m = re.search(r'Raudondvaris.*?percentage[^>]*>\s*(\d+)%', content, re.S)
if not m:
    sys.stderr.write('Raudondvaris block not found - site markup may have changed')
    sys.exit(3)
print(m.group(1))
" "$BODY" 2>/tmp/occ_err)
PY_RC=$?

[ "$PY_RC" -eq 0 ] || fail "$(cat /tmp/occ_err 2>/dev/null || echo "python3 exit $PY_RC")"

[ -f "$CSV" ] || echo "date,time,weekday,club,occupancy_percent" > "$CSV"
echo "$(date '+%Y-%m-%d'),$(date '+%H:%M'),$(date '+%a'),Raudondvaris,$PCT" >> "$CSV"
echo "$(date '+%Y-%m-%d %H:%M') Raudondvaris ${PCT}%"
