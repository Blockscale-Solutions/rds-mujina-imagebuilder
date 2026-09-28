# tools/env-find: locate CRC-valid U-Boot environment copies in a raw dump (#25).
FIND="$(repo_root)/tools/env-find"

mkdump() { # layout(single|redundant) "off:size:flag ..." [corrupt] -> dump path
    python3 - "$@" <<'PY'
import sys, zlib, tempfile
layout, spec = sys.argv[1], sys.argv[2]; corrupt = len(sys.argv) > 3
buf = bytearray(b'\xff' * 0x10000)
for item in spec.split():
    off, size, flag = (int(x, 0) for x in item.split(':'))
    hdr = 5 if layout == 'redundant' else 4
    data = bytearray(b'bootcmd=run boot\x00bootdelay=1\x00\x00'.ljust(size - hdr, b'\x00'))
    crc = zlib.crc32(data)
    if corrupt: crc ^= 1
    blk = crc.to_bytes(4, 'little') + (bytes([flag]) if layout == 'redundant' else b'') + data
    buf[off:off + size] = blk
f = tempfile.NamedTemporaryFile(delete=False, suffix='.bin'); f.write(buf); print(f.name)
PY
}

test_a_redundant_pair_is_found_and_the_newer_flag_is_active() {
    local d rc=0 out; d=$(mkdump redundant "0x4000:0x2000:5 0x8000:0x2000:6")
    out=$("$FIND" "$d" 2>&1) || rc=$?
    assert_eq 0 "$rc"
    assert_contains "$out" "offset 0x4000 size 0x2000 redundant flag 5"
    assert_contains "$out" "offset 0x8000 size 0x2000 redundant flag 6 ACTIVE"
}

test_flag_wraparound_prefers_the_copy_after_255() {
    local d out; d=$(mkdump redundant "0x4000:0x2000:255 0x8000:0x2000:0")
    out=$("$FIND" "$d" 2>&1)
    assert_contains "$out" "offset 0x8000 size 0x2000 redundant flag 0 ACTIVE"
}

test_a_single_copy_is_found() {
    local d out; d=$(mkdump single "0x6000:0x1000:0")
    out=$("$FIND" "$d" 2>&1)
    assert_contains "$out" "offset 0x6000 size 0x1000 single"
}

test_a_corrupted_crc_is_not_reported_and_exits_1() {
    local d rc=0 out; d=$(mkdump redundant "0x4000:0x2000:5" corrupt)
    out=$("$FIND" "$d" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_not_contains "$out" "offset 0x4000"
}

test_it_never_prints_the_environment_contents() {
    local d out; d=$(mkdump redundant "0x4000:0x2000:5 0x8000:0x2000:6")
    out=$("$FIND" "$d" 2>&1)
    assert_not_contains "$out" "bootcmd"; assert_not_contains "$out" "run boot"
}

test_an_empty_file_is_unmeasured() {
    local f rc=0; f=$(mktemp)
    "$FIND" "$f" >/dev/null 2>&1 || rc=$?; assert_eq 2 "$rc"
}
