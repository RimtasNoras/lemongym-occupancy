#!/bin/bash
# Logs Lemon Gym Raudondvaris occupancy to a CSV.
#
# Timestamps are ALWAYS Europe/Vilnius, so local and cloud runs stay consistent.
# Transient network failures (DNS not up after a wake, timeouts) are retried
# before giving up -- launchd fires this the moment the Mac wakes, often before
# the network has settled, and a single attempt loses the reading.
# On final failure it prints a diagnosis to stderr and exits non-zero WITHOUT
# writing a row: a gap is correct, a guessed value is not.
#
# Usage: ./log-occupancy.sh [output.csv]

set -uo pipefail
export TZ="Europe/Vilnius"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV="${1:-$DIR/occupancy.csv}"
URL="https://www.lemongym.lt/wp-json/api/async-render-block?pid=NTY3&bid=YWNmL2NsdWJzLW9jY3VwYW5jeQ==&rest_language=en"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

ATTEMPTS=4
BACKOFF=(0 15 45 90)   # seconds to wait before attempt N

stamp() { date '+%Y-%m-%d %H:%M'; }
fail()  { echo "$(stamp) FETCH FAILED - $1 - nothing logged" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || fail "curl not installed"

BODY=$(mktemp)
trap 'rm -f "$BODY"' EXIT

PCT=""
LAST=""
for ((i = 0; i < ATTEMPTS; i++)); do
    (( BACKOFF[i] > 0 )) && sleep "${BACKOFF[i]}"

    HTTP=$(curl -s --compressed --max-time 45 -A "$UA" -o "$BODY" -w '%{http_code}' "$URL")
    RC=$?

    if [ "$RC" -ne 0 ]; then
        LAST="curl exit $RC (6=DNS 7=refused 28=timeout 35=TLS 60=cert)"
        # 6/7/28/35 are transient after a wake; anything else won't fix itself
        case "$RC" in 6|7|28|35) continue ;; *) break ;; esac
    fi
    if [ "$HTTP" != "200" ]; then
        LAST="HTTP $HTTP"
        continue
    fi

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

    if [ $? -eq 0 ] && [ -n "$PCT" ]; then
        [ "$i" -gt 0 ] && echo "$(stamp) recovered on attempt $((i+1))" >&2
        break
    fi
    LAST="$(cat /tmp/occ_err 2>/dev/null || echo 'parse failed')"
    PCT=""
    break   # markup problems are not transient
done

[ -n "$PCT" ] || fail "${LAST:-unknown error} (after $ATTEMPTS attempts)"

[ -f "$CSV" ] || echo "date,time,weekday,club,occupancy_percent" > "$CSV"
echo "$(date '+%Y-%m-%d'),$(date '+%H:%M'),$(date '+%a'),Raudondvaris,$PCT" >> "$CSV"
echo "$(stamp) Raudondvaris ${PCT}%"
