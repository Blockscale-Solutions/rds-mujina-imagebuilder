# tools/lock-gen: lock rows from Buildroot's show-info and the files actually downloaded (#35).
GEN="$(repo_root)/tools/lock-gen"
setup() { # -> dir with info.json and dl/ for two packages
    local d; d=$(mktemp -d); mkdir -p "$d/dl/foo" "$d/dl/bar"
    head -c 700 /dev/urandom > "$d/dl/foo/foo-1.0.tar.gz"; head -c 900 /dev/urandom > "$d/dl/bar/bar-2.tar.xz"
    cat > "$d/info.json" <<'J'
{"foo": {"type": "target", "version": "1.0", "downloads": [{"source": "foo-1.0.tar.gz", "uris": ["https+https://example.org/foo", "https+https://mirror.example/foo"]}]},
 "bar": {"type": "host", "version": "2", "downloads": [{"source": "bar-2.tar.xz", "uris": ["http|urlencode+http://example.net/b"]}]},
 "virt": {"type": "virtual", "downloads": []}}
J
    printf '%s' "$d"
}

test_rows_carry_the_real_hash_size_path_and_first_url() {
    local d out; d=$(setup); out=$("$GEN" --dl "$d/dl" "$d/info.json")
    assert_contains "$out" "$(sha256sum < "$d/dl/foo/foo-1.0.tar.gz" | cut -d' ' -f1)	700	foo/foo-1.0.tar.gz	https://example.org/foo/foo-1.0.tar.gz"
    assert_contains "$out" "	900	bar/bar-2.tar.xz	http://example.net/b/bar-2.tar.xz"
}
test_rows_from_several_variants_are_merged_once() {
    local d n; d=$(setup); n=$("$GEN" --dl "$d/dl" "$d/info.json" "$d/info.json" | grep -c 'foo-1.0.tar.gz')
    assert_eq 1 "$n"
}
test_a_download_missing_from_the_directory_fails() {
    local d rc=0 out; d=$(setup); rm "$d/dl/bar/bar-2.tar.xz"
    out=$("$GEN" --dl "$d/dl" "$d/info.json" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "bar/bar-2.tar.xz"
}
test_a_file_no_package_claims_fails() {
    local d rc=0 out; d=$(setup); echo stray > "$d/dl/foo/leftover.tar"
    out=$("$GEN" --dl "$d/dl" "$d/info.json" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "foo/leftover.tar"
}

test_urls_mode_lists_every_download_without_a_dl_dir() {
    local d out; d=$(setup); out=$("$GEN" --urls "$d/info.json")
    assert_contains "$out" "https://example.org/foo/foo-1.0.tar.gz"
    assert_contains "$out" "http://example.net/b/bar-2.tar.xz"
}

test_a_package_with_an_unlisted_url_fails_the_lock_check() {
    # #35: a package definition whose URL is not in the lock must fail, before any download.
    local d rc=0 out; d=$(setup)
    "$GEN" --dl "$d/dl" "$d/info.json" > "$d/lock.tsv"
    python3 - "$d/info.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["sneaky"] = {"type": "target", "downloads": [{"source": "sneaky-9.tar.gz", "uris": ["https+https://evil.example/s"]}]}
json.dump(d, open(p, "w"))
PY
    "$GEN" --urls "$d/info.json" > "$d/wanted.txt"
    out=$("$(repo_root)/tools/fetch" --lock "$d/lock.tsv" --check-urls "$d/wanted.txt" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "sneaky-9.tar.gz"
}

test_a_local_source_inside_our_tree_is_not_a_download() {
    # Our own packages are built from os/ in this repo, which git versions: no lock row.
    local d out; d=$(setup)
    python3 - "$d/info.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["ours"] = {"type": "target", "downloads": [{"source": "ours-1.tar.gz", "uris": ["local+/w/os/package/ours/src"]}]}
json.dump(d, open(p, "w"))
PY
    out=$("$GEN" --urls "$d/info.json")
    assert_not_contains "$out" "ours-1.tar.gz"
}

test_a_local_source_outside_our_tree_is_still_wanted() {
    # A local source anywhere else is an input nothing versions: it must be locked or fail.
    local d out; d=$(setup)
    python3 - "$d/info.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["stray"] = {"type": "target", "downloads": [{"source": "stray-1.tar.gz", "uris": ["local+/home/someone/stray"]}]}
json.dump(d, open(p, "w"))
PY
    out=$("$GEN" --urls "$d/info.json")
    assert_contains "$out" "stray-1.tar.gz"
}
