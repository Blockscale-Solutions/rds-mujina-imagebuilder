# #52: until stock is retired, any UBIFS our kernel formats must be format 4,
# which the vendor 4.9 kernel mounts read-write. Every kernel of ours carries
# ubifs.default_version=4 in its built-in command line (board/common).
. "$(repo_root)/tests/qemu/lib-qemu.sh"

test_a_new_ubifs_is_format_4_without_double_hash() {
    local r; r=$(run_guest ubifsver $CHIP $SENSE)
    assert_eq "attach=0 mkvol=0 mount=0" "attach=$(field "$r" attach) mkvol=$(field "$r" mkvol) mount=$(field "$r" mount)" "$r"
    assert_eq 06101831 "$(field "$r" magic)" "not a UBIFS superblock: $r"
    assert_eq 4 "$(field "$r" param)" "ubifs.default_version at boot: $r"
    assert_eq 4 "$(field "$r" fmt)" "superblock fmt_version: $r"
    assert_eq 4 "$(field "$r" media_w)" "the kernel's own mount message: $r"
    assert_eq no "$(field "$r" double_hash)" "$r"
}

test_twin_the_instrument_sees_a_format_5_superblock() {
    local r; r=$(run_guest ubifsver $CHIP $SENSE rds.twin=1)
    assert_eq 5 "$(field "$r" fmt)" "$r"
    assert_eq yes "$(field "$r" double_hash)" "$r"
}
