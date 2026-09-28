# env/rds: one entry point; each verb runs its stages in order, fail fast (#32, gate C1).
RDS="$(repo_root)/env/rds"
stages() { # "verb:NN-name:rc ..." -> stage root
    local d; d=$(mktemp -d)
    for s in "$@"; do
        IFS=: read -r v n rc <<< "$s"; mkdir -p "$d/$v"
        printf '#!/bin/sh\necho "ran %s"\nexit %s\n' "$n" "$rc" > "$d/$v/$n.sh"; chmod +x "$d/$v/$n.sh"
    done
    printf '%s' "$d"
}
go() { local rc=0; RDS_STAGES="$1" "$RDS" "$2" >"$1/out" 2>&1 || rc=$?; printf '%s' "$rc"; }

test_a_verb_with_no_stages_is_unmeasured() {
    local d; d=$(mktemp -d); assert_eq 2 "$(go "$d" build)"
}
test_all_stages_passing_exits_0() {
    local d; d=$(stages build:10-a:0 build:20-b:0); assert_eq 0 "$(go "$d" build)"
}
test_a_failing_stage_fails_the_verb_and_stops_later_stages() {
    local d; d=$(stages build:10-a:0 build:20-b:1 build:30-c:0)
    assert_eq 1 "$(go "$d" build)"
    assert_contains "$(cat "$d/out")" "ran 20-b"; assert_not_contains "$(cat "$d/out")" "ran 30-c"
    assert_contains "$(cat "$d/out")" "not run: 30-c"
}
test_an_unmeasured_stage_makes_the_verb_unmeasured_not_pass() {
    local d; d=$(stages test:10-a:0 test:20-b:2); assert_eq 2 "$(go "$d" test)"
}
test_stages_run_in_name_order() {
    local d; d=$(stages build:20-b:0 build:10-a:0); go "$d" build >/dev/null
    assert_eq "ran 10-a,ran 20-b," "$(grep '^ran' "$d/out" | tr '\n' ',')"
}
test_an_unknown_verb_exits_1() {
    local d; d=$(mktemp -d); assert_eq 1 "$(go "$d" frobnicate)"
}
