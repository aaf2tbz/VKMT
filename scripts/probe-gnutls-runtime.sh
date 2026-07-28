#!/bin/bash
# Prove the staged ARM64 GnuTLS closure through Windows HTTPS APIs.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
SOURCE="$VKMT/test/gnutls_https_probe.c"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
STAGE="$BUILD/dlls/secur32"
XTAJIT64="$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll"
XTAJIT="$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
WOW64="$BUILD/dlls/wow64/aarch64-windows/wow64.dll"
WOW64WIN="$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll"
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_GNUTLS_TIMEOUT:-120}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_GNUTLS_TIMEOUT:-120}s")
fi

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$SOURCE" \
    "$STAGE/libgnutls.30.dylib" "$XTAJIT64" "$XTAJIT" "$WOW64" "$WOW64WIN"; do
  test -e "$required" || { echo "Missing GnuTLS probe input: $required" >&2; exit 1; }
done
test "$(/usr/bin/lipo -archs "$STAGE/libgnutls.30.dylib")" = arm64
if /usr/bin/otool -L "$STAGE"/*.dylib | grep -Fq /opt/homebrew/; then
  echo "GnuTLS stage contains Homebrew runtime paths" >&2
  exit 1
fi

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/gnutls-runtime.XXXXXX")"
prefix="$run_root/prefix"
cleanup()
{
  status=$?
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in "$RUNS"/*) /usr/bin/trash "$run_root" 2>/dev/null || true;; esac
  exit "$status"
}
trap cleanup EXIT

compile()
{
  compiler=$1
  output=$2
  shift 2
  "$TOOL/$compiler" -O2 -g -Wall -Wextra "$@" "$SOURCE" -o "$output" \
    -lsecur32 -lwinhttp
}
compile aarch64-w64-mingw32-clang "$run_root/arm64.exe" -ffixed-x18 -ffixed-x28
compile arm64ec-w64-mingw32-clang "$run_root/arm64ec.exe" -ffixed-x18 -ffixed-x28
compile x86_64-w64-mingw32-clang "$run_root/x86_64.exe" -fno-vectorize -fno-slp-vectorize
compile i686-w64-mingw32-clang "$run_root/i386.exe"

mkdir -p "$prefix/drive_c/windows/system32" "$prefix/drive_c/windows/syswow64"
install -m 0644 "$XTAJIT64" "$prefix/drive_c/windows/system32/xtajit64.dll"
install -m 0644 "$XTAJIT" "$prefix/drive_c/windows/system32/xtajit.dll"
install -m 0644 "$WOW64" "$prefix/drive_c/windows/system32/wow64.dll"
install -m 0644 "$WOW64WIN" "$prefix/drive_c/windows/system32/wow64win.dll"
while IFS= read -r dll; do
  install -m 0644 "$dll" "$prefix/drive_c/windows/syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
  WINE_NO_EXPLORER=1 WINEDEBUG=-all "$WINE" "$WINEBOOT" --init \
  >"$run_root/wineboot.log" 2>&1
WINEPREFIX="$prefix" "$WINESERVER" -k
WINEPREFIX="$prefix" "$WINESERVER" -w

for arch in ${VKMT_GNUTLS_ARCHES:-arm64}; do
  log="$run_root/$arch.log"
  trace_log="$run_root/${arch}_dyld.log"
  if ! "${timeout_cmd[@]}" env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
      WINEDEBUG=-all DYLD_PRINT_LIBRARIES=1 "$WINE" "$run_root/$arch.exe" --schannel-only \
      >"$trace_log" 2>&1; then
    install -m 0644 "$trace_log" "$VKMT/build/gnutls-runtime.latest.log"
    echo "$arch staged GnuTLS load trace failed" >&2
    tail -n 160 "$trace_log" >&2
    exit 1
  fi
  grep -Fq "$STAGE/libgnutls.30.dylib" "$trace_log" || {
    echo "$arch did not load staged GnuTLS" >&2
    exit 1
  }
  WINEPREFIX="$prefix" "$WINESERVER" -k
  WINEPREFIX="$prefix" "$WINESERVER" -w
  if ! "${timeout_cmd[@]}" env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
      WINEDEBUG=-all "$WINE" "$run_root/$arch.exe" >"$log" 2>&1; then
    install -m 0644 "$log" "$VKMT/build/gnutls-runtime.latest.log"
    echo "$arch GnuTLS HTTPS probe failed or timed out" >&2
    tail -n 160 "$log" >&2
    exit 1
  fi
  grep -q 'GNUTLS_HTTPS_ALL_OK' "$log" || {
    install -m 0644 "$log" "$VKMT/build/gnutls-runtime.latest.log"
    tail -n 160 "$log" >&2
    exit 1
  }
  arch_upper="$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')"
  echo "GNUTLS_${arch_upper}_HTTPS_OK"
  WINEPREFIX="$prefix" "$WINESERVER" -k
  WINEPREFIX="$prefix" "$WINESERVER" -w
done
echo GNUTLS_NATIVE_ARM64_SERVER_HTTPS_OK
