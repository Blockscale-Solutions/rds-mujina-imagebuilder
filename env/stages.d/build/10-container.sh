#!/usr/bin/env bash
# S1 prerequisite: the pinned build container (#34).
. "$(dirname "$0")/../../lib.sh"
exec "$RDS_REPO/env/container.sh" build
