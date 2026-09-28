#!/usr/bin/env bash
# Install the pinned Playwright core into <project>/build/ui-accept. Idempotent:
# when the pinned version is already there it touches nothing and needs no
# network. The browser (chromium revision 1234 for this version) comes from the
# local ~/.cache/ms-playwright; this script never downloads one.
set -euo pipefail
PIN=1.62.1
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dest=${UI_ACCEPT_HOME:-$(cd "$here/../../../.." && pwd)/build/ui-accept}
have=$(node -p "require('$dest/node_modules/playwright-core/package.json').version" 2>/dev/null || true)
if [ "$have" = "$PIN" ]; then
    printf '[ui-accept] playwright-core %s present in %s\n' "$PIN" "$dest" >&2
    exit 0
fi
mkdir -p "$dest"
[ -f "$dest/package.json" ] || printf '{"name":"ui-accept","private":true}\n' > "$dest/package.json"
npm install --prefix "$dest" --no-audit --no-fund "playwright-core@$PIN" >&2
printf '[ui-accept] installed playwright-core %s in %s\n' "$PIN" "$dest" >&2
