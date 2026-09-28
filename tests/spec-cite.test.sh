# tools/spec-cite: every requirement id a test or driver cites must exist in the spec (#18).
# Ids are assembled at runtime so this file never contains a literal citation itself.
CITE="$(repo_root)/tools/spec-cite"
id() { printf 'REQ-%s-%s' "$1" "$2"; }

fixture() { # spec-ids... -- cited-ids...  -> dir with spec.md and tree/
    local d; d=$(mktemp -d); mkdir -p "$d/tree"; : > "$d/spec.md"
    while [ "$1" != "--" ]; do printf '### %s\nText.\n' "$1" >> "$d/spec.md"; shift; done; shift
    for c in "$@"; do printf '# covers %s\n' "$c" >> "$d/tree/a.test.sh"; done
    printf '%s' "$d"
}

test_all_cited_ids_present_exits_0() {
    local d rc=0 out; d=$(fixture "$(id UART 1)" "$(id UART 2)" -- "$(id UART 1)")
    out=$("$CITE" --spec "$d/spec.md" "$d/tree" 2>&1) || rc=$?
    assert_eq 0 "$rc"; assert_contains "$out" "1 cited, 1 found"
}

test_a_missing_id_exits_1_and_names_it() {
    local d rc=0 out; d=$(fixture "$(id UART 1)" -- "$(id UART 1)" "$(id PWM 3)")
    out=$("$CITE" --spec "$d/spec.md" "$d/tree" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "$(id PWM 3)"; assert_contains "$out" "a.test.sh"
}

test_an_absent_spec_exits_1_naming_the_file() {
    local d rc=0 out; d=$(fixture -- "$(id UART 1)"); rm "$d/spec.md"
    out=$("$CITE" --spec "$d/spec.md" "$d/tree" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "spec.md"
}

test_no_citations_is_unmeasured() {
    local d rc=0; d=$(fixture "$(id UART 1)" --)
    "$CITE" --spec "$d/spec.md" "$d/tree" >/dev/null 2>&1 || rc=$?
    assert_eq 2 "$rc"
}

test_an_id_prefix_does_not_count_as_present() {
    # Id 1 of a block in the spec must not satisfy a citation of id 12 of that block.
    local d rc=0; d=$(fixture "$(id UART 1)" -- "$(id UART 12)")
    "$CITE" --spec "$d/spec.md" "$d/tree" >/dev/null 2>&1 || rc=$?
    assert_eq 1 "$rc"
}
