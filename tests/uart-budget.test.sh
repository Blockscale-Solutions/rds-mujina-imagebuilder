# The chain UART arithmetic gate (#27, DESIGN 6.2 step 1): can a userspace
# driver serve the receive FIFOs within the deadline and the CPU budget?
UB="$(repo_root)/tools/uart-budget"

hw() { # dir depth dma [buses] -> hw.toml with chain-uart blocks; an empty depth is left out
    local i
    for i in $(seq 0 $(( ${4:-3} - 1 ))); do
        printf '[[block]]\nname = "chain-uart%d"\nkind = "chain-uart"\n' "$i"
        [ -z "$2" ] || printf 'rx_fifo_depth = %s\n' "$2"
        printf 'rx_dma = %s\nfifo_source = "fixture"\n\n' "$3"
    done > "$1/hw.toml"
    printf '[[block]]\nname = "pwm0"\nkind = "pwm"\n' >> "$1/hw.toml"
}

costs() { # dir [wake lo hi] [latency lo hi] -> costs.toml
    cat > "$1/costs.toml" <<EOT
[line]
baud = 5000000
bits_per_char = 11
source = "fixture"

[traffic]
chars_per_s_total = 106000
source = "fixture"

[cost]
wake_us = [${2:-20}, ${3:-20}]
latency_us = [${4:-500}, ${5:-500}]
read_us = [0.3, 0.3]
budget_core = 0.2
margin = 0.5
kernel_preemption = "PREEMPT"
source = "fixture"
EOT
}

run_ub() { # dir [args] -> $out, $rc
    rc=0; out=$("$UB" --hw "$1/hw.toml" "$1/costs.toml" "${@:2}" 2>&1) || rc=$?
}

test_a_64_deep_fifo_without_dma_needs_the_kernel() {
    local d out rc; d=$(mktemp -d); hw "$d" 64 false; costs "$d"; run_ub "$d"
    assert_eq 0 "$rc" "$out"
    assert_contains "$out" "fill 140.8 us"
    assert_contains "$out" "verdict: kernel"
}

test_a_64_deep_fifo_with_dma_needs_the_dma_helper() {
    local d out rc; d=$(mktemp -d); hw "$d" 64 true; costs "$d"; run_ub "$d"
    assert_eq 0 "$rc" "$out"
    assert_contains "$out" "verdict: needs-dma-helper"
}

test_a_1024_deep_fifo_is_served_from_userspace() {
    local d out rc; d=$(mktemp -d); hw "$d" 1024 false; costs "$d"; run_ub "$d"
    assert_eq 0 "$rc" "$out"
    assert_contains "$out" "fill 2252.8 us"
    assert_contains "$out" "verdict: userspace-irq"
}

test_a_missing_depth_is_unmeasured_and_named() {
    local d out rc; d=$(mktemp -d); hw "$d" "" true; costs "$d"; run_ub "$d"
    assert_eq 2 "$rc" "$out"
    assert_contains "$out" "UNMEASURED: chain-uart0.rx_fifo_depth, chain-uart1.rx_fifo_depth, chain-uart2.rx_fifo_depth;"
    assert_not_contains "$out" "rx_dma;"
}

test_a_verdict_that_flips_inside_a_range_is_undecided_and_names_the_input() {
    # wake_us has a range too, but it cannot move the verdict alone: at 2000 us
    # of latency no wake cost leaves time to drain. Only latency_us decides.
    local d out rc; d=$(mktemp -d); hw "$d" 1024 true; costs "$d" 20 25 100 2000; run_ub "$d"
    assert_eq 2 "$rc" "$out"
    assert_eq "UNDECIDED: userspace-irq at the low costs, needs-dma-helper at the high; decided by: latency_us" \
        "$(printf '%s\n' "$out" | grep '^UNDECIDED')"
}

test_cpu_over_budget_fails_userspace_even_when_the_deadline_holds() {
    # 2048 deep: deadline 2252.8 us, period 1752.8 us, 570.5 wakes/s per bus;
    # 3 x 570.5 x 200 us = 0.342 of a core, over 0.2.
    local d out rc; d=$(mktemp -d); hw "$d" 2048 true; costs "$d" 200 200; run_ub "$d"
    assert_eq 0 "$rc" "$out"
    assert_contains "$out" "cpu 0.374"   # 0.342 waking + 0.0318 reading
    assert_contains "$out" "verdict: needs-dma-helper"
}

test_min_depth_is_computed_without_a_depth() {
    # Reading costs 106000 x 0.3 us = 0.0318; waking may use 0.1682, so each of
    # 3 buses may wake 2803.3 times/s: period >= 356.7 us, deadline >= 856.7 us,
    # fill >= 1713.4 us, depth >= 778.8 entries: 779.
    local d out rc; d=$(mktemp -d); hw "$d" "" true; costs "$d"; run_ub "$d" --min-depth
    assert_eq 0 "$rc" "$out"
    assert_contains "$out" "userspace-irq at every cost in range needs rx_fifo_depth >= 779"
}

test_a_depth_without_a_source_is_refused() {
    local d out rc; d=$(mktemp -d); hw "$d" 1024 false; costs "$d"
    sed -i '/fifo_source/d' "$d/hw.toml"; run_ub "$d"
    assert_eq 1 "$rc" "$out"
    assert_contains "$out" "fifo_source"
}

test_the_bus_count_comes_from_hw_toml() {
    local d out rc; d=$(mktemp -d); hw "$d" 1024 false 2; costs "$d"; run_ub "$d"
    assert_contains "$out" "2 buses"
}

test_no_chain_uart_blocks_is_unmeasured() {
    local d out rc; d=$(mktemp -d); printf '[[block]]\nname = "pwm0"\nkind = "pwm"\n' > "$d/hw.toml"; costs "$d"; run_ub "$d"
    assert_eq 2 "$rc" "$out"
    assert_contains "$out" "no chain-uart blocks"
}

test_a_cost_file_without_a_preemption_model_is_unmeasured() {
    local d out rc; d=$(mktemp -d); hw "$d" 1024 false; costs "$d"
    sed -i '/kernel_preemption/d' "$d/costs.toml"; run_ub "$d"
    assert_eq 2 "$rc" "$out"
    assert_contains "$out" "cost.kernel_preemption"
}

# The board's real inputs (#27): complete, and consistent with the kernel.
REAL_COSTS="$(repo_root)/os/board/rds-control/uart-budget.toml"

test_the_real_inputs_are_complete() {
    local out rc=0
    out=$("$UB" "$REAL_COSTS" --min-depth 2>&1) || rc=$?
    assert_eq 0 "$rc" "$out"
    assert_contains "$out" "needs rx_fifo_depth >= "
}

test_the_board_kernel_requests_the_preemption_model_the_latency_assumes() {
    local model
    model=$(python3 -c "import tomllib,sys;print(tomllib.load(open(sys.argv[1],'rb'))['cost']['kernel_preemption'])" "$REAL_COSTS")
    [ -n "$model" ] || fail "no kernel_preemption in $REAL_COSTS"
    assert_contains "$(cat "$(repo_root)/os/board/rds-control/linux.fragment")" "CONFIG_${model}=y"
}
