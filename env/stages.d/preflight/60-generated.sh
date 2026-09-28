#!/usr/bin/env bash
# Every generated file equals its regeneration: a hand edit fails here.
. "$(dirname "$0")/../../lib.sh"
[ -f "$RDS_GENERATED" ] || { echo "no generated-file registry at $RDS_GENERATED: unmeasured"; exit 2; }
n=0 bad=0
while IFS=$'\t' read -r path cmd; do
    case "$path" in ''|\#*) continue ;; esac
    n=$((n + 1))
    if ! diff -q <(cd "$RDS_REPO" && bash -c "$cmd") "$path" >/dev/null 2>&1; then echo "DRIFT $path differs from: $cmd"; bad=$((bad + 1)); fi
done < "$RDS_GENERATED"
[ "$n" -gt 0 ] || { echo "no generated files registered yet: unmeasured"; exit 2; }
echo "$((n - bad)) of $n generated files match their regeneration"
[ "$bad" -eq 0 ]
