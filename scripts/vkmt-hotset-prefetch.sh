#!/bin/bash
# Start one bounded asynchronous hot-set request per prefix cooldown interval.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
PREFIX="${WINEPREFIX:-}"
COOLDOWN="${VKMT_HOTSET_COOLDOWN_SECONDS:-30}"

test "${VKMT_HOTSET_PREFETCH:-1}" != 0 || exit 0
test -n "$PREFIX" && test -d "$PREFIX" || exit 0
case "$COOLDOWN" in ''|*[!0-9]*) exit 2 ;; esac

tool="$BUILD/runtime/hotset/vkmt-hotset-prefetch"
manifest="$BUILD/runtime/hotset/all-arch-default.tsv"
receipt="$PREFIX/.vkmt/hotset-runtime.receipt"
stamp="$PREFIX/.vkmt/hotset-prefetch.stamp"
lock="$PREFIX/.vkmt/hotset-prefetch.lock"
test -x "$tool" && test -f "$manifest" && test -f "$receipt" || exit 0

now="$(date +%s)"
if test -f "$stamp"; then
  last="$(stat -f %m "$stamp")"
  test $((now - last)) -ge "$COOLDOWN" || exit 0
fi
mkdir "$lock" 2>/dev/null || exit 0
: >"$stamp"
(
  "$tool" "$manifest" "$VKMT" "$PREFIX" --advice >/dev/null 2>&1 || true
  find "$lock" -depth -delete 2>/dev/null || true
) &
disown 2>/dev/null || true
echo "VKMT_HOTSET_PREFETCH_STARTED prefix=$PREFIX"
