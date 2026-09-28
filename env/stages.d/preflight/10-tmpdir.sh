#!/usr/bin/env bash
# The build's temp directory must not be tmpfs: on the build host /tmp is RAM, and
# Claude Code kills background tasks on low free memory (MEASURED).
. "$(dirname "$0")/../../lib.sh"
mkdir -p "$RDS_TMPDIR" 2>/dev/null
fs=$(findmnt -no FSTYPE -T "$RDS_TMPDIR" 2>/dev/null) || { echo "cannot read filesystem of $RDS_TMPDIR"; exit 2; }
if [ "$fs" = tmpfs ] || [ "$fs" = ramfs ]; then echo "FAIL: build TMPDIR $RDS_TMPDIR is $fs"; exit 1; fi
echo "build TMPDIR $RDS_TMPDIR is $fs"
