#!/bin/bash
# Prove the shared Wine Mono 11.2.0 package in a disposable ARM64 Wine prefix.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
MONO="$VKMT/wine/mono/wine-mono-11.2.0"
MCS="$MONO/lib/mono/4.5/mcs.exe"
RUNS="$VKMT/build/probe-runs"
SOURCE="$VKMT/test/managed_runtime_probe.cs"

"$VKMT/scripts/fetch-wine-mono-runtime.sh"
test -f "$MCS"
mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/wine-mono.XXXXXX")"
prefix="$run_root/prefix"

cleanup()
{
  status=$?
  WINEPREFIX="$prefix" "$WINESERVER" -k >/dev/null 2>&1 || true
  WINEPREFIX="$prefix" "$WINESERVER" -w >/dev/null 2>&1 || true
  case "$run_root" in
    "$RUNS"/*)
      test "${VKMT_KEEP_PROBE_RUN:-0}" = 1 ||
        /usr/bin/trash "$run_root" >/dev/null 2>&1 || true
      ;;
  esac
  exit "$status"
}
trap cleanup EXIT

run_wine()
{
  output=$1
  shift
  gtimeout --signal=TERM --kill-after=10s 120s \
    env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
      WINE_NO_EXPLORER=1 MVK_CONFIG_LOG_LEVEL=0 \
      WINE_MONO_AOT="${VKMT_WINE_MONO_AOT:-interp}" \
      WINEDEBUG="${VKMT_MONO_WINEDEBUG:--all}" \
      "$WINE" "$@" >"$output" 2>&1
}

mkdir -p "$prefix/drive_c/windows/system32"
for dll in xtajit64 xtajit wow64 wow64win; do
  install -m 0644 "$BUILD/dlls/$dll/aarch64-windows/$dll.dll" \
    "$prefix/drive_c/windows/system32/$dll.dll"
done
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine "$run_root/wineboot.log" "$WINEBOOT" --init
WINEPREFIX="$prefix" "$WINESERVER" -k >/dev/null 2>&1 || true
WINEPREFIX="$prefix" "$WINESERVER" -w >/dev/null 2>&1 || true
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

install -m 0644 "$SOURCE" "$prefix/drive_c/managed-runtime-probe.cs"
run_wine "$run_root/compile-i386.log" "$MCS" -nologo -platform:x86 \
  '-out:C:\managed-i386.exe' 'C:\managed-runtime-probe.cs'
run_wine "$run_root/compile-arm64.log" "$MCS" -nologo -platform:anycpu \
  '-out:C:\managed-arm64.exe' 'C:\managed-runtime-probe.cs'
run_wine "$run_root/compile-x64.log" "$MCS" -nologo -platform:x64 \
  '-out:C:\managed-x64.exe' 'C:\managed-runtime-probe.cs'

file "$prefix/drive_c/managed-i386.exe" | grep -q 'PE32 executable'
file "$prefix/drive_c/managed-arm64.exe" | grep -q 'PE32 executable'
file "$prefix/drive_c/managed-x64.exe" | grep -q 'PE32+ executable'

run_wine "$run_root/i386.log" "$prefix/drive_c/managed-i386.exe" 32 I386
run_wine "$run_root/arm64.log" "$prefix/drive_c/managed-arm64.exe" 64 ARM64
run_wine "$run_root/x64.log" "$prefix/drive_c/managed-x64.exe" 64 X86_64

grep -q 'VKMT_WINE_MONO_11_2_0_I386_OK' "$run_root/i386.log"
grep -q 'VKMT_WINE_MONO_11_2_0_ARM64_OK' "$run_root/arm64.log"
grep -q 'VKMT_WINE_MONO_11_2_0_X86_64_OK' "$run_root/x64.log"

sed -n '1,120p' "$run_root/i386.log"
sed -n '1,120p' "$run_root/arm64.log"
sed -n '1,120p' "$run_root/x64.log"
echo "VKMT_WINE_MONO_11_2_0_ALL_OK"
