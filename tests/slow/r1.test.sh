# Slow tier: R1 reproducibility, two assemblies from the same built tree (#45).
RDS="$(repo_root)/env/rds"
EV="$(repo_root)/../../data/build-evidence"

OUT="$(repo_root)/../../build/br-out/rds_control"

test_two_assemblies_give_identical_manifests() {
    local rc=0 out; out=$("$RDS" repro 2>&1) || rc=$?
    assert_eq 0 "$rc" "env/rds repro"; assert_contains "$out" "identical"
    # #92: every artifact is compared, not the rootfs alone, and the run
    # leaves images/ whole. A count, so an empty assembly cannot pass.
    local d n
    for d in assembly-A assembly-B images; do
        n=0
        [ -s "$OUT/$d/zImage" ] && n=$((n + 1))
        [ -s "$OUT/$d/rootfs.squashfs" ] && n=$((n + 1))
        ls "$OUT/$d/"*.dtb >/dev/null 2>&1 && n=$((n + 1))
        assert_eq 3 "$n" "$d holds $(ls "$OUT/$d" | tr '\n' ' ')"
    done
}

test_a_planted_difference_fails_and_keeps_evidence() {
    # The instrument must see the defect it exists for.
    local rc=0 out before after; before=$(ls "$EV" 2>/dev/null | wc -l)
    out=$(RDS_R1_PLANT=1 "$RDS" repro 2>&1) || rc=$?
    after=$(ls "$EV" 2>/dev/null | wc -l)
    assert_eq 1 "$rc" "a planted difference must fail R1"
    assert_contains "$out" "DIFFER"
    [ "$after" -gt "$before" ] || fail "no evidence kept under data/build-evidence"
}
