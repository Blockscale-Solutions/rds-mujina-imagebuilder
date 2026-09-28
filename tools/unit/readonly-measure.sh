#!/bin/sh
# Read-only measurements on an RDS control board (rdsmujina-env #61, DESIGN.md s10).
#
#   ssh unit sh -s facts     < readonly-measure.sh > facts.txt
#   ssh unit sh -s dump-mtd0 < readonly-measure.sh > mtd0.bin
#
# Sent on stdin: the unit's dropbear refuses a command string over 9000 bytes.
# POSIX sh for busybox ash. It never writes flash, UBI, the bootloader
# environment or power state; tests/unit-measure.test.sh proves that against a
# fake unit with trap commands for every writer. The only mount is read-only
# and is undone. Every probe prints its exit status; a probe that cannot run
# prints UNMEASURED with the reason, never an empty line.
R=${RDS_ROOT:-}
T=${TMPDIR:-/tmp}

section() { printf '\n===== %s\n' "$1"; }
unmeasured() { printf 'UNMEASURED: %s\n' "$*"; }
show() { # file [label]
    if [ -r "$R$1" ]; then printf '%s: %s\n' "${2:-$1}" "$(cat "$R$1" 2>&1 | tr '\0' ' ')"
    else unmeasured "$1 not readable"; fi
}
run() { # label command...
    l=$1; shift
    if command -v "$1" >/dev/null 2>&1; then
        out=$("$@" 2>&1); rc=$?
        printf -- '--- %s (rc %s)\n%s\n' "$l" "$rc" "$out"
    else unmeasured "$l: $1 not present"; fi
}

facts() {
    printf 'readonly-measure %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    show /proc/version kernel

    section Q-ECC
    for f in writesize oobsize ecc_strength ecc_step_size erasesize type; do
        show /sys/class/mtd/mtd0/$f $f
    done

    section Q-ENV
    show /etc/fw_env.config fw_env.config
    run fw_printenv fw_printenv
    printf 'mtd0: dump separately with the dump-mtd0 mode (%s)\n' \
        "$( [ -r "$R/dev/mtd0" ] && echo readable || echo 'not readable' )"

    section Q-WDT
    if [ -d "$R/sys/class/watchdog" ]; then
        for w in "$R"/sys/class/watchdog/*; do
            for f in identity timeout timeleft state bootstatus nowayout; do
                show "${w#$R}/$f" "$(basename "$w")/$f"
            done
        done
    else unmeasured "no /sys/class/watchdog"; fi

    section Q-DT
    if [ -d "$R/proc/device-tree" ]; then
        find "$R/proc/device-tree" -type f \( -name compatible -o -name reg -o -name interrupts \
            -o -name dmas -o -name dma-names -o -name phy-mode -o -name clocks -o -name status \) 2>/dev/null |
        sort | while read -r p; do
            case "$p" in
                */compatible|*/dma-names|*/phy-mode|*/status) printf '%s: %s\n' "${p#$R}" "$(tr '\0' ' ' < "$p")" ;;
                *) printf '%s:%s\n' "${p#$R}" "$(od -An -tx1 "$p" | tr -s ' \n' ' ')" ;;
            esac
        done
    else unmeasured "no /proc/device-tree"; fi

    section Q-UBI
    if ls -d "$R"/sys/class/ubi/ubi0_* >/dev/null 2>&1; then
        for v in "$R"/sys/class/ubi/ubi0_*; do
            for f in name type reserved_ebs data_bytes alignment usable_eb_size; do
                show "${v#$R}/$f" "$(basename "$v")/$f"
            done
        done
    else unmeasured "no /sys/class/ubi/ubi0_*"; fi
    for f in avail_eraseblocks total_eraseblocks bad_peb_count reserved_for_bad eraseblock_size; do
        [ -r "$R/sys/class/ubi/ubi0/$f" ] && show /sys/class/ubi/ubi0/$f "ubi0/$f"
    done

    section Q-BOOT
    m="$T/rds-ro-$$"
    if mkdir "$m" 2>/dev/null; then
        if mount -t ubifs -o ro ubi0:boot "$m" 2>/dev/null; then
            ls -lR "$m"; find "$m" -type f -exec sha256sum {} \;
            umount "$m"
        else unmeasured "read-only mount of ubi0:boot failed (rc $?)"; fi
        rmdir "$m"
    else unmeasured "cannot create mount point under $T"; fi

    section Q-FW
    if [ -d "$R/firmware" ]; then
        find "$R/firmware" -type f -exec sha256sum {} \; | sed "s#$R##"
        find "$R/firmware" -type f -exec ls -l {} \; | sed "s#$R##"
    else unmeasured "no /firmware"; fi

    section Q-CLK
    if [ -r "$R/sys/kernel/debug/clk/clk_summary" ]; then show /sys/kernel/debug/clk/clk_summary clk_summary
    else unmeasured "debugfs clk_summary not readable (debugfs not mounted is not mounted here: read-only script)"; fi
    show /proc/cpuinfo cpuinfo
}

case "${1:-facts}" in
    facts) facts ;;
    dump-mtd0) cat "$R/dev/mtd0" ;;
    *) echo "usage: readonly-measure.sh facts|dump-mtd0" >&2; exit 64 ;;
esac
