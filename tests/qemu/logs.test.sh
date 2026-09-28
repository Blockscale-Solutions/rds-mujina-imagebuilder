# #58 (goal G7): a failure keeps its evidence. A deliberate panic reaches a
# host UDP listener over netconsole, and after the warm reset pstore holds it.
. "$(repo_root)/tests/qemu/lib-qemu.sh"

test_a_panic_reaches_netconsole_and_survives_a_warm_reset_in_pstore() {
    local port cap lpid r rc=0
    port=$(python3 -c 'import socket;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
    cap=$(mktemp)
    python3 -c 'import socket,sys; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.bind(("127.0.0.1",int(sys.argv[1]))); f=open(sys.argv[2],"ab",0)
while True: f.write(s.recv(65535))' "$port" "$cap" & lpid=$!
    r=$(RDS_QEMU_REBOOT=1 RDS_QEMU_NET=1 RDS_QEMU_TIMEOUT=240 "$Q" pstore $SENSE mem=240M \
        ramoops.mem_address=0x6f000000 ramoops.mem_size=0x100000 ramoops.record_size=0x20000 ramoops.console_size=0x20000 \
        "netconsole=6665@10.0.2.15/eth0,$port@10.0.2.2/") || rc=$?
    kill "$lpid" 2>/dev/null; wait "$lpid" 2>/dev/null || true   # its SIGTERM status is not a failure
    [ $rc -eq 0 ] || fail "no result: $r"
    assert_eq 2 "$(field "$r" boot)" "$r"
    assert_eq yes "$(field "$r" oops)" "pstore did not keep the oops: $r"
    local marker; marker=$(field "$r" marker)
    [ "$marker" != none ] || fail "the pstore record lacks this boot's marker: $r"
    # The UDP capture holds this boot's own marker and the panic: not stray traffic.
    assert_contains "$(tr -d '\0' < "$cap")" "marker $marker panicking now"
    assert_contains "$(tr -d '\0' < "$cap")" "sysrq triggered crash"
}
