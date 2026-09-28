# tools/layout: one home for UBI volume sizes, checked against the measured device (#20).
LAYOUT="$(repo_root)/tools/layout"
REAL="$(repo_root)/os/board/rds-control/layout.toml"

mutate() { # python expression over the parsed text -> fixture path
    local f; f=$(mktemp --suffix=.toml)
    python3 - "$REAL" "$f" "$1" <<'PY'
import sys
src, dst, expr = sys.argv[1:]
t = open(src).read()
a, b = expr.split('=>')
assert a in t, f"fixture anchor not found: {a!r}"
open(dst, 'w').write(t.replace(a, b, 1))
PY
    printf '%s' "$f"
}

test_the_committed_layout_passes_and_prints_each_sum() {
    local rc=0 out
    out=$("$LAYOUT" check "$REAL" 2>&1) || rc=$?
    assert_eq 0 "$rc"
    assert_contains "$out" "stock: 3951 of 3951 LEB"
    assert_contains "$out" "L1: 3951 of 3951 LEB"
    assert_contains "$out" "L2: 3951 of 3951 LEB"
}

test_a_layout_that_overflows_the_device_fails() {
    local f rc=0 out
    f=$(mutate 'name = "xtest", lebs = 2=>name = "xtest", lebs = 3')
    out=$("$LAYOUT" check "$f" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "L1"
}

test_shrinking_data_fails() {
    local f rc=0 out
    f=$(mutate 'name = "data", lebs = 3545=>name = "data", lebs = 3544')
    out=$("$LAYOUT" check "$f" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "data"
}

test_a_layout_that_replaces_a_never_write_volume_fails() {
    # factory holds per-unit identity; no layout may replace it.
    local f rc=0 out
    f=$(mutate 'replaces = ["rootfs1"]=>replaces = ["rootfs1", "factory"]')
    out=$("$LAYOUT" check "$f" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "factory"
}

test_bytes_are_computed_from_lebs() {
    local out
    out=$("$LAYOUT" show "$REAL" L1)
    assert_contains "$out" "a_kernel 44 LEB 5586944 B"
}
