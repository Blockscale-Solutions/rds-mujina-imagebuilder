# #95: the chroot runner (the ECC build host's) gets exactly podman's binds and environment,
# because container.sh builds that list once for both.
CS="$(repo_root)/env/container.sh"

runner_args() { # runner dir -> the -v/-e pairs and the command it was handed, one per line
    local d=$2
    printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done\n' > "$d/stub"; chmod +x "$d/stub"
    RDS_RUNNER=$1 RDS_PODMAN_BIN="$d/stub" RDS_CHROOT_RUN="$d/stub" RDS_PODMAN_ROOT="$d/pr" RDS_PODMAN_RUNROOT="$d/prr" \
        RDS_DL="$d/dl" RDS_BR_DIR="$d/br" "$CS" br "zz-parity-$$" build \
        | awk 'p{print "pair " $0; p=0; next} /^-[ve]$/{p=1; next} /^\/w\/env\/br.sh$/{c=1} c{print "cmd " $0}' | sort
    rm -rf "$(repo_root)/../../build/br-out/zz-parity-$$"
}

test_chroot_runner_gets_podman_s_binds_and_environment() {
    local a b d; d=$(mktemp -d); a=$(runner_args podman "$d"); b=$(runner_args chroot "$d")
    assert_contains "$a" "pair HOME=/w/out"      # the instrument sees pairs at all
    assert_contains "$a" "cmd /w/env/br.sh"
    assert_eq "$a" "$b" "podman and chroot runners differ"
}

test_the_chroot_runner_refuses_the_network() {
    local out rc=0; out=$(RDS_RUNNER=chroot RDS_CHROOT_RUN=/bin/true "$CS" br zz-parity-net source net 2>&1) || rc=$?
    rm -rf "$(repo_root)/../../build/br-out/zz-parity-net"
    assert_eq 64 "$rc" "$out"
}
