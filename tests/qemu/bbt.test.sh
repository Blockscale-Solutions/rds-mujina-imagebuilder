# QEMU tier (#51): the bad block table, the flag, and userspace writes.
. "$(repo_root)/tests/qemu/lib-qemu.sh"

assert_canary_held() { # result line
    local r=$1
    assert_eq no "$(field "$r" bbt_written)" "table written in canary mode: $r"
    assert_eq yes "$(field "$r" canary)" "canary mode not announced"
    assert_eq Y "$(field "$r" param)" "nand.canary parameter"
    assert_eq 0x0 "$(field "$r" flags)" "MTD flags still writable"
    assert_eq 0 "$(field "$r" chip_prog)" "the chip executed a program"
    assert_eq 0 "$(field "$r" chip_erase)" "the chip executed an erase"
    assert_eq open "$(field "$r" erase_layer)" "erase refused at the wrong layer"
    assert_eq open "$(field "$r" write_layer)" "write refused at the wrong layer"
    assert_eq yes "$(field "$r" raw_unchanged)" "raw data or OOB changed"
}

test_t0_twin_without_canary_the_chip_is_written() {
    local r; r=$(run_guest bbt $CHIP $SENSE)
    assert_contains "$(field "$r" dev)" mtd "no NAND simulator device"
    assert_eq yes "$(field "$r" bbt_written)"; assert_eq N "$(field "$r" param)"
    gt0 "$(field "$r" chip_prog)" "programs seen by the chip sensor"
    assert_eq no "$(field "$r" raw_unchanged)" "the twin must change the flash"
}
test_t0_canary_holds() {
    assert_canary_held "$(run_guest bbt $CHIP nand.canary=1 $SENSE)"
}
test_t1_a_later_canary_0_is_refused_and_logged() {
    local r; r=$(run_guest bbt $CHIP nand.canary=1 nand.canary=0 $SENSE)
    assert_canary_held "$r"
    assert_eq yes "$(field "$r" refused_zero_arg)" "the refused nand.canary=0 is not logged"
}
