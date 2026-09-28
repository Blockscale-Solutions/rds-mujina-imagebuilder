# ui-accept judges /miner polling by the UI's own stale threshold, not a
# hard-coded poll count (#78).
CAD="$(repo_root)/tools/ui-accept/cadence.mjs"

judge() { # JSON times, end ms, stale ms -> the cadence result as JSON
    node --input-type=module -e "
        import { cadence } from '$CAD';
        console.log(JSON.stringify(cadence($1, $2, $3)));" 2>&1
}

polls() { # first step count -> JSON array of request times
    node -e "console.log(JSON.stringify(Array.from({length: $3}, (_, i) => $1 + i * $2)))"
}

test_polls_every_2_2_s_over_40_s_pass() {
    local out
    out=$(judge "$(polls 300 2200 18)" 40000 4000)   # the #78 case: 18 polls in 40 s
    assert_contains "$out" '"polls":18'
    assert_contains "$out" '"failures":[]'
    assert_contains "$out" '"medianMs":2200'
}

test_polling_that_stops_is_named_even_with_many_polls() {
    local out
    out=$(judge "$(polls 300 2000 5)" 40000 4000)    # the deadlock shape: polls stop at 8.3 s
    assert_contains "$out" "no /miner request in the last 31700 ms"
}

test_one_gap_past_the_stale_threshold_fails() {
    local out
    out=$(judge "[0,2000,4000,9000,11000,13000]" 14000 4000)
    assert_contains "$out" "gap of 5000 ms"
    assert_contains "$out" "stale threshold of 4000 ms"
}

test_a_single_poll_is_not_a_cadence() {
    local out
    out=$(judge "[500]" 1000 4000)
    assert_contains "$out" "polled 1 time"
}

test_the_threshold_comes_from_the_ui_config() {
    local out
    out=$(node --input-type=module -e "
        import { staleAfterMs } from '$CAD';
        console.log(staleAfterMs({ minerIntervalMs: 2000, liveMultiplier: 2 }));
        try { staleAfterMs({ minerIntervalMs: 2000 }); console.log('no throw'); }
        catch (e) { console.log('threw: ' + e.message); }" 2>&1)
    assert_contains "$out" "4000"
    assert_contains "$out" "threw: "
    assert_not_contains "$out" "no throw"
}

test_accept_uses_this_module_and_no_fixed_interval() {
    local src; src=$(cat "$(repo_root)/tools/ui-accept/accept.mjs")
    assert_contains "$src" "from './cadence.mjs'"
    assert_not_contains "$src" "DWELL / 2000"
}
