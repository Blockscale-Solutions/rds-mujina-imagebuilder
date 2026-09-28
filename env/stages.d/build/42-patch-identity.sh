#!/usr/bin/env bash
# Each kernel we built carries exactly the committed patches (#51, T2).
. "$(dirname "$0")/../../lib.sh"
shopt -s nullglob
trees=("$RDS_PROJECT"/build/br-out/*/build/linux-[0-9]*/)
[ ${#trees[@]} -gt 0 ] || { echo "no built kernel trees: unmeasured"; exit 2; }
exec "$RDS_REPO/tools/patch-identity" "${trees[@]}"
