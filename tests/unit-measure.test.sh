# tools/unit/readonly-measure.sh is sent to the test unit and must never write (#61).
# The write proof runs it under dash against a fake unit root, with trap
# commands for every NAND, UBI, bootloader-environment and power writer.
# NOT busybox sh: busybox runs its own applets (mount, reboot, nandwrite, the
# UBI tools) ahead of PATH, so traps placed on PATH are never called there
# (MEASURED 2026-09-24, busybox 1.37). A separate test runs it under busybox
# for compatibility with the unit's shell.
SCRIPT="$(repo_root)/tools/unit/readonly-measure.sh"
WRITERS="nandwrite flash_erase flash_eraseall flashcp mtd ubiformat ubiupdatevol ubimkvol ubirmvol ubirsvol ubirename ubiattach ubidetach fw_setenv reboot poweroff halt insmod rmmod modprobe devmem"

fake_unit() { # -> dir with root/, shims/, and trap logs
    local d r; d=$(mktemp -d); r=$d/root
    mkdir -p "$r/sys/class/mtd/mtd0" "$r/etc" "$r/sys/class/watchdog/watchdog0" \
        "$r/proc/device-tree/soc/serial@ffc02000" "$r/sys/class/ubi/ubi0_0" "$r/firmware" \
        "$r/sys/kernel/debug/clk" "$r/dev" "$d/shims" "$d/tmp"
    for f in writesize:2048 oobsize:64 ecc_strength:8 ecc_step_size:512; do echo "${f#*:}" > "$r/sys/class/mtd/mtd0/${f%%:*}"; done
    echo '/dev/mtd0 0x100000 0x20000 0x20000' > "$r/etc/fw_env.config"
    for f in identity:wdt timeout:30 state:active bootstatus:0; do echo "${f#*:}" > "$r/sys/class/watchdog/watchdog0/${f%%:*}"; done
    printf 'snps,dw-apb-uart\0' > "$r/proc/device-tree/soc/serial@ffc02000/compatible"
    printf '\377\300\040\000' > "$r/proc/device-tree/soc/serial@ffc02000/reg"
    for f in name:factory type:static reserved_ebs:34 data_bytes:4317184; do echo "${f#*:}" > "$r/sys/class/ubi/ubi0_0/${f%%:*}"; done
    echo hex > "$r/firmware/board.hex"
    echo 'clk summary' > "$r/sys/kernel/debug/clk/clk_summary"
    head -c 4096 /dev/urandom > "$r/dev/mtd0"; head -c 8192 /dev/urandom > "$r/dev/mtd1"
    for w in $WRITERS; do
        printf '#!/bin/sh\necho "%s $*" >> "%s/trap.log"\nexit 1\n' "$w" "$d" > "$d/shims/$w"
    done
    printf '#!/bin/sh\necho "mount $*" >> "%s/mount.log"\nexit 1\n' "$d" > "$d/shims/mount"
    printf '#!/bin/sh\necho "umount $*" >> "%s/mount.log"\nexit 0\n' "$d" > "$d/shims/umount"
    chmod +x "$d/shims/"*; : > "$d/trap.log"; : > "$d/mount.log"
    printf '%s' "$d"
}
tree_hash() { (cd "$1" && find . -type f -exec sha256sum {} + | sort | sha256sum); }
run() { # dir script [mode] -> stdout of the script under dash, traps on PATH
    RDS_ROOT="$1/root" TMPDIR="$1/tmp" PATH="$1/shims:$PATH" dash "$2" ${3:-facts}
}

test_every_question_is_answered_or_marked_unmeasured() {
    local d out; d=$(fake_unit); out=$(run "$d" "$SCRIPT")
    for q in Q-ECC Q-ENV Q-WDT Q-DT Q-UBI Q-BOOT Q-FW Q-CLK; do assert_contains "$out" "===== $q"; done
    assert_contains "$out" "ecc_strength: 8"
    assert_contains "$out" "reserved_ebs: 34"
}

test_it_calls_no_writer_and_changes_nothing() {
    local d before after
    d=$(fake_unit); before=$(tree_hash "$d/root")
    run "$d" "$SCRIPT" >/dev/null
    after=$(tree_hash "$d/root")
    assert_eq "" "$(cat "$d/trap.log")" "writer commands called"
    assert_eq "$before" "$after" "fake unit root changed"
}

test_every_mount_is_read_only() {
    local d; d=$(fake_unit); run "$d" "$SCRIPT" >/dev/null
    [ -s "$d/mount.log" ] || fail "no mount attempted: Q-BOOT unmeasured by construction"
    if grep -v -- '-o ro' "$d/mount.log" | grep -q '^mount'; then fail "a mount without -o ro: $(cat "$d/mount.log")"; fi
}

test_a_planted_writer_is_caught() {
    # The instrument must see the defect it exists for: plant a write and expect the trap.
    local d m; d=$(fake_unit); m=$d/mutant.sh
    sed 's/^\( *\)section Q-ENV$/&\n\1fw_setenv bootdelay 5/' "$SCRIPT" > "$m"
    grep -q 'fw_setenv bootdelay' "$m" || fail "mutation did not apply"
    run "$d" "$m" >/dev/null
    assert_contains "$(cat "$d/trap.log")" "fw_setenv bootdelay 5"
}

test_a_missing_source_reads_unmeasured_not_empty() {
    local d out; d=$(fake_unit); rm -r "$d/root/sys/class/watchdog"
    out=$(run "$d" "$SCRIPT")
    assert_contains "$out" "UNMEASURED"
}

test_dump_mode_streams_mtd0_byte_for_byte() {
    local d a b; d=$(fake_unit)
    a=$(run "$d" "$SCRIPT" dump-mtd0 | sha256sum); b=$(sha256sum < "$d/root/dev/mtd0")
    assert_eq "$b" "$a"
}

test_a_planted_busybox_applet_write_is_caught() {
    # The case the first version of this test could not see: reboot is a busybox applet.
    local d m; d=$(fake_unit); m=$d/mutant.sh
    sed 's/^\( *\)section Q-WDT$/&\n\1reboot -f/' "$SCRIPT" > "$m"
    run "$d" "$m" >/dev/null
    assert_contains "$(cat "$d/trap.log")" "reboot -f"
}

test_it_never_calls_busybox_by_name() {
    # "busybox reboot" would bypass every trap above.
    if grep -n -w busybox "$SCRIPT" | grep -v '^[0-9]*: *#'; then fail "script calls busybox directly"; fi
}

test_it_runs_under_busybox_sh() {
    local d out; d=$(fake_unit)
    out=$(RDS_ROOT="$d/root" TMPDIR="$d/tmp" busybox sh "$SCRIPT" facts 2>&1)
    for q in Q-ECC Q-ENV Q-WDT Q-DT Q-UBI Q-BOOT Q-FW Q-CLK; do assert_contains "$out" "===== $q"; done
}
