# tools/unit-facts: every fact the design needs from the unit has a value and a source (#61).
FACTS="$(repo_root)/tools/unit-facts"
fx() { local f; f=$(mktemp --suffix=.toml); printf '%s\n' "$@" > "$f"; printf '%s' "$f"; }

test_all_measured_exits_0() {
    local f rc=0; f=$(fx '[[fact]]' 'q = "Q-ECC"' 'key = "a"' 'value = "8"' 'source = "u:x.txt:1"')
    "$FACTS" check "$f" >/dev/null 2>&1 || rc=$?; assert_eq 0 "$rc"
}
test_an_unmeasured_fact_exits_1_and_is_listed() {
    local f rc=0 out; f=$(fx '[[fact]]' 'q = "Q-WDT"' 'key = "watchdog.timeout"' 'value = ""' 'source = ""')
    out=$("$FACTS" check "$f" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "UNMEASURED Q-WDT watchdog.timeout"
}
test_a_value_without_a_source_fails() {
    local f rc=0 out; f=$(fx '[[fact]]' 'q = "Q-ECC"' 'key = "a"' 'value = "8"' 'source = ""')
    out=$("$FACTS" check "$f" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "no source"
}
test_no_facts_is_unmeasured() {
    local f rc=0; f=$(fx '# empty')
    "$FACTS" check "$f" >/dev/null 2>&1 || rc=$?; assert_eq 2 "$rc"
}
test_the_committed_file_covers_every_batched_question() {
    local out; out=$("$FACTS" check 2>&1) || true
    for q in Q-ECC Q-ENV Q-WDT Q-DT Q-UBI Q-BOOT Q-FW Q-CLK; do assert_contains "$out" "$q"; done
}
