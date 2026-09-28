# Built kernel trees carry exactly the committed patches (#51 review G2, G5; test T2),
# and the design's promises about the canary are in the patch (G3; test T3a).
ID="$(repo_root)/tools/patch-identity"

fake_tree() { # dir with one file, and a patch that adds a line to it
    local d; d=$(mktemp -d); mkdir -p "$d/tree/drivers" "$d/patches"
    printf 'a\nb\n' > "$d/tree/drivers/x.c"
    printf -- '--- a/drivers/x.c\n+++ b/drivers/x.c\n@@ -1,2 +1,3 @@\n a\n+canary\n b\n' > "$d/patches/0001-x.patch"
    printf '%s' "$d"
}
test_a_tree_carrying_the_patch_passes() {
    local d rc=0; d=$(fake_tree); printf 'a\ncanary\nb\n' > "$d/tree/drivers/x.c"
    "$ID" --patches "$d/patches" "$d/tree" >/dev/null 2>&1 || rc=$?; assert_eq 0 "$rc"
}
test_a_tree_without_the_patch_fails_and_names_it() {
    local d rc=0 out; d=$(fake_tree)
    out=$("$ID" --patches "$d/patches" "$d/tree" 2>&1) || rc=$?; assert_eq 1 "$rc"; assert_contains "$out" "0001-x.patch"
}
test_a_tree_with_a_different_revision_fails() {
    local d rc=0; d=$(fake_tree); printf 'a\ncanary-old\nb\n' > "$d/tree/drivers/x.c"
    "$ID" --patches "$d/patches" "$d/tree" >/dev/null 2>&1 || rc=$?; assert_eq 1 "$rc"
}
test_no_patches_is_unmeasured() {
    local d rc=0; d=$(fake_tree); rm "$d/patches/"*.patch
    "$ID" --patches "$d/patches" "$d/tree" >/dev/null 2>&1 || rc=$?; assert_eq 2 "$rc"
}
test_the_design_and_the_patch_agree_on_write_protect() {
    # DESIGN.md says the canary holds the controller's write-protect; the patch must do it.
    local design patch; design=$(cat "$(repo_root)/docs/DESIGN.md"); patch=$(cat "$(repo_root)"/os/patches/linux/*.patch)
    case "$design" in *write-protect*|*"write protect"*) assert_contains "$patch" "drivers/mtd/nand/raw/denali.c" "DESIGN.md promises write-protect; no denali.c hunk in the patch" ;; esac
}
