# Slow tier (about 40 min cold): the offline build verb end to end (#36, #77).
# The verb itself checks each stage; this asserts its outcome and records.
P="$(repo_root)/../.."

test_the_build_verb_passes_offline_and_boots() {
    local log rc=0; log=$(mktemp)
    "$(repo_root)/env/rds" build > "$log" 2>&1 || rc=$?
    assert_eq 0 "$rc" "env/rds build"
    assert_contains "$(cat "$log")" "[rds build] 50-qemu-boot: exit 0"
    for v in rds_qemu rds_control; do
        for f in zImage rootfs.squashfs; do [ -s "$P/build/br-out/$v/images/$f" ] || fail "$v: no $f"; done
        ls "$P/build/br-out/$v/images/"*.dtb >/dev/null 2>&1 || fail "$v: no DTB"
        [ -s "$P/build/br-out/$v/stage-times.tsv" ] || fail "$v: no stage times"
    done
}
