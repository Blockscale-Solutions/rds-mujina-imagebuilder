# Gates C4 (#37) and C9 (#38) through the real path: env/container.sh, then
# br.sh, then make, under --network=none. Test-only packages from
# tests/slow/br-plant are built as host packages in their own scratch output
# (build/br-out/<variant>-plant); no image is touched. The stage runner's
# propagation is tested apart (#81, tests/stages.test.sh).
# The locked, offline download directory the build stages use (build/20-rds_qemu).
PLANT_DL=$(. "$(repo_root)/env/lib.sh" && printf '%s' "$RDS_PROJECT/build/dl-offline")
plant() { # host package -> its output; status in $rc
    rc=0; out=$(RDS_PLANT="$(repo_root)/tests/slow/br-plant" RDS_DL="$PLANT_DL" \
        "$(repo_root)/env/container.sh" br rds_qemu "pkg:$1" 2>&1) || rc=$?
}

test_twin_a_package_that_builds_passes_the_same_path() {
    local out rc; plant host-rds-plant-ok
    assert_eq 0 "$rc" "$(printf '%s' "$out" | tail -5)"
}

test_c9_a_compile_error_fails_the_build_and_names_the_package() {
    local out rc; plant host-rds-plant-broken
    [ "$rc" -ne 0 ] || fail "a compile error exited 0"
    assert_contains "$out" "rds-plant-broken"
    assert_contains "$out" "broken.c"
}

test_c4_a_download_at_build_time_fails_offline() {
    local out rc; plant host-rds-plant-netfetch
    [ "$rc" -ne 0 ] || fail "a build-time download succeeded"
    assert_contains "$out" "rds-plant-netfetch"
    assert_contains "$out" "URLError"
}
