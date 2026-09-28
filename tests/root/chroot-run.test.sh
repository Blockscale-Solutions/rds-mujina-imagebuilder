# #95: the podman-free runner. Needs root and RDS_ROOTFS (the exported build
# image), so it runs on the ECC build host: tests/run.sh tests/root. Anywhere else each test
# fails, naming what it lacks: it is never a pass it did not measure.
RUN="$(repo_root)/env/chroot-run.sh"
need() { [ "$(id -u)" = 0 ] || fail "needs root"; [ -x "${RDS_ROOTFS:-/nonexistent}/usr/bin/setpriv" ] || fail "needs RDS_ROOTFS"; }

test_no_network_but_loopback() {
    need; local out; out=$("$RUN" -- sh -c 'tail -n +3 /proc/net/dev | cut -d: -f1 | tr -d " "')
    assert_eq lo "$out" "interfaces inside"
}

test_the_build_runs_as_uid_1000_with_a_name_and_only_the_given_environment() {
    need; local out; out=$(SECRET_HOST_VAR=x "$RUN" -e HOME=/w/out -- sh -c 'echo "$(id -u) $(id -un) $HOME"; env | sort | cut -d= -f1 | tr "\n" " "')
    assert_contains "$out" "1000 builder /w/out"
    assert_not_contains "$out" "SECRET_HOST_VAR"
}

test_the_image_is_read_only_out_is_writable_and_ro_binds_hold() {
    need; local o r out; o=$(mktemp -d); r=$(mktemp -d); chown 1000:1000 "$o"
    out=$("$RUN" -v "$o:/w/out" -v "$r:/w/os:ro" -- sh -c \
        'touch /usr/rds-x 2>/dev/null && echo image-writable; touch /w/out/x && echo out-ok; touch /w/os/x 2>/dev/null && echo ro-writable; true')
    assert_eq out-ok "$out" "writes"
    [ -f "$o/x" ] || fail "/w/out did not reach the host"
}

test_a_writable_bind_made_by_root_is_writable_by_the_build_user() {
    # The stages run as root on the ECC build host and create /w/out themselves (first launch, 2026-09-28).
    need; local o out; o=$(mktemp -d)
    out=$("$RUN" -v "$o:/w/out" -- sh -c 'mkdir /w/out/build && echo ok')
    assert_eq ok "$out"
}

test_the_build_user_can_lock_in_a_root_made_subdirectory_but_files_keep_their_owner() {
    # Buildroot flocks dl/<pkg>/.lock (second launch, 2026-09-28); dl's files
    # are hard links into the mirror and must not change owner.
    need; local d out; d=$(mktemp -d); mkdir "$d/lz4"; echo x > "$d/lz4/src.tar"
    out=$("$RUN" -v "$d:/w/dl" -- sh -c 'touch /w/dl/lz4/.lock && echo ok')
    assert_eq ok "$out"
    assert_eq 0 "$(stat -c %u "$d/lz4/src.tar")" "a file's owner changed"
}

test_tmp_is_fresh_every_run() {
    need; "$RUN" -- sh -c 'touch /tmp/planted'
    assert_eq absent "$("$RUN" -- sh -c '[ -e /tmp/planted ] && echo present || echo absent')"
}

test_the_image_passes_dpkg_verify() {
    need; local out; out=$("$RUN" -- sh -c 'dpkg --verify 2>&1 | grep -v "^missing" | grep -c . || true')
    assert_eq 0 "$out" "files differing from their packages"
}
