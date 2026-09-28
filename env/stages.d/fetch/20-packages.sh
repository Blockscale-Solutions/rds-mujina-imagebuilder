#!/usr/bin/env bash
# S1, packages: download every variant's sources (network), lock them by the
# bytes received, mirror them by hash, and prove the kernel's hash from
# kernel.org's signed list (#35, #36). Pinned rows (no '/') are kept as they are.
. "$(dirname "$0")/../../lib.sh"
net=$RDS_PROJECT/build/dl-net
for v in $(rds_variants); do
    RDS_DL=$net "$RDS_REPO/env/container.sh" br "$v" source net || { echo "FAIL source $v"; exit 1; }
done
rows=$(mktemp)
"$RDS_REPO/tools/lock-gen" --dl "$net" $(for v in $(rds_variants); do echo "$RDS_PROJECT/build/br-out/$v/show-info.json"; done) > "$rows" || exit 1
new=$(mktemp)
{ grep -v -P '^[0-9a-f]{64}\t\d+\t[^\t/]*/' "$RDS_LOCK"; cat "$rows"; } > "$new"
mv "$new" "$RDS_LOCK"
while IFS=$'\t' read -r h size name url; do
    [ -f "$RDS_MIRROR/$h" ] || cp "$net/$name" "$RDS_MIRROR/$h"
done < "$rows"
echo "$(wc -l < "$rows") package rows locked and mirrored"
k=$(awk '$3=="linux-6.18.53.tar.xz"{print $2}' "$RDS_REPO/os/patches/linux/linux.hash")
asc=$(awk -F'\t' '$3=="kernel-v6.x-sha256sums.asc"{print $1}' "$RDS_LOCK")
exec "$RDS_REPO/tools/verify-release" --key "$RDS_REPO/env/keys/kernel-org-autosigner.gpg" \
    --fingerprint "$(cat "$RDS_REPO/env/keys/kernel-org-autosigner.fingerprint")" \
    --sign "$RDS_MIRROR/$asc" --name linux-6.18.53.tar.xz --sha256 "$k"
