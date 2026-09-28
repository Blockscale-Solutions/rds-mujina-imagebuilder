# Assertions shared by every *.test.sh. Sourced by tests/run.sh before each file.
fail() { printf '    FAIL: %s\n' "$*" >&2; return 1; }
assert_eq() { # expected actual [label]
    [ "$1" = "$2" ] || fail "${3:-values differ}: expected [$1] got [$2]"
}
assert_contains() { # haystack needle [label]
    case "$1" in *"$2"*) ;; *) fail "${3:-missing text}: [$2] not found" ;; esac
}
assert_not_contains() { # haystack needle [label]
    case "$1" in *"$2"*) fail "${3:-unexpected text}: [$2] present" ;; *) ;; esac
}
repo_root() { cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd; }
build_tmp() { # -> a new directory under <project>/build (on disk, never tmpfs)
    # A fresh clone has no build/ yet. Create it, and fail rather than print an
    # empty path: a caller in $(...) has no errexit, and "$d/x" would be "/x".
    local b; b="$(repo_root)/../../build"
    mkdir -p "$b" && mktemp -d -p "$b"
}
