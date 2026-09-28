# #96: Buildroot's job count honours a CPU limit. Rootless podman on the build host
# cannot be CPU-limited (no cpuset delegation, and taskset does not reach the
# container), so this runs where the limit is real: the chroot runner, as root
# (the ECC build host). Needs RDS_ROOTFS, and the Buildroot tree and dl-offline from a build.
need() { [ "$(id -u)" = 0 ] || fail "needs root"; [ -x "${RDS_ROOTFS:-/nonexistent}/usr/bin/setpriv" ] || fail "needs RDS_ROOTFS"; }

test_the_job_count_honours_a_cpu_limit() {
    need; local out rc=0 p; p=$(cd "$(repo_root)/../.." && pwd)
    # container.sh derives SOURCE_DATE_EPOCH from git, which the ECC build host lacks; prep recorded it.
    out=$(SOURCE_DATE_EPOCH=$(cat "$p/build/source-date-epoch") RDS_RUNNER=chroot RDS_PLANT="$(repo_root)/tests/slow/br-plant" RDS_DL="$p/build/dl-offline" \
        taskset -c 0,1 "$(repo_root)/env/container.sh" br rds_qemu "pkg:host-rds-plant-jobs-rebuild" 2>&1) || rc=$?
    assert_eq 0 "$rc" "$(printf '%s' "$out" | tail -5)"
    # The number exactly: "RDS-PLANT-JOBS=33" contains "=3" (a false pass, 2026-09-28).
    assert_eq 3 "$(printf '%s' "$out" | grep -ao 'RDS-PLANT-JOBS=[0-9]*' | tail -1 | cut -d= -f2)" "jobs under a 2-CPU limit"
}
