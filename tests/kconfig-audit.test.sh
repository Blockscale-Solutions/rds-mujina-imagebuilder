# tools/kconfig-audit: every option a fragment asks for survives into the final .config (#41).
A="$(repo_root)/tools/kconfig-audit"
fx() { local f; f=$(mktemp); printf '%s\n' "$@" > "$f"; printf '%s' "$f"; }

test_all_requested_options_present_passes() {
    local fr cf rc=0
    fr=$(fx '# c' 'CONFIG_KERNEL_XZ=y' 'CONFIG_UIO=m' '# CONFIG_DEBUG_INFO is not set' 'CONFIG_HZ=250')
    cf=$(fx 'CONFIG_KERNEL_XZ=y' 'CONFIG_UIO=m' '# CONFIG_DEBUG_INFO is not set' 'CONFIG_HZ=250' 'CONFIG_OTHER=y')
    "$A" --fragment "$fr" --config "$cf" >/dev/null 2>&1 || rc=$?; assert_eq 0 "$rc"
}
test_an_option_dropped_by_dependencies_fails_and_is_named() {
    local fr cf rc=0 out
    fr=$(fx 'CONFIG_KERNEL_XZ=y' 'CONFIG_UIO_PDRV_GENIRQ=y'); cf=$(fx 'CONFIG_KERNEL_XZ=y')
    out=$("$A" --fragment "$fr" --config "$cf" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "CONFIG_UIO_PDRV_GENIRQ"
}
test_a_changed_value_fails() {
    local fr cf rc=0; fr=$(fx 'CONFIG_HZ=250'); cf=$(fx 'CONFIG_HZ=100')
    "$A" --fragment "$fr" --config "$cf" >/dev/null 2>&1 || rc=$?; assert_eq 1 "$rc"
}
test_an_option_asked_off_but_on_fails() {
    local fr cf rc=0; fr=$(fx '# CONFIG_MODULES is not set'); cf=$(fx 'CONFIG_MODULES=y')
    "$A" --fragment "$fr" --config "$cf" >/dev/null 2>&1 || rc=$?; assert_eq 1 "$rc"
}
test_an_empty_fragment_is_unmeasured() {
    local fr cf rc=0; fr=$(fx '# nothing'); cf=$(fx 'CONFIG_X=y')
    "$A" --fragment "$fr" --config "$cf" >/dev/null 2>&1 || rc=$?; assert_eq 2 "$rc"
}

test_buildroot_options_are_audited_too() {
    # Buildroot drops unmet BR2_ options as silently as the kernel drops CONFIG_ ones.
    local fr cf rc=0 out; fr=$(fx 'BR2_TARGET_ROOTFS_SQUASHFS=y' 'BR2_LINUX_KERNEL_XZ=y'); cf=$(fx 'BR2_TARGET_ROOTFS_SQUASHFS=y')
    out=$("$A" --fragment "$fr" --config "$cf" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "BR2_LINUX_KERNEL_XZ"
}
