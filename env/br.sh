#!/usr/bin/env bash
# Runs INSIDE the build container (#36). Fixed paths, so outputs do not depend
# on where the project lives: /w/br Buildroot (read-only), /w/os our tree
# (read-only), /w/out this variant's output, /w/dl the download directory.
#
#   br.sh VARIANT config|source|build
set -euo pipefail
v=$1 mode=$2
cd /w/br
ext=/w/os; [ "${RDS_PLANT:-0}" = 1 ] && ext=/w/os:/w/plant   # test-only plants (#37, #38)
# Buildroot sizes its jobs with getconf, which ignores a CPU limit (a cgroup
# cpuset or taskset): on the ECC build host, capped to 4 of 72 threads, it ran 73 compilers
# and thrashed (#96). nproc honours the limit; the rule is Buildroot's own.
jobs=$(( $(nproc) + 1 ))
mk() { make O=/w/out BR2_EXTERNAL="$ext" BR2_JLEVEL="$jobs" "$@"; }
support/kconfig/merge_config.sh -m -O /w/out /w/os/configs/common.fragment "/w/os/configs/$v.fragment" >/dev/null
mk olddefconfig >/dev/null
case "$mode" in
    config) mk show-info > /w/out/show-info.json ;;
    source) mk show-info > /w/out/show-info.json; mk source ;;
    build)  start=$(date +%s); mk; printf '%s\t%s\t%d\n' "$v" build $(( $(date +%s) - start )) >> /w/out/stage-times.tsv ;;
    assemble:*)
        # Re-run image assembly over the already-built tree (#45). With
        # RDS_R1_PLANT=1, plant a new file and a fresh mtime first: the
        # instrument check that R1 can see a difference at all.
        label=${mode#assemble:}
        if [ "${RDS_R1_PLANT:-0}" = 1 ]; then
            echo planted > /w/out/target/etc/rds-r1-plant; touch /w/out/target/etc/hostname
        fi
        # The kernel's install stamp outlives images/, so its install steps
        # are re-run too (#92); without that, zImage and the DTB vanish and
        # R1 compares the rootfs alone. Nothing is rebuilt.
        rm -rf /w/out/images; mk linux-reinstall >/dev/null; mk >/dev/null
        rm -rf "/w/out/assembly-$label"; cp -a /w/out/images "/w/out/assembly-$label"
        rm -f /w/out/target/etc/rds-r1-plant
        python3 /w/env/repro-manifest.py "/w/out/assembly-$label" /w/out/host/bin/unsquashfs "/w/out/manifest-$label.tsv" ;;
    pkg:*)
        # One package and what it needs, not the image (the plant gates).
        mk "${mode#pkg:}" ;;
    rebuild-pkg:*)
        # Development loop: rebuild one package, then the images.
        mk "${mode#rebuild-pkg:}-rebuild" >/dev/null; mk ;;
    rebuild-linux)
        # Development loop: re-extract and re-patch the kernel, then rebuild
        # the images. The build verb always starts from a fresh output instead.
        mk linux-dirclean >/dev/null; mk ;;
    *) echo "br.sh: unknown mode $mode" >&2; exit 64 ;;
esac
