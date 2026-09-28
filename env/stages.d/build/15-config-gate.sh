#!/usr/bin/env bash
# Seconds, before any compile (#35, #36): configure every variant and fail when
# Buildroot dropped an option we asked for, or when the kernel headers series
# does not match the kernel. The first cold build lost 10 minutes to the
# second of these; configuration alone already knew.
. "$(dirname "$0")/../../lib.sh"
bad=0
for v in $(rds_variants); do
    "$RDS_REPO/env/container.sh" br "$v" config >/dev/null 2>&1 || { echo "FAIL $v: configure"; bad=1; continue; }
    cfg=$RDS_PROJECT/build/br-out/$v/.config
    "$RDS_REPO/tools/kconfig-audit" --fragment "$RDS_REPO/os/configs/common.fragment" --fragment "$RDS_REPO/os/configs/$v.fragment" --config "$cfg" | sed "s/^/$v: /" || bad=1
    kv=$(sed -n 's/^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="\([0-9]*\)\.\([0-9]*\).*/\1_\2/p' "$cfg")
    if ! grep -q "^BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_${kv}=y" "$cfg"; then
        echo "FAIL $v: kernel is ${kv/_/.} but the toolchain's kernel headers series is not declared as ${kv/_/.}"; bad=1
    fi
done
# Every download the configured variants want must be in the lock (#35): a
# package added without locking its source fails here, before any compile.
"$RDS_REPO/tools/lock-gen" --urls $(for v in $(rds_variants); do echo "$RDS_PROJECT/build/br-out/$v/show-info.json"; done) > "$RDS_TMPDIR/wanted-urls.txt" || bad=1
"$RDS_REPO/tools/fetch" --lock "$RDS_LOCK" --check-urls "$RDS_TMPDIR/wanted-urls.txt" || bad=1
exit $bad
