# Shared by tests/qemu/*.test.sh (sourced by each test file).
Q="$(repo_root)/tools/qemu-test"
# Sensor boot arguments: the chip logs each program and erase it executes (S1),
# into a log buffer large enough that no line is lost.
SENSE="log_buf_len=4M nandsim.log=1 nandsim.dyndbg=+p"
# The simulated chip: the unit's geometry (2048 B pages, 64 B OOB, 128 KiB
# blocks) and its table layout (flash BBT, marker in the data area, as Denali
# uses), in 64 blocks so a raw hash stays fast. A Samsung ID, not the unit's
# Micron one: nandsim cannot follow the Micron probe's commands (MEASURED
# 2026-09-25: its state machine desyncs and every read fails), so the Micron
# init stays unmeasured until the unit.
CHIP="nandsim.id_bytes=0xec,0xf1,0x00,0x95,0x40 nandsim.overridesize=6 nandsim.bbt=2"
field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }
run_guest() { "$Q" "$@" || fail "no result from $1: $(printf '%s' "$*")"; }
gt0() { [ "${1:-0}" -gt 0 ] 2>/dev/null || fail "$2: expected more than 0, got '${1}'"; }
