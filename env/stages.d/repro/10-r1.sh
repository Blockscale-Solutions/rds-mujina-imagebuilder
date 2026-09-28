#!/usr/bin/env bash
# R1 (#45): assemble the images twice from the same built tree; every artifact
# and every file inside the squashfs must match. On a difference, both
# manifests and the comparison are kept under data/build-evidence/.
. "$(dirname "$0")/../../lib.sh"
v=rds_control out=$RDS_PROJECT/build/br-out/$v
[ -d "$out/target" ] || { echo "no built $v tree: unmeasured (run env/rds build)"; exit 2; }
RDS_R1_PLANT=0 "$RDS_REPO/env/container.sh" br $v assemble:A || exit 1
"$RDS_REPO/env/container.sh" br $v assemble:B || exit 1
res=$("$RDS_REPO/tools/repro-compare" --allowed "$RDS_REPO/repro/allowed-differences.tsv" "$out/manifest-A.tsv" "$out/manifest-B.tsv"); rc=$?
echo "$res" | tail -25
if [ $rc -ne 0 ]; then
    ev=$RDS_PROJECT/data/build-evidence/r1-$(date -u +%Y%m%dT%H%M%SZ)
    mkdir -p "$ev"; cp "$out/manifest-A.tsv" "$out/manifest-B.tsv" "$ev/"; echo "$res" > "$ev/compare.txt"
    echo "evidence kept: $ev"
fi
exit $rc
