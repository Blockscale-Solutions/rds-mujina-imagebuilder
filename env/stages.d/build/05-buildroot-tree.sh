#!/usr/bin/env bash
# S2 prerequisite: Buildroot's source tree, from the locked tarball (#94).
# The mirror entry is re-hashed against the lock first, and the tree is
# extracted fresh every run, so nothing unlocked or half-written carries over.
. "$(dirname "$0")/../../lib.sh"
name=buildroot-2026.08.tar.xz
h=$(awk -F'\t' -v n="$name" '$3==n{print $1}' "$RDS_LOCK" 2>/dev/null)
[ -n "$h" ] || { echo "no $name row in $RDS_LOCK: unmeasured (the fetch stage locks it)"; exit 2; }
src=$RDS_MIRROR/$h
[ -f "$src" ] && [ "$(sha256sum < "$src" | cut -d' ' -f1)" = "$h" ] \
    || { echo "FAIL $name: mirror entry ${h:0:16} missing or not matching the lock"; exit 1; }
tmp=$(mktemp -d "${RDS_BR_DIR%/}.new.XXXXXX" 2>/dev/null) || { mkdir -p "$(dirname "$RDS_BR_DIR")"; tmp=$(mktemp -d "${RDS_BR_DIR%/}.new.XXXXXX"); }
tar -C "$tmp" -xJf "$src" || { rm -rf "$tmp"; echo "FAIL $name: does not extract"; exit 1; }
rm -rf "$RDS_BR_DIR" && mv "$tmp" "$RDS_BR_DIR"
echo "$name ${h:0:16} extracted to $RDS_BR_DIR"
