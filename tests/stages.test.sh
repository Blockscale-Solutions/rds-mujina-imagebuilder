# Build stages must be able to fail (#81): a lost option fails the kernel
# audit, the variants and their fragments come from os/configs, and every
# stage runs with pipefail so a pipe cannot hide a failing check.
REAL="$(repo_root)"

fixture() { # -> project dir holding git/repo with one variant, vx, and two board fragments
    local p r
    p=$(mktemp -d); r="$p/git/repo"
    mkdir -p "$r/env/stages.d/build" "$r/tools" "$r/os/configs" "$r/os/board/common" "$r/os/board/vx" \
        "$p/build/br-out/vx/build/linux-1"
    cp "$REAL/env/lib.sh" "$r/env/"
    cp "$REAL/env/stages.d/build/40-kconfig-audit.sh" "$r/env/stages.d/build/"
    cp "$REAL/tools/kconfig-audit" "$r/tools/"
    printf 'BR2_arm=y\n' > "$r/os/configs/common.fragment"
    printf 'BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="$(BR2_EXTERNAL_RDS_PATH)/board/common/linux.fragment $(BR2_EXTERNAL_RDS_PATH)/board/vx/linux.fragment"\n' \
        > "$r/os/configs/vx.fragment"
    printf 'CONFIG_RDS_A=y\n' > "$r/os/board/common/linux.fragment"
    printf 'CONFIG_RDS_B=y\n' > "$r/os/board/vx/linux.fragment"
    printf '%s' "$p"
}

audit() { # project -> stage output; status in $rc
    rc=0; out=$("$1/git/repo/env/stages.d/build/40-kconfig-audit.sh" 2>&1) || rc=$?
}

test_the_kernel_audit_passes_when_every_option_survives() {
    local p out rc; p=$(fixture)
    printf 'CONFIG_RDS_A=y\nCONFIG_RDS_B=y\n' > "$p/build/br-out/vx/build/linux-1/.config"
    audit "$p"
    assert_eq 0 "$rc" "$out"
    assert_contains "$out" "vx: kconfig-audit: 2 of 2 requested options survived"
}

test_the_kernel_audit_fails_on_an_option_lost_from_the_second_board_fragment() {
    local p out rc; p=$(fixture)
    printf 'CONFIG_RDS_A=y\n' > "$p/build/br-out/vx/build/linux-1/.config"
    audit "$p"
    assert_eq 1 "$rc" "$out"
    assert_contains "$out" "LOST CONFIG_RDS_B"
}

test_a_variant_without_a_kernel_config_is_unmeasured() {
    local p out rc; p=$(fixture)
    audit "$p"
    assert_eq 2 "$rc" "$out"
    assert_contains "$out" "vx: no kernel .config"
}

test_variants_and_their_fragments_come_from_os_configs() {
    local p out; p=$(fixture)
    out=$(bash -c '. "$1/git/repo/env/lib.sh"; echo "variants: $(rds_variants)"; rds_kernel_fragments vx' _ "$p")
    assert_contains "$out" "variants: vx"
    assert_contains "$out" "$p/git/repo/os/board/common/linux.fragment"
    assert_contains "$out" "$p/git/repo/os/board/vx/linux.fragment"
}

test_the_real_variants_are_the_two_we_build() {
    assert_eq "rds_control rds_qemu" "$(bash -c '. "$1/env/lib.sh"; echo $(rds_variants)' _ "$REAL")"
}

test_every_stage_runs_with_pipefail() {
    local s missing=""
    grep -q '^set -o pipefail' "$REAL/env/lib.sh" || fail "env/lib.sh does not set pipefail"
    for s in "$REAL"/env/stages.d/*/*; do
        grep -q 'lib\.sh"' "$s" || missing="$missing $(basename "$(dirname "$s")")/$(basename "$s")"
    done
    assert_eq "" "$missing" "stages that do not source lib.sh"
}
