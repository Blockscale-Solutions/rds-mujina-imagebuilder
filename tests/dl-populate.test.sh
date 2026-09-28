# tools/dl-populate: the offline download dir holds exactly the locked, verified bytes (#36).
POP="$(repo_root)/tools/dl-populate"
setup() {
    local d h f; d=$(mktemp -d); mkdir -p "$d/mirror"; printf '# header\n' > "$d/lock.tsv"
    for n in foo/foo-1.tar.gz bar/bar-2.tar.xz; do f=$(mktemp); head -c 300 /dev/urandom > "$f"
        h=$(sha256sum < "$f" | cut -d' ' -f1); cp "$f" "$d/mirror/$h"; printf '%s\t300\t%s\thttps://x/%s\n' "$h" "$n" "$n" >> "$d/lock.tsv"; done
    printf '%s\t601\tbuildroot-2026.08.tar.xz.sign\thttps://x/s\n' "$(printf s | sha256sum | cut -d' ' -f1)" >> "$d/lock.tsv"
    printf '%s' "$d"
}
test_package_rows_land_at_their_paths_with_their_bytes() {
    local d rc=0; d=$(setup)
    "$POP" --lock "$d/lock.tsv" --mirror "$d/mirror" --dl "$d/dl" >/dev/null 2>&1 || rc=$?
    assert_eq 0 "$rc"; [ -f "$d/dl/foo/foo-1.tar.gz" ] || fail "foo missing"
    assert_eq "$(awk -F'\t' '$3=="foo/foo-1.tar.gz"{print $1}' "$d/lock.tsv")" "$(sha256sum < "$d/dl/foo/foo-1.tar.gz" | cut -d' ' -f1)"
}
test_rows_without_a_package_dir_are_not_placed() {
    # Also requires the package rows to be placed, so an absent tool cannot pass it.
    local d; d=$(setup); "$POP" --lock "$d/lock.tsv" --mirror "$d/mirror" --dl "$d/dl" >/dev/null 2>&1 || true
    [ -f "$d/dl/foo/foo-1.tar.gz" ] || fail "package rows were not placed, so this measured nothing"
    [ ! -e "$d/dl/buildroot-2026.08.tar.xz.sign" ] || fail "a non-package row was placed in dl"
}
test_a_stale_extra_file_in_dl_is_removed() {
    local d; d=$(setup); mkdir -p "$d/dl/foo"; echo old > "$d/dl/foo/old.tar"
    "$POP" --lock "$d/lock.tsv" --mirror "$d/mirror" --dl "$d/dl" >/dev/null 2>&1
    [ ! -e "$d/dl/foo/old.tar" ] || fail "unlocked file left in the offline dl dir"
}
test_a_corrupt_mirror_entry_fails() {
    local d rc=0 h; d=$(setup); h=$(awk -F'\t' '$3=="bar/bar-2.tar.xz"{print $1}' "$d/lock.tsv"); echo x >> "$d/mirror/$h"
    "$POP" --lock "$d/lock.tsv" --mirror "$d/mirror" --dl "$d/dl" >/dev/null 2>&1 || rc=$?
    assert_eq 1 "$rc"
}
