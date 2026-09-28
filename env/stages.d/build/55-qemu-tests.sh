#!/usr/bin/env bash
# S6: the guest tests under QEMU, on the image just built (#51 onward).
. "$(dirname "$0")/../../lib.sh"
exec "$RDS_REPO/tests/run.sh" "$RDS_REPO/tests/qemu"
