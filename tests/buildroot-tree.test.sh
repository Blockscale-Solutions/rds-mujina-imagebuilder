# #94: Buildroot's source tree comes from the locked tarball, by a stage,
# re-checked by hash before extraction, into a fresh directory every run.
STAGE="$(repo_root)/env/stages.d/build/05-buildroot-tree.sh"

tree_fixture() { # -> dir with lock.tsv, mirror/ and a tiny locked buildroot tarball
    local d h src; d=$(mktemp -d); src=$(mktemp -d)
    mkdir -p "$src/buildroot-2026.08/support" "$d/mirror"
    echo 'all:' > "$src/buildroot-2026.08/Makefile"; echo x > "$src/buildroot-2026.08/support/marker"
    tar -C "$src" -cJf "$d/br.tar.xz" buildroot-2026.08
    h=$(sha256sum < "$d/br.tar.xz" | cut -d' ' -f1); cp "$d/br.tar.xz" "$d/mirror/$h"
    printf '%s\t%s\tbuildroot-2026.08.tar.xz\thttps://example.invalid/br.tar.xz\n' "$h" "$(stat -c %s "$d/br.tar.xz")" > "$d/lock.tsv"
    printf '%s' "$d"
}
run_stage() { # fixture -> output; status in $rc
    rc=0; out=$(RDS_LOCK="$1/lock.tsv" RDS_MIRROR="$1/mirror" RDS_BR_DIR="$1/br" "$STAGE" 2>&1) || rc=$?
}

test_the_locked_tarball_is_extracted_fresh() {
    local d out rc; d=$(tree_fixture)
    mkdir -p "$d/br/buildroot-2026.08"; echo stale > "$d/br/buildroot-2026.08/leftover"
    run_stage "$d"
    assert_eq 0 "$rc" "$out"
    [ -f "$d/br/buildroot-2026.08/support/marker" ] || fail "not extracted: $(ls -R "$d/br" | head)"
    [ ! -e "$d/br/buildroot-2026.08/leftover" ] || fail "an old tree carried over"
}

test_a_mirror_entry_that_does_not_match_the_lock_fails_and_extracts_nothing() {
    local d out rc h; d=$(tree_fixture); h=$(cut -f1 "$d/lock.tsv")
    printf 'x' >> "$d/mirror/$h"
    run_stage "$d"
    assert_eq 1 "$rc" "$out"
    [ ! -e "$d/br/buildroot-2026.08" ] || fail "extracted from bytes that do not match the lock"
}

test_no_lock_row_is_unmeasured() {
    local d out rc; d=$(tree_fixture); : > "$d/lock.tsv"
    run_stage "$d"
    assert_eq 2 "$rc" "$out"
}
