#!/usr/bin/env bash
# Build or run the RDS build container (#34).
#
#   env/container.sh build      -> prints the image id
#   env/container.sh apt-list   -> the installed package set, sorted
#   env/container.sh run CMD... -> CMD inside, project root mounted at /work
#   env/container.sh export TAR -> the image's filesystem as a tar (#95), then its id
#
# Podman storage lives under the project's build/, never in $HOME, so nothing
# is written outside the project root except podman's own runtime socket
# state under $XDG_RUNTIME_DIR. Image timestamps come from SOURCE_DATE_EPOCH
# (default: the last commit touching env/container/), so rebuilds are identical.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/lib.sh"
: "${RDS_PODMAN_ROOT:=$RDS_PROJECT/build/podman/root}"
: "${RDS_PODMAN_RUNROOT:=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/rds-podman}"
: "${SOURCE_DATE_EPOCH:=$(git -C "$RDS_REPO" log -1 --format=%ct -- env/container)}"
: "${SOURCE_DATE_EPOCH:=$(git -C "$RDS_REPO" log -1 --format=%ct)}"
[ -n "$SOURCE_DATE_EPOCH" ] || { echo "container: no SOURCE_DATE_EPOCH derivable" >&2; exit 1; }
export SOURCE_DATE_EPOCH
# RDS_RUNNER=chroot (#95): the same image filesystem and the same binds
# without podman, for a host whose podman cannot run this (the ECC build host).
# Offline only.
runner=${RDS_RUNNER:-podman}
[ "$runner" = chroot ] || mkdir -p "$RDS_PODMAN_ROOT" "$RDS_PODMAN_RUNROOT" "$RDS_TMPDIR"
pm() { TMPDIR="$RDS_TMPDIR" "${RDS_PODMAN_BIN:-podman}" --root "$RDS_PODMAN_ROOT" --runroot "$RDS_PODMAN_RUNROOT" "$@"; }
TAG=localhost/rds-build:latest
case "${1:-}" in
    build)
        pm build -q ${RDS_NO_CACHE:+--no-cache} --source-date-epoch "$SOURCE_DATE_EPOCH" --rewrite-timestamp -t "$TAG" \
            -f "$here/container/Containerfile" "$here/container" >&2
        pm image inspect "$TAG" --format '{{.Id}}' ;;
    export)
        # For env/chroot-run.sh on a host without a usable podman (#95).
        c=$(pm create --pull=never "$TAG" true)
        trap 'pm rm -f "$c" >/dev/null' EXIT
        pm export -o "$2" "$c"
        pm image inspect "$TAG" --format '{{.Id}}' ;;
    apt-list)
        pm run --rm --pull=never "$TAG" dpkg-query -W -f '${Package}\t${Version}\t${Architecture}\n' | sort ;;
    run)
        shift; pm run --rm --pull=never --userns=keep-id --network=none -v "$RDS_PROJECT:/work:Z" -w /work "$TAG" "$@" ;;
    br)
        # br VARIANT MODE [net]: Buildroot in the container. Only the fetch
        # stage passes net; every other mode runs with --network=none.
        v=$2 mode=$3 net=${4:-none}
        br=$RDS_BR_DIR/buildroot-2026.08
        out=$RDS_PROJECT/build/br-out/$v; dl=${RDS_DL:-$RDS_PROJECT/build/dl}
        # RDS_PLANT=DIR adds a test-only BR2_EXTERNAL (tests/slow/br-plant,
        # #37, #38), read-only at /w/plant, with its own scratch output.
        plant=(); [ -n "${RDS_PLANT:-}" ] && { plant=(-v "$RDS_PLANT:/w/plant:ro" -e RDS_PLANT=1); out=$out-plant; }
        mkdir -p "$out" "$dl"
        # One list of binds and environment for both runners (#95).
        mounts=(-v "$br:/w/br:ro" -v "$RDS_REPO/os:/w/os:ro" -v "$RDS_REPO/env:/w/env:ro" "${plant[@]}"
            -v "$out:/w/out" -v "$dl:/w/dl" -e HOME=/w/out -e RDS_R1_PLANT="${RDS_R1_PLANT:-0}")
        if [ "$runner" = chroot ]; then
            [ "$net" = none ] || { echo "container: the chroot runner is offline only" >&2; exit 64; }
            exec "${RDS_CHROOT_RUN:-$here/chroot-run.sh}" "${mounts[@]}" -- /w/env/br.sh "$v" "$mode"
        fi
        pm run --rm --pull=never --userns=keep-id --network="$([ "$net" = net ] && echo slirp4netns || echo none)" \
            "${mounts[@]}" "$TAG" /w/env/br.sh "$v" "$mode" ;;
    *) echo "usage: env/container.sh build|apt-list|export TAR|run CMD...|br VARIANT MODE [net]" >&2; exit 64 ;;
esac
