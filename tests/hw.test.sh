# tools/hw2dts: the FPGA blocks' device-tree include is generated from hw.toml, one home (#42).
H="$(repo_root)/tools/hw2dts"
REAL="$(repo_root)/os/board/rds-control/hw.toml"
mut() { local f; f=$(mktemp --suffix=.toml); python3 - "$REAL" "$f" "$1" <<'PY'
import sys; s, d, e = sys.argv[1:]; a, b = e.split('=>'); t = open(s).read(); assert a in t, a; open(d, 'w').write(t.replace(a, b, 1))
PY
printf '%s' "$f"; }

test_every_block_becomes_a_node_with_its_reg_and_irq() {
    local out; out=$("$H" dtsi "$REAL")
    assert_contains "$out" "chain-uart0@c0050000"
    assert_contains "$out" "reg = <0xc0050000 0x200>;"
    assert_contains "$out" "interrupts = <GIC_SPI 41 IRQ_TYPE_LEVEL_HIGH>;"
    assert_contains "$out" 'linux,uio-name = "chain-uart0";'
    assert_contains "$out" "tacho3@ff2460c0"
}
test_the_committed_file_checks_clean() {
    local rc=0; "$H" check "$REAL" >/dev/null 2>&1 || rc=$?; assert_eq 0 "$rc"
}
test_overlapping_blocks_fail() {
    local f rc=0 out; f=$(mut 'base = 0xc0050200=>base = 0xc0050100')
    out=$("$H" check "$f" 2>&1) || rc=$?; assert_eq 1 "$rc"; assert_contains "$out" "overlap"
}
test_a_field_without_provenance_fails() {
    local f rc=0; f=$(mut 'irq_source = "MEASURED=>irq_source_removed = "MEASURED')
    "$H" check "$f" >/dev/null 2>&1 || rc=$?; assert_eq 1 "$rc"
}
test_a_measured_irq_must_match_the_stock_hwirq() {
    # /proc/interrupts on the stock unit lists GIC hwirq = SPI + 32.
    local f rc=0 out; f=$(mut 'spi = 41=>spi = 44')
    out=$("$H" check "$f" 2>&1) || rc=$?; assert_eq 1 "$rc"; assert_contains "$out" "chain-uart0"
}
test_a_gpio_hog_anywhere_in_a_dts_fails() {
    local d rc=0 out; d=$(mktemp); printf '/ { gpio@0 { psu-enable { gpio-hog; gpios = <3 0>; output-high; }; }; };\n' > "$d"
    out=$("$H" check-dts "$d" 2>&1) || rc=$?; assert_eq 1 "$rc"; assert_contains "$out" "gpio-hog"
}

good_dtb_text() { # decompiled-DTB text as dtc prints it, generated from hw.toml itself
    python3 - "$REAL" <<'PY'
import sys, tomllib
T = {"level-high": 4, "edge-rising": 1, "edge-falling": 2}
print("/dts-v1/;\n/ {\n\tsoc {")
for b in tomllib.load(open(sys.argv[1], "rb"))["block"]:
    if b["access"] == "none":
        continue
    print(f"\t\t{b['name']}@{b['base']:x} {{\n\t\t\treg = <0x{b['base']:x} 0x{b['size']:x}>;")
    if "spi" in b:
        print(f"\t\t\tinterrupts = <0x00 0x{b['spi']:02x} 0x{T[b['trigger']]:02x}>;")
    print("\t\t};")
print("\t};\n};")
PY
}
test_a_dtb_that_matches_hw_toml_verifies() {
    local f rc=0; f=$(mktemp); good_dtb_text > "$f"
    "$H" verify-dtb "$f" >/dev/null 2>&1 || rc=$?; assert_eq 0 "$rc"
}
test_a_dtb_with_a_wrong_interrupt_fails_and_names_the_block() {
    local f rc=0 out; f=$(mktemp); good_dtb_text | sed '/tacho1@/,/};/ s/0x3a/0x3b/' > "$f"
    out=$("$H" verify-dtb "$f" 2>&1) || rc=$?; assert_eq 1 "$rc"; assert_contains "$out" "tacho1"
}
test_a_dtb_missing_a_block_fails() {
    local f rc=0 out; f=$(mktemp); good_dtb_text | sed '/pwm2@/,/};/d' > "$f"
    out=$("$H" verify-dtb "$f" 2>&1) || rc=$?; assert_eq 1 "$rc"; assert_contains "$out" "pwm2"
}

# Provenance has a shape (#104): a MEASURED fact names its capture (u:...), and a
# vendor-derived one names the measurement that will replace it (pending #N).
test_a_measured_source_without_its_capture_fails() {
    local f rc=0 out
    f=$(mut 'reg_source = "MEASURED: stock boot log mapbase, u:inventory/20260915T014110Z/logs.txt"=>reg_source = "MEASURED: stock boot log mapbase"')
    out=$("$H" check "$f" 2>&1) || rc=$?; assert_eq 1 "$rc" "$out"; assert_contains "$out" "chain-uart0"; assert_contains "$out" "capture"
}
test_a_vendor_derived_source_must_name_what_replaces_it() {
    local f rc=0 out tag; tag="$(printf '%s-%s' VENDOR DERIVED)"
    f=$(mut "reg_source = \"MEASURED: stock /proc/iomem, u:inventory/kernel-20260924/unit-kernel-facts.txt\"=>reg_source = \"$tag: read somewhere\"")
    out=$("$H" check "$f" 2>&1) || rc=$?; assert_eq 1 "$rc" "$out"; assert_contains "$out" "pending"
}
test_a_source_without_a_known_tag_fails() {
    local f rc=0 out
    f=$(mut 'reg_source = "MEASURED: stock /proc/iomem=>reg_source = "SEEN: stock /proc/iomem')
    out=$("$H" check "$f" 2>&1) || rc=$?; assert_eq 1 "$rc" "$out"; assert_contains "$out" "tag"
}
test_the_board_blocks_carry_no_stock_source_reading() {
    # No FIFO flags or register notes that no capture measured; the tool that needs
    # FIFO facts reports them UNMEASURED instead (#27).
    local t; t=$(cat "$REAL")
    assert_not_contains "$t" "fifo_source"; assert_not_contains "$t" "rx_dma"
    assert_not_contains "$t" "stock device tree"; assert_not_contains "$t" "stock tree"
    assert_not_contains "$t" "register draft"; assert_not_contains "$t" "stock driver"
}

test_a_device_tree_measured_interrupt_must_match_the_booted_tree() {
    # 2026-09-28: pio0's interrupt is measured only in the unit's booted device tree
    # (#61); a chained GIC line never appears in /proc/interrupts. The tree's raw value
    # is the cross-check: the SPI and the trigger must both agree with it.
    local f out rc=0
    out=$("$H" check "$REAL" 2>&1) || rc=$?; assert_eq 0 "$rc" "$out"
    f=$(mut 'dt_interrupts = "0 0x3d 1"=>dt_interrupts = "0 0x3e 1"'); rc=0
    out=$("$H" check "$f" 2>&1) || rc=$?; assert_eq 1 "$rc" "$out"; assert_contains "$out" "fpga-pio0"
    f=$(mut 'dt_interrupts = "0 0x3d 1"=>dt_interrupts = "0 0x3d 4"'); rc=0
    out=$("$H" check "$f" 2>&1) || rc=$?; assert_eq 1 "$rc" "$out"; assert_contains "$out" "trigger"
    f=$(mut 'dt_interrupts = "0 0x3d 1"=>dt_note = "none"'); rc=0
    out=$("$H" check "$f" 2>&1) || rc=$?; assert_eq 1 "$rc" "$out"; assert_contains "$out" "needs stock_hwirq or dt_interrupts"
}
