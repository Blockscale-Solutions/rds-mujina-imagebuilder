#!/usr/bin/env bash
# Every locked input is in the mirror, named by and matching its sha256.
. "$(dirname "$0")/../../lib.sh"
[ -f "$RDS_LOCK" ] || { echo "no lock at $RDS_LOCK: unmeasured (the fetch stage, #35, creates it)"; exit 2; }
# Nothing fetched yet (a fresh clone) is unmeasured too; a mirror that exists
# but lacks or corrupts an entry fails below.
[ -d "$RDS_MIRROR" ] || { echo "no mirror at $RDS_MIRROR yet: unmeasured (env/rds fetch creates it)"; exit 2; }
n=0 bad=0
while IFS=$'\t' read -r h bytes name url; do
    case "$h" in ''|\#*) continue ;; esac
    n=$((n + 1)) f="$RDS_MIRROR/$h"
    if [ ! -f "$f" ]; then echo "MISSING $name ($h)"; bad=$((bad + 1)); continue; fi
    if [ "$(sha256sum < "$f" | cut -d' ' -f1)" != "$h" ]; then echo "CORRUPT $name ($h)"; bad=$((bad + 1)); fi
done < "$RDS_LOCK"
[ "$n" -gt 0 ] || { echo "lock has no entries: unmeasured"; exit 2; }
echo "$((n - bad)) of $n locked inputs present and matching"
[ "$bad" -eq 0 ]
