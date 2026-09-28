#!/usr/bin/env bash
# The built board DTB carries every hw.toml block exactly, and no source hogs
# a GPIO line (#42).
. "$(dirname "$0")/../../lib.sh"
b=$RDS_REPO/os/board/rds-control
"$RDS_REPO/tools/hw2dts" check-dts "$b/rds-control.dts" "$b/rds-fpga.dtsi" || exit 1
out=$RDS_PROJECT/build/br-out/rds_control
dtb=$out/images/rds-control.dtb
[ -s "$dtb" ] || { echo "no rds-control.dtb: unmeasured"; exit 2; }
dtc=$(cd "$out" && ls -d build/linux-*/scripts/dtc/dtc | head -1)
"$RDS_REPO/env/container.sh" run "/work/build/br-out/rds_control/$dtc" -I dtb -O dts -o /work/build/br-out/rds_control/rds-control.decompiled.dts \
    /work/build/br-out/rds_control/images/rds-control.dtb 2>/dev/null || { echo "FAIL: decompile"; exit 1; }
exec "$RDS_REPO/tools/hw2dts" verify-dtb "$out/rds-control.decompiled.dts"
