# Shared paths for env/rds stages. Every default lives here, once; each can be
# overridden by the environment (tests do).
RDS_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RDS_PROJECT=$(cd "$RDS_REPO/../.." && pwd)
: "${RDS_TMPDIR:=$RDS_PROJECT/build/tmp}"
: "${RDS_LOCK:=$RDS_REPO/env/lock.tsv}"
: "${RDS_MIRROR:=$RDS_PROJECT/archive/mirror}"
: "${RDS_BR_DIR:=$RDS_PROJECT/build/buildroot}"   # extracted by build/05-buildroot-tree (#94)
: "${RDS_GENERATED:=$RDS_REPO/env/generated.tsv}"
: "${RDS_DISK_FLOOR_GB:=60}"   # D5: 40 GB build cap, plus margin
# The publication check tools/publish-seed runs on every export (#104): the
# Mujina port project's gate (mujina_bzm2), read in place beside this project,
# never copied here.
: "${RDS_PUBLISH_GATE:=$(dirname "$RDS_PROJECT")/mujina_bzm2/git/mujina-bzm2-dev/tools/rds/check-public.sh}"

# A pipe must not hide a failing check: `check | sed` has sed's status without
# this (#81).
set -o pipefail

# The variants we build: one os/configs/<variant>.fragment each, besides
# common. The configs are the one home for this list (#81).
rds_variants() {
    local f
    for f in "$RDS_REPO"/os/configs/*.fragment; do
        f=$(basename "$f" .fragment)
        [ "$f" = common ] || echo "$f"
    done
}

# A variant's kernel fragments, read from its own
# BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES, one path per line (#81).
rds_kernel_fragments() {
    sed -n 's/^BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="\(.*\)"$/\1/p' "$RDS_REPO/os/configs/$1.fragment" \
        | tr ' ' '\n' | sed -e '/^$/d' -e "s|\$(BR2_EXTERNAL_RDS_PATH)|$RDS_REPO/os|"
}
