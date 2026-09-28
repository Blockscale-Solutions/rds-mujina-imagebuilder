# #58: the board DT reserves a ramoops region inside RAM, clear of the top of
# RAM where U-Boot relocates itself (INFERRED). Whether the unit's SPL scrubs
# SDRAM (ECC) on a warm reset is UNMEASURED until #61.
DTS="$(repo_root)/os/board/rds-control/rds-control.dts"

test_the_board_reserves_a_ramoops_region_inside_ram_and_below_the_top_16_mib() {
    local out
    out=$(python3 - "$DTS" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
mem = re.search(r'memory@0\s*\{[^}]*reg\s*=\s*<0x0\s+(0x[0-9a-fA-F]+)>', s)
ro = re.search(r'ramoops@([0-9a-fA-F]+)\s*\{[^}]*compatible\s*=\s*"ramoops";[^}]*reg\s*=\s*<(0x[0-9a-fA-F]+)\s+(0x[0-9a-fA-F]+)>', s)
if not (mem and ro): print('missing', bool(mem), bool(ro)); sys.exit()
size, base, length = int(mem.group(1), 16), int(ro.group(2), 16), int(ro.group(3), 16)
print('unit-address-matches' if int(ro.group(1), 16) == base else 'unit-address-differs')
print('inside' if base + length <= size else 'outside')
print('clear-of-top' if base + length <= size - (16 << 20) else 'in-top-16MiB')
print('in-reserved-memory' if re.search(r'reserved-memory\s*\{[\s\S]*ramoops@', s) else 'not-reserved')
PY
)
    assert_contains "$out" "unit-address-matches"
    assert_contains "$out" "inside"
    assert_contains "$out" "clear-of-top"
    assert_contains "$out" "in-reserved-memory"
}
