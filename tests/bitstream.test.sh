# tools/bitstream-check: the unit's bitstream is recognised by hash, never by name (#23).
CHK="$(repo_root)/tools/bitstream-check"
listfor() { # file -> allowlist naming that file's hash
    local f; f=$(mktemp); printf '# sha256\tbytes\trevision\tsource\n%s\t%s\ttest-rev\tfixture\n' \
        "$(sha256sum < "$1" | cut -d' ' -f1)" "$(stat -c %s "$1")" > "$f"; printf '%s' "$f"
}

test_a_listed_hash_is_known() {
    local b l rc=0 out; b=$(mktemp); head -c 1000 /dev/urandom > "$b"; l=$(listfor "$b")
    out=$("$CHK" --allowlist "$l" "$b" 2>&1) || rc=$?
    assert_eq 0 "$rc"; assert_contains "$out" "known test-rev"
}

test_the_same_name_with_other_bytes_is_unknown() {
    local d b l rc=0 out; d=$(mktemp -d); b=$d/soc_system.rbf
    head -c 1000 /dev/urandom > "$b"; l=$(listfor "$b")
    head -c 1000 /dev/urandom > "$b"
    out=$("$CHK" --allowlist "$l" "$b" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "unknown"
}

test_an_empty_allowlist_is_unmeasured() {
    local b l rc=0; b=$(mktemp); echo x > "$b"; l=$(mktemp); echo '# header only' > "$l"
    "$CHK" --allowlist "$l" "$b" >/dev/null 2>&1 || rc=$?; assert_eq 2 "$rc"
}

test_the_committed_list_holds_the_measured_revision_and_no_bytes() {
    local l="$(repo_root)/data/allowlist/bitstream.tsv"
    assert_contains "$(cat "$l")" "789e72a75f2c9dd9658e75207ae6074801a869c1c064c6dbc8a9d071ac0d8dd5	1544828"
    [ "$(stat -c %s "$l")" -lt 4096 ] || fail "allowlist is suspiciously large: it must hold hashes, never bytes"
    assert_not_contains "$(cat "$l")" "192.168" "no internal file-server paths"
}
