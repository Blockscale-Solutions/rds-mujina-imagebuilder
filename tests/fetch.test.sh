# tools/fetch: every byte of every input by sha256 into the mirror, nothing unlisted (#35, gate C3).
FETCH="$(repo_root)/tools/fetch"

serve() { # dir -> "port pid" of a local http server over dir
    local d=$1 port
    port=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
    python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 &
    local pid=$!
    for _ in $(seq 50); do curl -s "http://127.0.0.1:$port/" >/dev/null && break; sleep 0.1; done
    printf '%s %s' "$port" "$pid"
}
setup() { # -> dir with srv/ (good.tar, page.tar is HTML), mirror/, tmp/
    local d; d=$(build_tmp) || return 1; mkdir -p "$d/srv" "$d/mirror" "$d/tmp"
    head -c 4000 /dev/urandom > "$d/srv/good.tar"
    printf '<!DOCTYPE html><html><body>contact us</body></html>\n' > "$d/srv/page.tar"
    printf '%s' "$d"
}
lockline() { printf '%s\t%s\t%s\thttp://127.0.0.1:%s/%s\n' "$(sha256sum < "$1" | cut -d' ' -f1)" "$(stat -c %s "$1")" "$2" "$3" "$2"; }

test_a_good_entry_lands_in_the_mirror_named_by_hash() {
    local d s rc=0 h; d=$(setup); s=$(serve "$d/srv"); set -- $s
    lockline "$d/srv/good.tar" good.tar "$1" > "$d/lock.tsv"; h=$(cut -f1 "$d/lock.tsv")
    RDS_TMPDIR=$d/tmp "$FETCH" --lock "$d/lock.tsv" --mirror "$d/mirror" >/dev/null 2>&1 || rc=$?
    kill "$2"; assert_eq 0 "$rc"
    [ -f "$d/mirror/$h" ] || fail "not in mirror"
    assert_eq "$h" "$(sha256sum < "$d/mirror/$h" | cut -d' ' -f1)"
}

test_a_flipped_byte_fails_and_nothing_lands() {
    local d s rc=0 out; d=$(setup); s=$(serve "$d/srv"); set -- $s
    lockline "$d/srv/good.tar" good.tar "$1" > "$d/lock.tsv"
    printf '\xff' | dd of="$d/srv/good.tar" bs=1 seek=100 conv=notrunc 2>/dev/null
    out=$(RDS_TMPDIR=$d/tmp "$FETCH" --lock "$d/lock.tsv" --mirror "$d/mirror" 2>&1) || rc=$?
    kill "$2"; assert_eq 1 "$rc"; assert_contains "$out" "good.tar"
    assert_eq 0 "$(find "$d/mirror" -type f | wc -l)" "a failed fetch left a file in the mirror"
}

test_html_answered_for_a_tarball_fails() {
    local d s rc=0 out; d=$(setup); s=$(serve "$d/srv"); set -- $s
    # The lock expects a tarball's hash; the server answers 200 with an HTML page.
    printf '%s\t4000\tpage.tar\thttp://127.0.0.1:%s/page.tar\n' "$(printf x | sha256sum | cut -d' ' -f1)" "$1" > "$d/lock.tsv"
    out=$(RDS_TMPDIR=$d/tmp "$FETCH" --lock "$d/lock.tsv" --mirror "$d/mirror" 2>&1) || rc=$?
    kill "$2"; assert_eq 1 "$rc"; assert_contains "$out" "HTML"
}

test_an_unlisted_url_fails() {
    local d rc=0 out; d=$(setup)
    printf '%s\t10\ta.tar\thttps://example.invalid/a.tar\n' "$(printf a | sha256sum | cut -d' ' -f1)" > "$d/lock.tsv"
    printf 'https://example.invalid/a.tar\nhttps://example.invalid/sneaky.tar\n' > "$d/wanted.txt"
    out=$("$FETCH" --lock "$d/lock.tsv" --check-urls "$d/wanted.txt" 2>&1) || rc=$?
    assert_eq 1 "$rc"; assert_contains "$out" "sneaky.tar"
}

test_an_entry_already_in_the_mirror_is_not_refetched() {
    local d rc=0 h; d=$(setup); cp "$d/srv/good.tar" "$d/g"; h=$(sha256sum < "$d/g" | cut -d' ' -f1)
    cp "$d/g" "$d/mirror/$h"
    printf '%s\t4000\tgood.tar\thttp://127.0.0.1:1/unreachable\n' "$h" > "$d/lock.tsv"
    RDS_TMPDIR=$d/tmp "$FETCH" --lock "$d/lock.tsv" --mirror "$d/mirror" >/dev/null 2>&1 || rc=$?
    assert_eq 0 "$rc" "a present, matching entry must not touch the network"
}

test_an_empty_wanted_list_is_unmeasured_not_a_pass() {
    # Measured 2026-09-25: with no show-info on disk the gate read "0 of 0 wanted URLs are locked", exit 0.
    local d rc=0; d=$(mktemp -d)
    printf '%s\t1\ta/b\thttps://x/b\n' "$(printf a | sha256sum | cut -d' ' -f1)" > "$d/lock.tsv"; : > "$d/wanted.txt"
    "$FETCH" --lock "$d/lock.tsv" --check-urls "$d/wanted.txt" >/dev/null 2>&1 || rc=$?
    assert_eq 2 "$rc"
}
