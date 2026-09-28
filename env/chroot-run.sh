#!/usr/bin/env bash
# The build image without podman (#95), for a host whose podman cannot run
# env/container.sh: the ECC build host has bookworm's 4.3 and runs as root. The same image
# filesystem, exported from the pinned image, with the same /w binds (the list
# is built once, in container.sh), no network, uid 1000, the image read-only
# and a fresh /tmp for every run.
#
#   RDS_ROOTFS=DIR env/chroot-run.sh [-v SRC:DST[:ro]]... [-e K=V]... -- CMD...
#
# Needs root (unshare, mount, chroot). On a shared host, run it inside a
# capped transient unit (tools/remote-build), never bare.
set -euo pipefail
: "${RDS_ROOTFS:?the exported build image filesystem (tools/remote-build prep)}"
: "${RDS_UID:=1000}"
binds=() envs=()
while [ $# -gt 0 ]; do
    case $1 in
        -v) binds+=("$2"); shift 2 ;;
        -e) envs+=("$2"); shift 2 ;;
        --) shift; break ;;
        *) echo "chroot-run: unknown option $1" >&2; exit 64 ;;
    esac
done
[ $# -gt 0 ] || { echo "chroot-run: no command" >&2; exit 64; }
[ "$(id -u)" = 0 ] || { echo "chroot-run: needs root (unshare, mount, chroot)" >&2; exit 64; }
[ -x "$RDS_ROOTFS/usr/bin/setpriv" ] || { echo "chroot-run: $RDS_ROOTFS is not the build image" >&2; exit 64; }
work=$(mktemp -d)   # this run's /tmp, passwd and group: nothing carries over
trap 'rm -rf "$work"' EXIT
mkdir -m 1777 "$work/tmp"
{ grep -v "^[^:]*:[^:]*:$RDS_UID:" "$RDS_ROOTFS/etc/passwd"; echo "builder:x:$RDS_UID:$RDS_UID:builder:/w/out:/bin/sh"; } > "$work/passwd"
{ grep -v "^[^:]*:[^:]*:$RDS_UID:" "$RDS_ROOTFS/etc/group"; echo "builder:x:$RDS_UID:"; } > "$work/group"
for b in "${binds[@]}"; do
    d=${b#*:}; mkdir -p "$RDS_ROOTFS/${d%%:*}"   # mount points, before the image goes read-only
    # A writable bind's directories belong to the build user, as the invoking
    # user owns them under rootless podman (Buildroot flocks dl/<pkg>/.lock).
    # Directories only: dl's files are hard links into the mirror.
    case $d in *:ro) ;; *) find "${b%%:*}" -type d -exec chown "$RDS_UID:$RDS_UID" {} + ;; esac
done
inner=$(cat <<'INNER'
set -euo pipefail
R=$1 W=$2 U=$3; shift 3
nb=$1; shift; binds=("${@:1:$nb}"); shift "$nb"
ne=$1; shift; envs=("${@:1:$ne}"); shift "$ne"
hostname rds-build
mount --bind "$R" "$R"; mount -o remount,bind,ro "$R"
mount -t proc proc "$R/proc"
mount -t tmpfs -o mode=755,size=16m tmpfs "$R/dev"
for n in null:1:3 zero:1:5 full:1:7 random:1:8 urandom:1:9 tty:5:0; do
    IFS=: read -r f a b <<<"$n"; mknod -m 666 "$R/dev/$f" c "$a" "$b"
done
mkdir "$R/dev/pts" "$R/dev/shm"; mount -t tmpfs -o mode=1777,size=512m tmpfs "$R/dev/shm"
ln -s /proc/self/fd "$R/dev/fd"; ln -s fd/0 "$R/dev/stdin"; ln -s fd/1 "$R/dev/stdout"; ln -s fd/2 "$R/dev/stderr"
mount --bind "$W/tmp" "$R/tmp"
mount --bind "$W/passwd" "$R/etc/passwd"; mount --bind "$W/group" "$R/etc/group"
for b in "${binds[@]}"; do
    src=${b%%:*} rest=${b#*:} dst=${rest%%:*} opt=; [ "$rest" != "$dst" ] && opt=${rest#*:}
    mount --bind "$src" "$R$dst"
    [ "$opt" = ro ] && mount -o remount,bind,ro "$R$dst"
done
exec chroot "$R" /usr/bin/setpriv --reuid="$U" --regid="$U" --clear-groups \
    /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TERM=dumb "${envs[@]}" "$@"
INNER
)
# Not exec: the trap must clear $work when the build ends. Stdin is
# /dev/null, as under podman.
unshare --mount --uts --ipc --net --pid --fork --propagation private \
    bash -c "$inner" chroot-run "$RDS_ROOTFS" "$work" "$RDS_UID" \
    "${#binds[@]}" "${binds[@]}" "${#envs[@]}" "${envs[@]}" "$@" < /dev/null
