# Slow tier: a real browser against real commits of the Device UI (issue #2).
# Run with: tests/run.sh tests/slow
# The Device UI checkout beside this repository: mujina-frontend (its public
# name), else mujina-bzm2-device-ui; UI_REPO overrides.
if [ -z "${UI_REPO:-}" ]; then
    for c in mujina-frontend mujina-bzm2-device-ui; do
        [ -d "$(repo_root)/../$c" ] && { UI_REPO=$(repo_root)/../$c; break; }
    done
    UI_REPO=${UI_REPO:-$(repo_root)/../mujina-frontend}
fi
# The two trees under test, by commit. A squashed public history lacks these
# private ones: set UI_FROZE and UI_FIXED to that history's equivalents.
UI_FROZE=${UI_FROZE:-84bc182}   # the poller that deadlocked after one request
UI_FIXED=${UI_FIXED:-ad0f17b}   # its fix
ACCEPT="$(repo_root)/tools/ui-accept/accept.mjs"

unpack() { # commit -> directory holding that commit's tree; a missing commit fails, never an empty tree
    local d
    git -C "$UI_REPO" cat-file -e "$1^{commit}" 2>/dev/null \
        || { fail "no commit $1 in $UI_REPO: set UI_REPO, UI_FROZE and UI_FIXED"; return 1; }
    d=$(mktemp -d)
    git -C "$UI_REPO" archive "$1" | tar -x -C "$d"
    printf '%s' "$d"
}

test_the_ui_that_froze_fails_acceptance() {
    local d rc=0 out
    d=$(unpack "$UI_FROZE")
    out=$(node "$ACCEPT" "$d" --scenario nominal-3b 2>&1) || rc=$?
    assert_eq 1 "$rc" "exit status for the deadlocked poller"
    assert_contains "$out" "FAIL"
    assert_contains "$out" "/miner polled 1"
}

test_the_fixed_ui_passes_acceptance() {
    local d rc=0 out
    d=$(unpack "$UI_FIXED")
    out=$(node "$ACCEPT" "$d" --scenario nominal-3b 2>&1) || rc=$?
    printf '%s\n' "$out" >&2
    assert_eq 0 "$rc" "exit status for the fixed poller"
}

test_it_states_what_it_measured() {
    local d out
    d=$(unpack "$UI_FIXED")
    out=$(node "$ACCEPT" "$d" --scenario nominal-3b 2>&1) || true
    assert_contains "$out" "requests by path"
    assert_contains "$out" "view desktop-1440"
    assert_contains "$out" "view phone-400"
}
