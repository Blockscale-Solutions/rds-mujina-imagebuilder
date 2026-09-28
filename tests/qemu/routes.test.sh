# QEMU tier (#80, review T7): every userspace route to a write in the image,
# each with the layer that refused it and the chip's counts across it alone.
. "$(repo_root)/tests/qemu/lib-qemu.sh"
MTDCHAR="mtd_debug flashcp nandtest flash_lock"
ERRNO="flashcp nandtest flash_lock"   # mtd_debug reports a failed open() without its errno

test_t7_canary_refuses_every_route_before_the_chip() {
    local r h; r=$(run_guest routes $CHIP nand.canary=1 $SENSE)
    assert_eq yes "$(field "$r" canary)" "canary mode not announced: $r"
    assert_eq yes "$(field "$r" mtdblock_present)" "no mtdblock node, so that route is unmeasured: $r"
    for h in $MTDCHAR mtdblock; do
        [ "$(field "$r" ${h}_rc)" != 0 ] || fail "$h succeeded under the canary: $r"
        assert_eq 0 "$(field "$r" ${h}_dprog)" "$h: programs the chip executed"
        assert_eq 0 "$(field "$r" ${h}_derase)" "$h: erases the chip executed"
    done
    # mtdchar refuses a read-write open; a block device opens, and its write
    # is refused because mtdblock marked the disk read-only (6.18 fops.c).
    for h in $ERRNO; do assert_eq open "$(field "$r" ${h}_layer)" "$h refused at the wrong layer: $r"; done
    assert_eq open-noerrno "$(field "$r" mtd_debug_layer)" "mtd_debug: $r"
    assert_eq block "$(field "$r" mtdblock_layer)" "mtdblock refused at the wrong layer: $r"
    assert_eq yes "$(field "$r" raw_unchanged)" "raw data or OOB changed: $r"
}

test_t7_twin_every_write_route_reaches_the_chip() {
    local r h; r=$(run_guest routes $CHIP $SENSE)
    assert_eq no "$(field "$r" canary)" "twin booted in canary mode: $r"
    assert_eq yes "$(field "$r" mtdblock_present)" "no mtdblock node: $r"
    for h in mtd_debug flashcp nandtest mtdblock; do
        assert_eq 0 "$(field "$r" ${h}_rc)" "$h failed without the canary: $r"
        gt0 "$(field "$r" ${h}_derase)" "$h: erases seen by the chip"
    done
    for h in flashcp nandtest mtdblock; do gt0 "$(field "$r" ${h}_dprog)" "$h: programs seen by the chip"; done
    # nandsim has no lock_area, so the chip layer answers -ENOTSUPP (#80):
    # this route is measured in the canary direction only.
    [ "$(field "$r" flash_lock_rc)" != 0 ] || fail "flash_lock succeeded on nandsim: $r"
    assert_eq other "$(field "$r" flash_lock_layer)" "flash_lock twin: $r"
    assert_eq 0 "$(field "$r" flash_lock_dprog)"; assert_eq 0 "$(field "$r" flash_lock_derase)"
    assert_eq no "$(field "$r" raw_unchanged)" "the twin must change the flash"
}
