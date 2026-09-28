#!/usr/bin/env bash
# S1: fetch every locked input into the mirror, then prove Buildroot's hash
# came from its maintainer's signature (#35). The only networked stage.
. "$(dirname "$0")/../../lib.sh"
"$RDS_REPO/tools/fetch" --lock "$RDS_LOCK" --mirror "$RDS_MIRROR" || exit $?
sign=$(awk -F'\t' '$3=="buildroot-2026.08.tar.xz.sign"{print $1}' "$RDS_LOCK")
tar=$(awk -F'\t' '$3=="buildroot-2026.08.tar.xz"{print $1}' "$RDS_LOCK")
exec "$RDS_REPO/tools/verify-release" --key "$RDS_REPO/env/keys/buildroot-release.gpg" \
    --fingerprint "$(cat "$RDS_REPO/env/keys/buildroot-release.fingerprint")" \
    --sign "$RDS_MIRROR/$sign" --name buildroot-2026.08.tar.xz --sha256 "$tar"
