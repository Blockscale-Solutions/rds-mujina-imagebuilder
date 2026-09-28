#!/usr/bin/env bash
# S2-S5 for rds_control: offline Buildroot build from locked sources only (#36).
. "$(dirname "$0")/../../lib.sh"
dl=$RDS_PROJECT/build/dl-offline
"$RDS_REPO/tools/dl-populate" --lock "$RDS_LOCK" --mirror "$RDS_MIRROR" --dl "$dl" || exit 1
out=$RDS_PROJECT/build/br-out/rds_control
rm -rf "$out"
RDS_DL=$dl "$RDS_REPO/env/container.sh" br rds_control build || exit 1
img=$out/images; miss=0
for f in zImage rootfs.squashfs; do [ -s "$img/$f" ] || { echo "MISSING $f"; miss=1; }; done
ls "$img"/*.dtb >/dev/null 2>&1 || { echo "MISSING a DTB"; miss=1; }
[ $miss -eq 0 ] || exit 1
( cd "$img" && sha256sum zImage *.dtb rootfs.squashfs ) | tee "$out/images.sha256"
