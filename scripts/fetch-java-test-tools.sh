#!/bin/bash
# Fetch the pinned Java compiler used only to build native-Java acceptance fixtures.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$VKMT/third_party/build-tools"
ECJ="$TOOLS/ecj-4.6.1.jar"
URL=https://repo1.maven.org/maven2/org/eclipse/jdt/core/compiler/ecj/4.6.1/ecj-4.6.1.jar
EXPECTED_SHA=9cddda75f4a1b4469e73f44e7b61a3e897d0f657df4797f9106ffe88c4eeade0

mkdir -p "$TOOLS"
if test ! -f "$ECJ"; then
  temporary="$(mktemp "$TOOLS/ecj-4.6.1.XXXXXX")"
  trap 'test ! -f "$temporary" || /usr/bin/trash "$temporary"' EXIT
  curl -fL --retry 3 -o "$temporary" "$URL"
  printf '%s  %s\n' "$EXPECTED_SHA" "$temporary" |
    shasum -a 256 -c - >/dev/null
  mv "$temporary" "$ECJ"
  trap - EXIT
fi

printf '%s  %s\n' "$EXPECTED_SHA" "$ECJ" | shasum -a 256 -c - >/dev/null
echo "$ECJ"
