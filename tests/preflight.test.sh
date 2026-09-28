# env/rds preflight: cheap host checks before any container (#33, gate C2).
ST="$(repo_root)/env/stages.d/preflight"
stage() { local rc=0; "$ST/$1" >"$OUT" 2>&1 || rc=$?; printf '%s' "$rc"; }
OUT=$(mktemp)

test_a_tmpfs_tmpdir_fails_and_is_named() {
    assert_eq 1 "$(RDS_TMPDIR=/dev/shm stage 10-tmpdir.sh)"; assert_contains "$(cat "$OUT")" "tmpfs"
}
test_a_disk_tmpdir_passes() {
    local d; d=$(build_tmp)
    assert_eq 0 "$(RDS_TMPDIR=$d stage 10-tmpdir.sh)"; rmdir "$d"
}
test_disk_under_the_floor_fails() {
    assert_eq 1 "$(RDS_DISK_FLOOR_GB=999999 stage 20-disk.sh)"
}
lockfix() { # -> dir with lock.tsv and mirror/ holding every entry
    local d h f; d=$(mktemp -d); mkdir -p "$d/mirror"; printf '# sha256\tbytes\tname\turl\n' > "$d/lock.tsv"
    for n in a b; do f=$(mktemp); head -c 300 /dev/urandom > "$f"; h=$(sha256sum < "$f" | cut -d' ' -f1)
        cp "$f" "$d/mirror/$h"; printf '%s\t300\t%s.tar\thttps://example.invalid/%s\n' "$h" "$n" "$n" >> "$d/lock.tsv"; done
    printf '%s' "$d"
}
test_a_complete_mirror_passes() {
    local d; d=$(lockfix); assert_eq 0 "$(RDS_LOCK=$d/lock.tsv RDS_MIRROR=$d/mirror stage 50-lock.sh)"
}
test_no_mirror_yet_is_unmeasured_not_a_failure() {
    # A fresh clone has fetched nothing: like a missing lock, that is unmeasured.
    # A mirror that exists but lacks an entry still fails (below).
    local d; d=$(lockfix)
    assert_eq 2 "$(RDS_LOCK=$d/lock.tsv RDS_MIRROR=$d/never-fetched stage 50-lock.sh)"; assert_contains "$(cat "$OUT")" "fetch"
}
test_a_mirror_missing_an_entry_fails_and_names_it() {
    local d; d=$(lockfix); rm "$d/mirror/$(awk -F'\t' '$3=="b.tar"{print $1}' "$d/lock.tsv")"
    assert_eq 1 "$(RDS_LOCK=$d/lock.tsv RDS_MIRROR=$d/mirror stage 50-lock.sh)"; assert_contains "$(cat "$OUT")" "b.tar"
}
test_a_corrupted_mirror_entry_fails() {
    local d h; d=$(lockfix); h=$(awk -F'\t' '$3=="a.tar"{print $1}' "$d/lock.tsv"); echo x >> "$d/mirror/$h"
    assert_eq 1 "$(RDS_LOCK=$d/lock.tsv RDS_MIRROR=$d/mirror stage 50-lock.sh)"; assert_contains "$(cat "$OUT")" "a.tar"
}
test_no_lock_is_unmeasured() {
    assert_eq 2 "$(RDS_LOCK=/nonexistent/lock.tsv stage 50-lock.sh)"
}
test_a_hand_edited_generated_file_fails() {
    local d; d=$(mktemp -d); echo "generated 1" > "$d/out.txt"
    printf '%s\techo "generated 1"\n' "$d/out.txt" > "$d/gen.tsv"
    assert_eq 0 "$(RDS_GENERATED=$d/gen.tsv stage 60-generated.sh)"
    echo "hand edit" >> "$d/out.txt"
    assert_eq 1 "$(RDS_GENERATED=$d/gen.tsv stage 60-generated.sh)"; assert_contains "$(cat "$OUT")" "out.txt"
}
test_the_whole_preflight_finishes_under_60_s() {
    # Run in a clean clone of HEAD, on disk: the version stage rightly refuses
    # a dirty tree, so this must not depend on what is uncommitted right now.
    local w c s=$SECONDS rc=0
    w=$(build_tmp); c=$w/p/git/r
    git clone -q "$(repo_root)" "$c"
    RDS_TMPDIR=$w/tmp RDS_MIRROR="$(repo_root)/../../archive/mirror" "$c/env/rds" preflight > "$w/out" 2>&1 || rc=$?
    [ $((SECONDS - s)) -lt 60 ] || fail "preflight took $((SECONDS - s)) s"
    [ "$rc" != 1 ] || fail "preflight FAILED in a clean clone: $(tail -3 "$w/out")"
    rm -rf "$w"
}
