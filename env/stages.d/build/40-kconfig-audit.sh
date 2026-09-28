#!/usr/bin/env bash
# Every kernel option a variant's fragments request survived into its final
# kernel .config (#41, #77). The variants and their fragments are read from
# os/configs, not listed here (#81).
. "$(dirname "$0")/../../lib.sh"
bad=0
for v in $(rds_variants); do
    args=()
    for f in $(rds_kernel_fragments "$v"); do args+=(--fragment "$f"); done
    [ ${#args[@]} -gt 0 ] || { echo "$v: names no kernel fragments: unmeasured"; exit 2; }
    cfg=$(ls "$RDS_PROJECT"/build/br-out/$v/build/linux-*/.config 2>/dev/null | head -1)
    [ -n "$cfg" ] || { echo "$v: no kernel .config: unmeasured"; exit 2; }
    "$RDS_REPO/tools/kconfig-audit" "${args[@]}" --config "$cfg" | sed "s/^/$v: /" || bad=1
done
exit $bad
