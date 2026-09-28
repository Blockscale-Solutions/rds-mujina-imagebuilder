# tools/version: versions from git, strictly ordered, never field-by-field (#22).
V="$(repo_root)/tools/version"
cmp_() { local rc=0; "$V" compare "$1" "$2" >/dev/null 2>&1 || rc=$?; printf '%s' "$rc"; }  # 0 same, 10 newer(A>B), 11 older, 2 refused

test_a_table_orders_strictly_and_transitively() {
    local vs=(rds-0.1.0-0-gaaaaaaa-100 rds-0.1.0-3-gbbbbbbb-90 rds-0.1.1-0-gccccccc-80
              rds-0.2.0-0-gddddddd-300 rds-0.10.0-0-geeeeeee-50 rds-1.0.0-7-gfffffff-60)
    local i j
    for ((i = 0; i < ${#vs[@]}; i++)); do for ((j = 0; j < ${#vs[@]}; j++)); do
        if ((i < j)); then assert_eq 11 "$(cmp_ "${vs[i]}" "${vs[j]}")" "${vs[i]} < ${vs[j]}"
        elif ((i > j)); then assert_eq 10 "$(cmp_ "${vs[i]}" "${vs[j]}")" "${vs[i]} > ${vs[j]}"
        else assert_eq 0 "$(cmp_ "${vs[i]}" "${vs[j]}")"; fi
    done; done
}

test_a_later_field_never_outvotes_an_earlier_one() {
    # A gate that accepted an image when ANY field is larger would call this newer. Ours must call it older.
    assert_eq 11 "$(cmp_ rds-1.1.9-99-gbbbbbbb-900 rds-1.2.0-5-gaaaaaaa-100)"
}

test_same_position_different_commit_is_refused() {
    assert_eq 2 "$(cmp_ rds-0.1.0-3-gaaaaaaa-100 rds-0.1.0-3-gbbbbbbb-100)"
}

test_vendor_and_garbage_strings_are_refused_not_compared() {
    assert_eq 2 "$(cmp_ mjv_2.0.20260914.1857 rds-0.1.0-0-gaaaaaaa-1)"
    assert_eq 2 "$(cmp_ rds-0.1.0-0-gaaaaaaa-1 user@host_2026-09-14)"
}

test_install_policy() {
    local c=rds-0.2.0-0-gddddddd-300 rc
    rc=0; "$V" allow-install "$c" rds-0.2.0-1-g1234567-310 >/dev/null 2>&1 || rc=$?; assert_eq 0 "$rc" "newer"
    rc=0; "$V" allow-install "$c" "$c" >/dev/null 2>&1 || rc=$?; assert_eq 1 "$rc" "same without --reinstall"
    rc=0; "$V" allow-install "$c" "$c" --reinstall >/dev/null 2>&1 || rc=$?; assert_eq 0 "$rc" "same with --reinstall"
    rc=0; "$V" allow-install "$c" rds-0.1.0-0-gaaaaaaa-1 >/dev/null 2>&1 || rc=$?; assert_eq 1 "$rc" "older"
    rc=0; "$V" allow-install "$c" rds-0.1.0-0-gaaaaaaa-1 --downgrade >/dev/null 2>&1 || rc=$?; assert_eq 0 "$rc" "older with --downgrade"
    rc=0; "$V" allow-install "$c" mjv_2.0.1.2 --downgrade --reinstall >/dev/null 2>&1 || rc=$?; assert_eq 2 "$rc" "unparseable, flags or not"
}

test_current_is_derived_from_git_and_refuses_a_dirty_tree() {
    local d out rc=0 h
    d=$(mktemp -d); git -C "$d" init -q -b main
    GIT_COMMITTER_DATE=2026-09-24T12:00:00Z git -C "$d" -c user.name=t -c user.email=t@t commit -q --allow-empty -m a
    git -C "$d" tag v0.1.0
    GIT_COMMITTER_DATE=2026-09-24T13:00:00Z git -C "$d" -c user.name=t -c user.email=t@t commit -q --allow-empty -m b
    h=$(git -C "$d" rev-parse --short=7 HEAD)
    out=$("$V" current --repo "$d")
    assert_eq "rds-0.1.0-1-g$h-1790254800" "$out"
    touch "$d/x"; git -C "$d" add x
    "$V" current --repo "$d" >/dev/null 2>&1 || rc=$?; assert_eq 1 "$rc" "dirty tree"
}
