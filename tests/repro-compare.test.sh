# tools/repro-compare: two manifests must match except for listed, reasoned differences (#45).
C="$(repo_root)/tools/repro-compare"
fx() { local f; f=$(mktemp); printf '%s\n' "$@" > "$f"; printf '%s' "$f"; }
test_identical_manifests_pass() {
    local a b rc=0; a=$(fx 'f	/bin/sh	0755	0	0	0	10	aa'); b=$(fx 'f	/bin/sh	0755	0	0	0	10	aa')
    "$C" "$a" "$b" >/dev/null 2>&1 || rc=$?; assert_eq 0 "$rc"
}
test_a_content_difference_fails_and_names_the_path() {
    local a b rc=0 out; a=$(fx 'f	/etc/x	0644	0	0	0	3	aa'); b=$(fx 'f	/etc/x	0644	0	0	0	3	bb')
    out=$("$C" "$a" "$b" 2>&1) || rc=$?; assert_eq 1 "$rc"; assert_contains "$out" "/etc/x"
}
test_a_path_in_only_one_manifest_fails() {
    local a b rc=0; a=$(fx 'f	/a	0644	0	0	0	1	aa' 'f	/b	0644	0	0	0	1	bb'); b=$(fx 'f	/a	0644	0	0	0	1	aa')
    "$C" "$a" "$b" >/dev/null 2>&1 || rc=$?; assert_eq 1 "$rc"
}
test_an_allowed_difference_passes_only_with_a_reason() {
    local a b al rc=0; a=$(fx 'f	/sig.cms	0644	0	0	0	9	aa'); b=$(fx 'f	/sig.cms	0644	0	0	0	9	bb')
    al=$(fx '/sig.cms	CMS envelope carries a signing time'); "$C" --allowed "$al" "$a" "$b" >/dev/null 2>&1 || rc=$?; assert_eq 0 "$rc"
    al=$(fx '/sig.cms	'); rc=0; "$C" --allowed "$al" "$a" "$b" >/dev/null 2>&1 || rc=$?; assert_eq 1 "$rc"
}
test_empty_manifests_are_unmeasured() {
    local a b rc=0; a=$(fx ''); b=$(fx ''); "$C" "$a" "$b" >/dev/null 2>&1 || rc=$?; assert_eq 2 "$rc"
}
