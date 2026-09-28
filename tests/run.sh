#!/usr/bin/env bash
# Run every *.test.sh in a directory (default: this one) and report TAP.
#
#   tests/run.sh [dir]
#
# Exit 0 when every test passed, 1 when any failed, 2 when none ran. A suite
# that ran nothing has measured nothing, so it is never reported as a pass.
#
# Each test_* function runs in its own subshell under `set -e`, called as a
# plain command. It is never wrapped in `if` or `||`, because bash disables
# errexit inside a subshell whose status is being tested, and a test that
# fails halfway would then report success.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dir=${1:-$here}
lib=$here/lib.sh
n=0 failed=0
log=$(mktemp); trap 'rm -f "$log"' EXIT
shopt -s nullglob

for f in "$dir"/*.test.sh; do
    name=$(basename "$f" .test.sh)
    if ! bash -n "$f" 2>"$log"; then
        n=$((n + 1)) failed=$((failed + 1))
        printf 'not ok %d - %s: file does not parse\n' "$n" "$name"
        sed 's/^/    # /' "$log"
        continue
    fi
    fns=$(bash -c 'source "$1"; source "$2"; declare -F' _ "$lib" "$f" 2>/dev/null \
        | awk '$3 ~ /^test_/ {print $3}')
    for fn in $fns; do
        n=$((n + 1))
        ( set -e; source "$lib"; source "$f"; "$fn" ) >"$log" 2>&1
        rc=$?
        if [ "$rc" -eq 0 ]; then
            printf 'ok %d - %s: %s\n' "$n" "$name" "$fn"
        else
            failed=$((failed + 1))
            printf 'not ok %d - %s: %s (exit %d)\n' "$n" "$name" "$fn" "$rc"
            sed 's/^/    # /' "$log"
        fi
    done
done

printf '1..%d\n' "$n"
if [ "$n" -eq 0 ]; then
    printf '# ran 0 tests in %s: unmeasured\n' "$dir"
    exit 2
fi
printf '# ran %d, failed %d\n' "$n" "$failed"
[ "$failed" -eq 0 ]
