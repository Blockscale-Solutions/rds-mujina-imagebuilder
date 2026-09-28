# tools/budget: images against their volumes in layout.toml (#21).
BUDGET="$(repo_root)/tools/budget"
REAL="$(repo_root)/os/board/rds-control/layout.toml"
img() { local f; f=$(mktemp); head -c "$1" /dev/zero > "$f"; printf '%s' "$f"; }

test_the_measured_kernel_fits_a_kernel_with_its_headroom_printed() {
    local k rc=0 out; k=$(img 4794016)
    out=$("$BUDGET" --layout "$REAL" L1 "a_kernel=$k" 2>&1) || rc=$?
    assert_eq 0 "$rc"; assert_contains "$out" "a_kernel 4794016 of 5586944 B, headroom 14.2%"
}

test_an_image_larger_than_its_volume_fails() {
    local k f rc=0 out; k=$(img 4794016); f=$(mktemp --suffix=.toml)
    sed 's/name = "a_kernel", lebs = 44/name = "a_kernel", lebs = 37/; s/name = "xtest", lebs = 2/name = "xtest", lebs = 9/' "$REAL" > "$f"
    out=$("$BUDGET" --layout "$f" L1 "a_kernel=$k" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "OVER"
}

test_an_image_with_no_volume_fails() {
    local k rc=0 out; k=$(img 10)
    out=$("$BUDGET" --layout "$REAL" L1 "nosuch=$k" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "nosuch"
}

test_no_images_is_unmeasured() {
    local rc=0
    "$BUDGET" --layout "$REAL" L1 >/dev/null 2>&1 || rc=$?
    assert_eq 2 "$rc"
}
