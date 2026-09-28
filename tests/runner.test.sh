# The runner is the instrument every other test relies on, so it is tested first.
RUN="$(repo_root)/tests/run.sh"

fixture() { # name body -> dir containing one test file
    local d; d=$(mktemp -d)
    printf '%s\n' "$2" > "$d/$1.test.sh"
    printf '%s' "$d"
}

test_a_passing_fixture_exits_0_and_counts_it() {
    local d out rc
    d=$(fixture ok 'test_one() { true; }')
    rc=0; out=$(bash "$RUN" "$d" 2>&1) || rc=$?
    assert_eq 0 "$rc" "exit status"
    assert_contains "$out" "ok 1 - ok: test_one"
    assert_contains "$out" "1..1"
}

test_a_failure_mid_body_is_not_ok() {
    # set -e is ignored inside a subshell whose status is tested with || or if.
    # A runner written that way reports this test as passing.
    local d out rc
    d=$(fixture mid 'test_mid() { false; true; }')
    rc=0; out=$(bash "$RUN" "$d" 2>&1) || rc=$?
    assert_eq 1 "$rc" "exit status"
    assert_contains "$out" "not ok 1 - mid: test_mid"
}

test_zero_tests_is_unmeasured_not_pass() {
    local d rc
    d=$(mktemp -d)
    rc=0; bash "$RUN" "$d" >/dev/null 2>&1 || rc=$?
    assert_eq 2 "$rc" "exit status for an empty suite"
}

test_a_file_that_does_not_parse_fails() {
    local d rc out
    d=$(fixture broken 'test_x() { true; ')
    rc=0; out=$(bash "$RUN" "$d" 2>&1) || rc=$?
    assert_eq 1 "$rc" "exit status for an unparseable file"
    assert_contains "$out" "not ok"
}

test_failures_are_counted_in_the_summary() {
    local d out
    d=$(fixture two 'test_a() { true; }
test_b() { false; }')
    out=$(bash "$RUN" "$d" 2>&1) || true
    assert_contains "$out" "# ran 2, failed 1"
}
