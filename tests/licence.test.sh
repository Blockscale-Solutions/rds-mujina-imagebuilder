# One licence, stated once and agreed everywhere (#104): LICENSE holds the decided
# copyright line and GPL-2.0-or-later, NOTICE keeps the names and logos out of it,
# and every SPDX line we write under os/, generated or not, names the same licence.
ROOT="$(repo_root)"
spdx_of_licence() { sed -n 's/^SPDX-License-Identifier: //p' "$ROOT/LICENSE"; }

test_the_licence_carries_the_decided_holders_and_terms() {
    local t; t=$(cat "$ROOT/LICENSE")
    assert_contains "$t" "Copyright (c) 2026 Reckless Systems, The 256 Foundation, and Blockscale Solutions"
    assert_eq "GPL-2.0-or-later" "$(spdx_of_licence)" "the LICENSE's SPDX line"
    assert_contains "$t" "either version 2 of the License, or (at your option) any later version"
    assert_contains "$t" "GNU GENERAL PUBLIC LICENSE"; assert_contains "$t" "Version 2, June 1991"
    assert_contains "$t" "END OF TERMS AND CONDITIONS"
}

test_the_notice_keeps_the_marks_out_of_the_code_licence() {
    local t; t=$(cat "$ROOT/NOTICE")
    assert_contains "$t" "Reckless Systems"; assert_contains "$t" "256 Foundation"; assert_contains "$t" "Blockscale Solutions"
    assert_contains "$t" "not covered by the code licence"
}

test_every_spdx_line_we_write_under_os_names_the_licence() {
    local want f id n=0; want=$(spdx_of_licence)
    [ -n "$want" ] || fail "LICENSE has no SPDX line"
    while IFS= read -r f; do
        n=$((n + 1)); id=$(sed -n 's|.*SPDX-License-Identifier: \([^ */]*\).*|\1|p' "$f" | head -1)
        assert_eq "$want" "$id" "$f"
    done < <(grep -rlE 'SPDX-License-Identifier' "$ROOT/os/board" "$ROOT/os/package")
    [ "$n" -gt 0 ] || fail "no SPDX line under os/: unmeasured"
}

test_the_generated_include_carries_the_licence_first() {
    assert_eq "// SPDX-License-Identifier: $(spdx_of_licence)" "$("$ROOT/tools/hw2dts" dtsi | head -1)"
    assert_eq "// SPDX-License-Identifier: $(spdx_of_licence)" "$(head -1 "$ROOT/os/board/rds-control/rds-fpga.dtsi")"
}
