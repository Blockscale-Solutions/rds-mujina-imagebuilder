#!/usr/bin/env bash
. "$(dirname "$0")/../../lib.sh"
exec "$RDS_REPO/tools/version" current --repo "$RDS_REPO"
