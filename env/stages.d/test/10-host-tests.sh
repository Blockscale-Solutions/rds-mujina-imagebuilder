#!/usr/bin/env bash
# S0h: host unit tests, seconds, no container.
. "$(dirname "$0")/../../lib.sh"
exec "$RDS_REPO/tests/run.sh"
