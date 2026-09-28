# QEMU tier (#51 T4): the driver hooks called directly, past mtdcore's read-only flag.
. "$(repo_root)/tests/qemu/lib-qemu.sh"
HOOKS="erase woob_place woob_raw oob_only markbad panic dev_erase dev_markbad"
test_t4_twin_every_hook_writes_without_canary() {
    local r h; r=$(run_guest probe $CHIP $SENSE)
    for h in $HOOKS; do assert_eq 0 "$(field "$r" $h)" "twin: $h did not succeed: $r"; done
    gt0 "$(field "$r" chip_prog)" "programs seen by the chip sensor"; gt0 "$(field "$r" chip_erase)" "erases seen by the chip sensor"
}
test_t4_canary_every_hook_is_refused_and_the_chip_is_untouched() {
    local r h; r=$(run_guest probe $CHIP nand.canary=1 $SENSE)
    for h in $HOOKS; do assert_eq -30 "$(field "$r" $h)" "$h not refused with -EROFS: $r"; done
    assert_eq 0 "$(field "$r" chip_prog)"; assert_eq 0 "$(field "$r" chip_erase)"
    assert_eq yes "$(field "$r" raw_unchanged)"
}
