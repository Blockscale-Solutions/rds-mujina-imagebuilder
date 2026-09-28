# Slow tier: the build container is pinned, identical on rebuild, and stays in the project (#34).
C="$(repo_root)/env/container.sh"

test_the_base_is_pinned_by_digest_and_apt_by_snapshot() {
    local f; f=$(cat "$(repo_root)/env/container/Containerfile")
    assert_contains "$f" "debian:trixie-slim@sha256:7792b1f7702a86946cd518db72b6a407302c3e9bc1635634368b878189e8221c"
    assert_contains "$f" "snapshot.debian.org/archive/debian/%s"
    assert_not_contains "$f" "deb.debian.org"
}

test_the_installed_set_equals_the_committed_list() {
    local id got
    id=$("$C" build) || fail "build failed"
    got=$("$C" apt-list) || fail "apt-list failed"
    [ -n "$got" ] || fail "empty package list"
    assert_eq "$(cat "$(repo_root)/env/apt.list")" "$got" "installed packages differ from env/apt.list"
}

test_a_rebuild_gives_the_same_image() {
    local a b
    a=$("$C" build) || fail "first build failed"
    "$C" build >/dev/null; podman --root "$(repo_root)/../../build/podman/root" --runroot "${XDG_RUNTIME_DIR}/rds-podman" rmi -f localhost/rds-build:latest >/dev/null 2>&1
    b=$(RDS_NO_CACHE=1 "$C" build) || fail "second build failed"
    assert_eq "$a" "$b" "image id differs between builds"
}

test_nothing_lands_in_default_podman_storage() {
    "$C" build >/dev/null
    if podman images --format '{{.Repository}}' | grep -q 'rds-build'; then fail "rds-build found in $HOME podman storage"; fi
}
