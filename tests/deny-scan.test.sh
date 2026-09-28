# tools/deny-scan: no output file may be byte-identical to a vendor file (#24, gate C14).
SCAN="$(repo_root)/tools/deny-scan"
setup() { # -> dir with vendor/, out/, manifest.tsv (sha256 first column), empty exceptions
    local d; d=$(mktemp -d); mkdir -p "$d/vendor/sub" "$d/out/usr/lib"
    head -c 5000 /dev/urandom > "$d/vendor/sub/driver.ko"
    head -c 5000 /dev/urandom > "$d/out/usr/lib/ours.so"
    printf 'sha256\tbytes\tpath\n%s\t5000\tsub/driver.ko\n' "$(sha256sum < "$d/vendor/sub/driver.ko" | cut -d' ' -f1)" > "$d/manifest.tsv"
    printf '# sha256\treason\n' > "$d/exceptions.tsv"
    printf '%s' "$d"
}

test_a_clean_tree_exits_0() {
    local d rc=0; d=$(setup)
    "$SCAN" --manifest "$d/manifest.tsv" --exceptions "$d/exceptions.tsv" "$d/out" >/dev/null 2>&1 || rc=$?
    assert_eq 0 "$rc"
}

test_a_planted_vendor_file_fails_and_is_named() {
    local d rc=0 out; d=$(setup); cp "$d/vendor/sub/driver.ko" "$d/out/usr/lib/renamed.bin"
    out=$("$SCAN" --manifest "$d/manifest.tsv" --exceptions "$d/exceptions.tsv" "$d/out" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "usr/lib/renamed.bin"
}

test_a_vendor_tree_can_be_the_source() {
    local d rc=0; d=$(setup); cp "$d/vendor/sub/driver.ko" "$d/out/x"
    "$SCAN" --tree "$d/vendor" --exceptions "$d/exceptions.tsv" "$d/out" >/dev/null 2>&1 || rc=$?
    assert_eq 1 "$rc"
}

test_no_source_is_unmeasured_never_clean() {
    local d rc=0; d=$(setup)
    "$SCAN" --manifest "$d/nonexistent.tsv" --exceptions "$d/exceptions.tsv" "$d/out" >/dev/null 2>&1 || rc=$?
    assert_eq 2 "$rc"
}

test_an_excepted_hash_passes_but_is_reported_with_its_reason() {
    local d rc=0 out h; d=$(setup); cp "$d/vendor/sub/driver.ko" "$d/out/COPYING"
    h=$(sha256sum < "$d/out/COPYING" | cut -d' ' -f1)
    printf '%s\tpublic licence text, also shipped by upstream\n' "$h" >> "$d/exceptions.tsv"
    out=$("$SCAN" --manifest "$d/manifest.tsv" --exceptions "$d/exceptions.tsv" "$d/out" 2>&1) || rc=$?
    assert_eq 0 "$rc"; assert_contains "$out" "EXCEPTED COPYING: public licence text"
}

test_an_exception_without_a_reason_is_refused() {
    local d rc=0; d=$(setup); printf '%s\t\n' "$(sha256sum < "$d/vendor/sub/driver.ko" | cut -d' ' -f1)" >> "$d/exceptions.tsv"
    "$SCAN" --manifest "$d/manifest.tsv" --exceptions "$d/exceptions.tsv" "$d/out" >/dev/null 2>&1 || rc=$?
    assert_eq 1 "$rc"
}

test_tiny_files_are_skipped_and_counted() {
    local d out; d=$(setup); : > "$d/out/empty"; : > "$d/vendor/empty"
    out=$("$SCAN" --tree "$d/vendor" --exceptions "$d/exceptions.tsv" "$d/out" 2>&1) || true
    assert_contains "$out" "skipped 1 file under 64 B"
}

test_git_metadata_is_ignored_on_both_sides() {
    # Measured 2026-09-24: the vendor reference tree carries its own .git, so git's
    # public sample hooks became "vendor" hashes and matched this repo's .git/hooks.
    local d rc=0 out; d=$(setup); mkdir -p "$d/vendor/.git/hooks" "$d/out/.git/hooks"
    head -c 500 /dev/urandom > "$d/vendor/.git/hooks/pre-commit.sample"
    cp "$d/vendor/.git/hooks/pre-commit.sample" "$d/out/.git/hooks/pre-commit.sample"
    out=$("$SCAN" --tree "$d/vendor" --exceptions "$d/exceptions.tsv" "$d/out" 2>&1) || rc=$?
    assert_eq 0 "$rc"; assert_not_contains "$out" "pre-commit.sample"
}

test_a_single_file_can_be_an_output() {
    # Reported by the Mujina port project: a file argument read "output missing".
    local d rc=0 out; d=$(setup); cp "$d/vendor/sub/driver.ko" "$d/lone.bin"
    out=$("$SCAN" --manifest "$d/manifest.tsv" --exceptions "$d/exceptions.tsv" "$d/lone.bin" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "lone.bin"
    rc=0; "$SCAN" --manifest "$d/manifest.tsv" --exceptions "$d/exceptions.tsv" "$d/out/usr/lib/ours.so" >/dev/null 2>&1 || rc=$?
    assert_eq 0 "$rc" "a clean single file"
}

test_the_tool_names_no_path_to_a_vendor_tree() {
    # No path into anyone's proprietary tree ships (#104): sources come from the
    # caller, as options or environment variables, never from a default.
    local t; t=$(cat "$SCAN")
    assert_not_contains "$t" "/home/"; assert_not_contains "$t" "proprietary"; assert_not_contains "$t" "vendor-docs"
}

test_no_source_given_is_unmeasured() {
    local d rc=0 out; d=$(setup)
    out=$(env -u RDS_DENY_MANIFEST -u RDS_DENY_TREE "$SCAN" --exceptions "$d/exceptions.tsv" "$d/out" 2>&1) || rc=$?
    assert_eq 2 "$rc" "$out"; assert_contains "$out" "no vendor hash source given"
}

test_sources_can_come_from_the_environment() {
    local d rc=0 out; d=$(setup); cp "$d/vendor/sub/driver.ko" "$d/out/x"
    out=$(RDS_DENY_TREE="$d/nowhere:$d/vendor" "$SCAN" --exceptions "$d/exceptions.tsv" "$d/out" 2>&1) || rc=$?
    assert_eq 1 "$rc" "$out"; assert_contains "$out" "VENDOR x"
    rc=0; RDS_DENY_MANIFEST="$d/manifest.tsv" "$SCAN" --exceptions "$d/exceptions.tsv" "$d/out/usr" >/dev/null 2>&1 || rc=$?
    assert_eq 0 "$rc" "a clean tree against an environment manifest"
}
