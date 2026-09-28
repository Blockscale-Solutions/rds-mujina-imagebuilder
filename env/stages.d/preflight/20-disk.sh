#!/usr/bin/env bash
. "$(dirname "$0")/../../lib.sh"
mkdir -p "$RDS_PROJECT/build"
free=$(df -Pk "$RDS_PROJECT/build" | awk 'NR==2{print int($4/1048576)}')
[ -n "$free" ] || { echo "cannot read free space"; exit 2; }
if [ "$free" -lt "$RDS_DISK_FLOOR_GB" ]; then echo "FAIL: $free GB free under build/, floor $RDS_DISK_FLOOR_GB GB"; exit 1; fi
echo "$free GB free under build/ (floor $RDS_DISK_FLOOR_GB GB)"
