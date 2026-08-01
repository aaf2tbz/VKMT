#!/bin/bash
# Prefix-scoped bounded wineserver lifecycle with runtime-generation receipts.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
WINESERVER="$BUILD/server/wineserver"
TIMEOUT="${VKMT_WARM_SESSION_TIMEOUT:-120}"
ACTION=
PREFIX=
REASON=manual

usage()
{
  echo "usage: $0 start|stop|invalidate|verify --prefix PREFIX [--reason TEXT]" >&2
  exit 2
}

test $# -ge 1 || usage
ACTION=$1
shift
while test $# -gt 0; do
  case "$1" in
    --prefix) test $# -ge 2 || usage; PREFIX=$2; shift 2 ;;
    --reason) test $# -ge 2 || usage; REASON=$2; shift 2 ;;
    *) usage ;;
  esac
done

case "$ACTION" in start|stop|invalidate|verify) ;; *) usage ;; esac
test -n "$PREFIX" || usage
case "$PREFIX" in /*) ;; *) echo "Prefix must be an absolute path" >&2; exit 2 ;; esac
case "$TIMEOUT" in *[!0-9]*|'') echo "Invalid VKMT_WARM_SESSION_TIMEOUT" >&2; exit 2 ;; esac
test "$TIMEOUT" -ge 1 && test "$TIMEOUT" -le 600 || {
  echo "VKMT_WARM_SESSION_TIMEOUT must be between 1 and 600 seconds" >&2
  exit 2
}
test -x "$WINESERVER" || { echo "Missing wineserver: $WINESERVER" >&2; exit 1; }
test "$(/usr/bin/lipo -archs "$BUILD/wine")" = arm64 || {
  echo "Warm-session Wine host must be ARM64-only" >&2
  exit 1
}
test "$(/usr/bin/lipo -archs "$WINESERVER")" = arm64 || {
  echo "Warm-session wineserver must be ARM64-only" >&2
  exit 1
}
translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null || echo 0)"
test "$translated" = 0 || { echo "Refusing to manage a Wine session under Rosetta" >&2; exit 1; }

receipt_dir="$PREFIX/.vkmt"
receipt="$receipt_dir/warm-session-v1.tsv"

runtime_generation()
{
  local files=(
    "$BUILD/wine"
    "$BUILD/server/wineserver"
    "$BUILD/dlls/ntdll/ntdll.so"
    "$PREFIX/drive_c/windows/system32/xtajit64.dll"
    "$PREFIX/drive_c/windows/system32/xtajit.dll"
    "$BUILD/runtime/gstreamer-arm64/MANIFEST.sha256"
  )
  local file
  {
    printf 'schema=1\nmsync=%s\n' "${WINEMSYNC:-default}"
    for file in "${files[@]}"; do
      test -f "$file" || { printf 'missing\t%s\n' "$file"; continue; }
      shasum -a 256 "$file"
    done
  } | shasum -a 256 | awk '{print $1}'
}

stop_exact()
{
  WINEPREFIX="$PREFIX" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$PREFIX" "$WINESERVER" -w 2>/dev/null || true
}

write_receipt()
{
  local state=$1 generation=$2 temporary
  mkdir -p "$receipt_dir"
  temporary="$(mktemp "$receipt_dir/warm-session-v1.XXXXXX")"
  {
    printf 'schema\t1\n'
    printf 'prefix\t%s\n' "$PREFIX"
    printf 'generation\t%s\n' "$generation"
    printf 'msync\t%s\n' "${WINEMSYNC:-default}"
    printf 'timeout_seconds\t%s\n' "$TIMEOUT"
    printf 'state\t%s\n' "$state"
    printf 'reason\t%s\n' "$REASON"
  } >"$temporary"
  mv -f "$temporary" "$receipt"
}

case "$ACTION" in
  start)
    test -d "$PREFIX" || { echo "Missing prefix: $PREFIX" >&2; exit 1; }
    generation="$(runtime_generation)"
    if test -f "$receipt"; then
      old_generation="$(awk -F '\t' '$1 == "generation" {print $2; exit}' "$receipt")"
      old_msync="$(awk -F '\t' '$1 == "msync" {print $2; exit}' "$receipt")"
      if test "$old_generation" != "$generation" || test "$old_msync" != "${WINEMSYNC:-default}"; then
        stop_exact
      fi
    fi
    WINEPREFIX="$PREFIX" "$WINESERVER" -p"$TIMEOUT"
    write_receipt active "$generation"
    echo "VKMT_WARM_SESSION_ACTIVE prefix=$PREFIX timeout=$TIMEOUT generation=$generation"
    ;;
  stop)
    stop_exact
    write_receipt stopped "$(runtime_generation)"
    echo "VKMT_WARM_SESSION_STOPPED prefix=$PREFIX"
    ;;
  invalidate)
    stop_exact
    write_receipt invalid "$(runtime_generation)"
    echo "VKMT_WARM_SESSION_INVALIDATED prefix=$PREFIX reason=$REASON"
    ;;
  verify)
    test -f "$receipt" || { echo "Missing warm-session receipt: $receipt" >&2; exit 1; }
    expected="$(runtime_generation)"
    actual="$(awk -F '\t' '$1 == "generation" {print $2; exit}' "$receipt")"
    test "$actual" = "$expected" || {
      echo "Warm-session generation mismatch: expected $expected, receipt $actual" >&2
      exit 1
    }
    test "$(awk -F '\t' '$1 == "prefix" {print $2; exit}' "$receipt")" = "$PREFIX"
    echo "VKMT_WARM_SESSION_VERIFY_OK prefix=$PREFIX generation=$expected"
    ;;
esac
