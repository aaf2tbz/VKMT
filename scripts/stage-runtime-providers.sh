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
XTAJIT64_SHA256="${VKMT_XTAJIT64_SHA256:-7b9f55ceabe971ffa1f514570bb54ed7b5640959e4440e7f8a013e9af13ab7e6}"
XTAJIT_SHA256="${VKMT_XTAJIT_SHA256:-ea523a42ca8e7965371122bd7be1eb6b973cded50ecda5da1465b2961ad36479}"
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

if test "$mode" != verify-prefix; then
  install -m 0644 "$XTAJIT64_SOURCE" "$XTAJIT64_STAGE"
  install -m 0644 "$XTAJIT_SOURCE" "$XTAJIT_STAGE"
  check "$XTAJIT64_SHA256" "$XTAJIT64_STAGE"
  check "$XTAJIT_SHA256" "$XTAJIT_STAGE"
fi

if test "$mode" = prefix; then
  system32="$prefix/drive_c/windows/system32"
  mkdir -p "$system32"
  install -m 0644 "$XTAJIT64_SOURCE" "$system32/xtajit64.dll"
  install -m 0644 "$XTAJIT_SOURCE" "$system32/xtajit.dll"
fi

if test "$mode" = prefix || test "$mode" = verify-prefix; then
  check "$XTAJIT64_SHA256" "$prefix/drive_c/windows/system32/xtajit64.dll"
  check "$XTAJIT_SHA256" "$prefix/drive_c/windows/system32/xtajit.dll"
fi

marker="$(printf '%s' "$mode" | tr '[:lower:]-' '[:upper:]_')"
echo "VKMT_RUNTIME_PROVIDERS_${marker}_OK"
