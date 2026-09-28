# tools/verify-release: the Buildroot tarball's hash comes from a signature by a pinned key (#35).
V="$(repo_root)/tools/verify-release"
SIGN="$(repo_root)/tests/fixtures/buildroot-2026.08.tar.xz.sign"
KEY="$(repo_root)/env/keys/buildroot-release.gpg"
FPR=AB07D806D2CE741FB886EE50B025BA8B59C36319
SHA=87aaca4164ea9d5c8085854953018263f7963f07c22e73a2a2185cc98c581c34
run() { local rc=0; "$V" --key "$KEY" --fingerprint "$1" --sign "$2" --name buildroot-2026.08.tar.xz --sha256 "$3" >/dev/null 2>&1 || rc=$?; printf '%s' "$rc"; }

test_the_real_signature_verifies_and_carries_the_locked_hash() {
    assert_eq 0 "$(run $FPR "$SIGN" $SHA)"
}
test_a_tampered_signed_text_fails() {
    local t; t=$(mktemp); sed 's/released Fri/released Sat/' "$SIGN" > "$t"; assert_eq 1 "$(run $FPR "$t" $SHA)"
}
test_a_different_pinned_fingerprint_fails() {
    assert_eq 1 "$(run 0000000000000000000000000000000000000000 "$SIGN" $SHA)"
}
test_a_lock_hash_that_differs_from_the_signed_one_fails() {
    assert_eq 1 "$(run $FPR "$SIGN" "$(printf x | sha256sum | cut -d' ' -f1)")"
}

KSIGN="$(repo_root)/tests/fixtures/kernel-v6.x-sha256sums.asc"
KKEY="$(repo_root)/env/keys/kernel-org-autosigner.gpg"
KFPR=B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1
KSHA=4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0
krun() { local rc=0; "$V" --key "$KKEY" --fingerprint "$KFPR" --sign "$KSIGN" --name "$1" --sha256 "$2" >/dev/null 2>&1 || rc=$?; printf '%s' "$rc"; }

test_the_kernel_checksum_list_format_verifies() {
    # kernel.org lists "<sha256>  <file>" lines, not "SHA256: <sha256>  <file>".
    assert_eq 0 "$(krun linux-6.18.53.tar.xz $KSHA)"
}
test_a_kernel_name_prefix_does_not_match_a_longer_name() {
    # linux-6.18.5 must not match the line for linux-6.18.53.
    assert_eq 1 "$(krun linux-6.18.5.tar.xz $KSHA)"
}
