#!/bin/bash
# Stage and verify the accepted ARM64EC/x86_64 and ARM64/i386 CPU providers.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
SOURCE="$VKMT/wine/wine-11.12/runtime-providers"
XTAJIT64_SOURCE="${VKMT_XTAJIT64_SOURCE:-$SOURCE/xtajit64-arm64ec-known-good.dll}"
XTAJIT_SOURCE="${VKMT_XTAJIT_SOURCE:-$SOURCE/xtajit-arm64-known-good.dll}"
XTAJIT64_STAGE="$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll"
XTAJIT_STAGE="$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
XTAJIT64_SHA256="${VKMT_XTAJIT64_SHA256:-0dde3c54ff286553b0592d58057e99f9ef4aca0d86436d1c1fa2e38d3fc14330}"
XTAJIT_SHA256="${VKMT_XTAJIT_SHA256:-e8d4c6694b456d9ecaa5d79e7461d6e0981a7080d14f3fe1b74732554a4b12a0}"
CANONICAL_XTAJIT64_SOURCE="$SOURCE/xtajit64-arm64ec-known-good.dll"
CANONICAL_XTAJIT_SOURCE="$SOURCE/xtajit-arm64-known-good.dll"
mode=stage
prefix=

usage()
{
  echo "usage: $0 [--stage-only | --prefix PREFIX | --verify-prefix PREFIX]" >&2
  exit 2
}

check()
{
  expected=$1
  file=$2
  echo "$expected  $file" | shasum -a 256 -c -
}

case $# in
  0) ;;
  1)
    test "$1" = --stage-only || usage
    ;;
  2)
    case "$1" in
      --prefix) mode=prefix ;;
      --verify-prefix) mode=verify-prefix ;;
      *) usage ;;
    esac
    prefix=$2
    ;;
  *) usage ;;
esac

check "$XTAJIT64_SHA256" "$XTAJIT64_SOURCE"
check "$XTAJIT_SHA256" "$XTAJIT_SOURCE"

stage_build=1
if test "$mode" = prefix &&
   { test "$XTAJIT64_SOURCE" != "$CANONICAL_XTAJIT64_SOURCE" ||
     test "$XTAJIT_SOURCE" != "$CANONICAL_XTAJIT_SOURCE"; }; then
  stage_build=0
fi
if test "${VKMT_PROVIDER_STAGE_BUILD:-$stage_build}" = 1 &&
   test "$mode" != verify-prefix; then
  if { test "$XTAJIT64_SOURCE" != "$CANONICAL_XTAJIT64_SOURCE" ||
       test "$XTAJIT_SOURCE" != "$CANONICAL_XTAJIT_SOURCE"; } &&
     test "${VKMT_PROVIDER_PROMOTE:-0}" != 1; then
    echo "Refusing to promote candidate providers without VKMT_PROVIDER_PROMOTE=1" >&2
    exit 1
  fi
  install -m 0644 "$XTAJIT64_SOURCE" "$XTAJIT64_STAGE"
  install -m 0644 "$XTAJIT_SOURCE" "$XTAJIT_STAGE"
  check "$XTAJIT64_SHA256" "$XTAJIT64_STAGE"
  check "$XTAJIT_SHA256" "$XTAJIT_STAGE"
fi

if test "$mode" = prefix; then
  system32="$prefix/drive_c/windows/system32"
  mkdir -p "$system32"
  if { test -f "$system32/xtajit64.dll" &&
       test "$(shasum -a 256 "$system32/xtajit64.dll" | awk '{print $1}')" != "$XTAJIT64_SHA256"; } ||
     { test -f "$system32/xtajit.dll" &&
       test "$(shasum -a 256 "$system32/xtajit.dll" | awk '{print $1}')" != "$XTAJIT_SHA256"; }; then
    "$VKMT/scripts/vkmt-warm-session.sh" invalidate --prefix "$prefix" --reason provider-replacement
  fi
  install -m 0644 "$XTAJIT64_SOURCE" "$system32/xtajit64.dll"
  install -m 0644 "$XTAJIT_SOURCE" "$system32/xtajit.dll"
fi

if test "$mode" = prefix || test "$mode" = verify-prefix; then
  check "$XTAJIT64_SHA256" "$prefix/drive_c/windows/system32/xtajit64.dll"
  check "$XTAJIT_SHA256" "$prefix/drive_c/windows/system32/xtajit.dll"
fi

# A prefix is accepted only against a verified, relocatable native media
# runtime. Store the exact closure manifest hash in the prefix so later
# verification catches missing/replaced host dependencies.
"$VKMT/scripts/stage-gstreamer-runtime.sh" --ensure
gst_manifest="$BUILD/runtime/gstreamer-arm64/MANIFEST.sha256"
gst_manifest_sha="$(shasum -a 256 "$gst_manifest" | awk '{print $1}')"
if test "$mode" = prefix; then
  mkdir -p "$prefix/.vkmt"
  printf '%s\n' "$gst_manifest_sha" >"$prefix/.vkmt/gstreamer-runtime.sha256"
fi
if test "$mode" = prefix || test "$mode" = verify-prefix; then
  test "$(cat "$prefix/.vkmt/gstreamer-runtime.sha256")" = "$gst_manifest_sha" || {
    echo "Prefix GStreamer runtime receipt does not match the staged closure" >&2
    exit 1
  }
fi

if test "$mode" = prefix; then
  "$VKMT/scripts/stage-gpu-cache-runtime.sh" --prefix "$prefix"
elif test "$mode" = verify-prefix; then
  "$VKMT/scripts/stage-gpu-cache-runtime.sh" --verify-prefix "$prefix"
fi

marker="$(printf '%s' "$mode" | tr '[:lower:]-' '[:upper:]_')"
echo "VKMT_RUNTIME_PROVIDERS_${marker}_OK"
