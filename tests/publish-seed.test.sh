# tools/publish-seed: one squashed commit of the committed HEAD, minus .publish-exclude,
# refused while a shipped file carries the vendor-derived marker or the gate fails.
# The marker is assembled at runtime, so this file never carries it and never blocks a seed.
PS="$(repo_root)/tools/publish-seed"
marker() { printf '%s-%s' VENDOR DERIVED; }

gate_ok() { local g; g=$(mktemp); printf '#!/bin/sh\nexit 0\n' > "$g"; chmod +x "$g"; printf '%s' "$g"; }
gate_rc() { local g; g=$(mktemp); printf '#!/bin/sh\necho "gate saw $1"\nexit %s\n' "$1" > "$g"; chmod +x "$g"; printf '%s' "$g"; }

fixture() { # -> a committed repo with public files, private files and an exclude list
    local d; d=$(mktemp -d)
    git -C "$d" init -q -b main
    mkdir -p "$d/docs/notes" "$d/tools"
    printf 'public\n' > "$d/a.txt"
    printf 'private\n' > "$d/docs/private.md"
    printf 'lab note\n' > "$d/docs/notes/x.md"
    printf 'kept\n' > "$d/docs/kept.md"
    printf '#!/bin/sh\necho t\n' > "$d/tools/t.sh"; chmod +x "$d/tools/t.sh"
    printf '*.img\n' > "$d/.gitignore"
    printf 'tracked despite the ignore rule\n' > "$d/tracked.img"
    printf '# internal notes\ndocs/private.md\n\ndocs/notes\n' > "$d/.publish-exclude"
    git -C "$d" add -A; git -C "$d" add -f tracked.img
    GIT_COMMITTER_DATE=2026-09-20T10:00:00Z git -C "$d" -c user.name=t -c user.email=t@t \
        commit -q -m "private history" --date=2026-09-20T09:00:00Z
    printf '%s' "$d"
}

seed() { # repo out [args] -> $out (stdout), $err, $rc
    local e; e=$(mktemp); rc=0
    out=$("$PS" "$1" "$2" "${@:3}" 2>"$e") || rc=$?
    err=$(cat "$e")
}

test_it_seeds_one_commit_of_head_minus_the_excluded_paths() {
    local d o out err rc
    d=$(fixture); o=$(mktemp -d)/seed; seed "$d" "$o" --gate "$(gate_ok)"
    assert_eq 0 "$rc" "$err"
    [ -f "$o/a.txt" ] && [ -f "$o/docs/kept.md" ] && [ -x "$o/tools/t.sh" ] && [ -f "$o/tracked.img" ] || fail "a public file is missing"
    [ ! -e "$o/docs/private.md" ] || fail "an excluded file shipped"
    [ ! -e "$o/docs/notes" ] || fail "an excluded directory shipped"
    [ ! -e "$o/.publish-exclude" ] || fail "the exclude list itself shipped"
    assert_eq 1 "$(git -C "$o" rev-list --count HEAD)" "one commit"
    assert_eq "Ronald <ronald@reckless.systems>" "$(git -C "$o" log -1 --format='%an <%ae>')" "author"
    assert_eq "Ronald <ronald@reckless.systems>" "$(git -C "$o" log -1 --format='%cn <%ce>')" "committer"
    assert_eq "$(git -C "$d" log -1 --format=%ct)" "$(git -C "$o" log -1 --format=%ct)" "committer date from the source HEAD"
    assert_eq "$(git -C "$d" log -1 --format=%ct)" "$(git -C "$o" log -1 --format=%at)" "author date from the source HEAD"
    assert_eq "$(git -C "$o" rev-parse 'HEAD^{tree}')" "$out" "stdout is the tree hash"
    assert_eq "" "$(git -C "$o" status --porcelain)" "a clean seed"
}

test_the_seed_carries_the_committed_bytes_and_modes() {
    local d o out err rc
    d=$(fixture); o=$(mktemp -d)/seed; seed "$d" "$o" --gate "$(gate_ok)"
    assert_eq 0 "$rc" "$err"
    assert_eq "$(git -C "$d" ls-tree -r HEAD -- a.txt tools/t.sh docs/kept.md tracked.img .gitignore)" \
              "$(git -C "$o" ls-tree -r HEAD -- a.txt tools/t.sh docs/kept.md tracked.img .gitignore)"
}

test_it_exports_the_committed_head_never_the_working_tree() {
    local d o out err rc
    d=$(fixture)
    printf 'uncommitted edit\n' > "$d/a.txt"; printf 'untracked\n' > "$d/new.txt"
    printf 'docs/notes\n' > "$d/.publish-exclude"   # the committed list still excludes docs/private.md
    o=$(mktemp -d)/seed; seed "$d" "$o" --gate "$(gate_ok)"
    assert_eq 0 "$rc" "$err"
    assert_eq "public" "$(cat "$o/a.txt")"
    [ ! -e "$o/new.txt" ] || fail "an untracked file shipped"
    [ ! -e "$o/docs/private.md" ] || fail "the working tree's exclude list was used"
}

test_the_seed_is_reproducible() {
    local d o1 o2 out err rc c1
    d=$(fixture)
    o1=$(mktemp -d)/seed; seed "$d" "$o1" --gate "$(gate_ok)"; assert_eq 0 "$rc" "$err"
    c1=$(git -C "$o1" rev-parse HEAD)
    o2=$(mktemp -d)/seed; seed "$d" "$o2" --gate "$(gate_ok)"; assert_eq 0 "$rc" "$err"
    assert_eq "$c1" "$(git -C "$o2" rev-parse HEAD)" "same HEAD, same seed commit"
}

test_a_marked_file_is_refused_and_each_line_named() {
    local d o out err rc
    d=$(fixture)
    printf 'one\ntwo\nbase from %s material\nfour\n%s again\n' "$(marker)" "$(marker)" > "$d/docs/kept.md"
    git -C "$d" commit -q -am marked
    o=$(mktemp -d)/seed; seed "$d" "$o" --gate "$(gate_ok)"
    assert_eq 1 "$rc" "$err"
    assert_contains "$err" "docs/kept.md:3:"
    assert_contains "$err" "docs/kept.md:5:"
    [ ! -e "$o" ] || fail "a refused seed left its out-dir"
}

test_a_marker_in_an_excluded_file_does_not_block() {
    local d o out err rc
    d=$(fixture); printf '%s\n' "$(marker)" > "$d/docs/private.md"; git -C "$d" commit -q -am marked
    o=$(mktemp -d)/seed; seed "$d" "$o" --gate "$(gate_ok)"
    assert_eq 0 "$rc" "$err"
}

test_a_failing_gate_refuses() {
    local d o out err rc
    d=$(fixture); o=$(mktemp -d)/seed; seed "$d" "$o" --gate "$(gate_rc 1)"
    assert_eq 1 "$rc" "$err"
    assert_contains "$err" "gate"
    [ ! -e "$o" ] || fail "a refused seed left its out-dir"
}

test_the_gate_scans_the_export_not_the_source() {
    local d o g out err rc
    d=$(fixture); g=$(mktemp)
    printf '#!/bin/sh\n[ -f "$1/a.txt" ] && [ ! -e "$1/docs/private.md" ] && [ ! -e "$1/.git" ]\n' > "$g"; chmod +x "$g"
    o=$(mktemp -d)/seed; seed "$d" "$o" --gate "$g"
    assert_eq 0 "$rc" "$err"
}

test_a_missing_gate_is_unmeasured() {
    local d o out err rc
    d=$(fixture); o=$(mktemp -d)/seed; seed "$d" "$o" --gate /nonexistent/gate.sh
    assert_eq 2 "$rc" "$err"
    assert_contains "$err" "/nonexistent/gate.sh"
    [ ! -e "$o" ] || fail "an unmeasured seed left its out-dir"
}

test_the_default_gate_comes_from_the_environment_file() {
    local d o out err rc
    d=$(fixture); o=$(mktemp -d)/seed
    rc=0; err=$(RDS_PUBLISH_GATE=/nonexistent/default-gate.sh "$PS" "$d" "$o" 2>&1 >/dev/null) || rc=$?
    assert_eq 2 "$rc" "$err"; assert_contains "$err" "/nonexistent/default-gate.sh"
    rc=0; RDS_PUBLISH_GATE=$(gate_ok) "$PS" "$d" "$o" >/dev/null 2>&1 || rc=$?
    assert_eq 0 "$rc"
}

test_an_existing_out_dir_is_refused_and_left_alone() {
    local d o out err rc
    d=$(fixture); o=$(mktemp -d); printf 'mine\n' > "$o/keep"
    seed "$d" "$o" --gate "$(gate_ok)"
    assert_eq 1 "$rc" "$err"; assert_contains "$err" "exists"
    assert_eq "mine" "$(cat "$o/keep")"; [ ! -e "$o/.git" ] || fail "wrote into an existing directory"
}

test_an_exclude_line_that_matches_nothing_is_refused() {
    # A renamed private file would otherwise ship while its stale line still reads as protection.
    local d o out err rc
    d=$(fixture); printf 'docs/renamed-away.md\n' >> "$d/.publish-exclude"; git -C "$d" commit -q -am stale
    o=$(mktemp -d)/seed; seed "$d" "$o" --gate "$(gate_ok)"
    assert_eq 1 "$rc" "$err"; assert_contains "$err" "docs/renamed-away.md"
}

test_exclude_globs_do_not_cross_directories_unless_asked() {
    # docs/n-*2.md would also match docs/n-deep/x-2.md if the star crossed the slash.
    local d o out err rc
    d=$(fixture); mkdir -p "$d/docs/n-deep"; printf 'x\n' > "$d/docs/n-deep/x-2.md"; printf 'y\n' > "$d/docs/n-2.md"
    printf 'docs/n-*2.md\n' >> "$d/.publish-exclude"; git -C "$d" add -A; git -C "$d" commit -q -m glob
    o=$(mktemp -d)/seed; seed "$d" "$o" --gate "$(gate_ok)"
    assert_eq 0 "$rc" "$err"
    [ ! -e "$o/docs/n-2.md" ] || fail "the glob did not exclude its match"
    [ -f "$o/docs/n-deep/x-2.md" ] || fail "a single star crossed a directory"
}

test_a_tag_is_made_on_the_seed_commit_when_asked() {
    local d o out err rc
    d=$(fixture); o=$(mktemp -d)/seed; seed "$d" "$o" --gate "$(gate_ok)" --tag v0.0.0
    assert_eq 0 "$rc" "$err"
    assert_eq "$(git -C "$o" rev-parse HEAD)" "$(git -C "$o" rev-parse 'v0.0.0^{commit}')"
    assert_eq "tag" "$(git -C "$o" cat-file -t v0.0.0)" "an annotated tag"
    assert_contains "$(git -C "$o" cat-file -p v0.0.0)" "tagger Ronald <ronald@reckless.systems>"
}

test_not_a_repository_is_unmeasured() {
    local o out err rc
    o=$(mktemp -d)/seed; seed "$(mktemp -d)" "$o" --gate "$(gate_ok)"
    assert_eq 2 "$rc" "$err"
}

test_a_seed_that_would_lose_a_committed_file_is_refused() {
    # git archive honours export-ignore, so the export can silently drop a committed file;
    # the seed must equal HEAD minus the listed exclusions, or nothing is written.
    local d o out err rc
    d=$(fixture); printf 'docs/kept.md export-ignore\n' > "$d/.gitattributes"
    git -C "$d" add .gitattributes; git -C "$d" commit -q -m attrs
    o=$(mktemp -d)/seed; seed "$d" "$o" --gate "$(gate_ok)"
    assert_eq 1 "$rc" "$err"; assert_contains "$err" "docs/kept.md"
    [ ! -e "$o" ] || fail "a refused seed left its out-dir"
}
