#!/usr/bin/env bash
# S6 smoke: the rds_qemu image must boot to init, not merely exist (#77).
# The SD copy is padded to a power of two (QEMU's rule) and run with
# snapshot=on, so nothing is written back.
. "$(dirname "$0")/../../lib.sh"
q=$RDS_PROJECT/build/br-out/rds_qemu/images
[ -s "$q/zImage" ] || { echo "no rds_qemu image: unmeasured"; exit 2; }
sd=$RDS_TMPDIR/qemu-sd.img log=$RDS_PROJECT/build/br-out/rds_qemu/qemu-boot.log
cp "$q/rootfs.squashfs" "$sd"; truncate -s "$(python3 -c "import os;n=os.path.getsize('$sd');p=1<<20
while p<n: p<<=1
print(p)")" "$sd"
timeout 60 qemu-system-arm -M vexpress-a9 -m 256 -nographic -no-reboot -kernel "$q/zImage" \
    -dtb "$q/vexpress-v2p-ca9.dtb" -drive "file=$sd,if=sd,format=raw,snapshot=on" \
    -append "console=ttyAMA0 root=/dev/mmcblk0 rootfstype=squashfs ro panic=1" > "$log" 2>&1
if grep -a -q 'Kernel panic' "$log"; then grep -a 'Kernel panic' "$log"; echo "FAIL: panic, see $log"; exit 1; fi
if grep -a -q -E 'Run /sbin/init|Starting|Welcome' "$log"; then echo "booted to init ($(grep -a -c . "$log") console lines)"; exit 0; fi
echo "FAIL: init never ran within 60 s, see $log"; exit 1
