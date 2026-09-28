# QEMU tier (#51 T6): UBI attaches read-only and writes nothing in canary mode.
. "$(repo_root)/tests/qemu/lib-qemu.sh"
test_t6_twin_ubi_writes_without_canary() {
    local r; r=$(run_guest ubi $CHIP $SENSE)
    assert_eq 0 "$(field "$r" attach_rc)" "the twin attach failed: $r"
    gt0 "$(field "$r" chip_prog)" "UBI's writes seen by the chip sensor"
}
test_t6_canary_ubi_attaches_read_only_and_writes_nothing() {
    local r; r=$(run_guest ubi $CHIP nand.canary=1 $SENSE)
    assert_eq yes "$(field "$r" ro_attach)" "no read-only attach: $r"
    assert_eq 0 "$(field "$r" chip_prog)"; assert_eq 0 "$(field "$r" chip_erase)"
    assert_eq yes "$(field "$r" raw_unchanged)"
}
