#!/bin/bash
# Prove i386 Inno compiler execution and the relocatable ARM64 extraction fallback.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
INSTALLER="$VKMT/third_party/inno-setup-6.5.4/innosetup-6.5.4.exe"
EXTRACT_FIXTURE="$VKMT/third_party/inno-setup-6.3.3/innosetup-6.3.3.exe"
EXTRACTOR="$BUILD/installer-runtime/innoextract/innoextract"
CLASSIFIER="$VKMT/scripts/classify-installer.sh"

echo 'fa73bf47a4da250d185d07561c2bfda387e5e20db77e4570004cf6a133cc10b1  '"$INSTALLER" |
  shasum -a 256 -c -
echo '0bcb2a409dea17e305a27a6b09555cabe600e984f88570ab72575cd7e93c95e6  '"$EXTRACT_FIXTURE" |
  shasum -a 256 -c -
test "$(/usr/bin/lipo -archs "$EXTRACTOR")" = arm64
! otool -L "$EXTRACTOR" | grep -Eq '/(opt/homebrew|usr/local)/'

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/inno-runtime.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=""
cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in "$RUNS"/*)
    test "${VKMT_KEEP_PROBE_RUN:-0}" = 1 ||
      /usr/bin/trash "$run_root" 2>/dev/null || true
  esac
  exit "$status"
}
trap cleanup EXIT

run_wine()
{
  output=$1
  shift
  gtimeout --signal=TERM --kill-after=10s "${VKMT_INNO_TIMEOUT:-180}s" \
    env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_INNO_WINEDEBUG:--all}" \
    "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then code=0; else code=$?; fi
  wine_pid=""
  return "$code"
}
stop_server()
{
  WINEPREFIX="$prefix" "$WINESERVER" -k
  WINEPREFIX="$prefix" "$WINESERVER" -w
}

mkdir -p "$prefix/drive_c/windows/system32" "$prefix/drive_c/windows/syswow64"
install -m 0644 "$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll" \
  "$prefix/drive_c/windows/system32/xtajit64.dll"
install -m 0644 "$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll" \
  "$prefix/drive_c/windows/system32/xtajit.dll"
install -m 0644 "$BUILD/dlls/wow64/aarch64-windows/wow64.dll" \
  "$prefix/drive_c/windows/system32/wow64.dll"
install -m 0644 "$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll" \
  "$prefix/drive_c/windows/system32/wow64win.dll"
while IFS= read -r dll; do
  install -m 0644 "$dll" "$prefix/drive_c/windows/syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

run_wine "$run_root/wineboot.log" "$WINEBOOT" --init
stop_server

extract="$run_root/extracted"
mkdir -p "$extract"
"$EXTRACTOR" --silent --extract --output-dir "$extract" "$EXTRACT_FIXTURE" \
  >"$run_root/innoextract.log" 2>&1
test -f "$extract/app/ISCC.exe"
test -f "$extract/app/Compil32.exe"
echo INNO_NATIVE_ARM64_FALLBACK_OK

fixture="$run_root/fixture"
mkdir -p "$fixture"
install -m 0644 "$VKMT/test/installers/vkmt-inno.iss" "$fixture/"
install -m 0644 "$VKMT/test/installers/vkmt-inno-marker.txt" "$fixture/"
windows_iscc="Z:${extract//\//\\}\\app\\ISCC.exe"
windows_iss="Z:${fixture//\//\\}\\vkmt-inno.iss"
run_wine "$run_root/iscc.log" "$windows_iscc" "$windows_iss"
compiled="$fixture/Output/vkmt-inno-probe.exe"
test -f "$compiled"
grep -q 'Successful compile' "$run_root/iscc.log"
echo INNO_I386_WOW64_COMPILER_OK

"$CLASSIFIER" "$INSTALLER" | grep -qx 'INSTALLER_FAMILY=inno'
"$CLASSIFIER" "$compiled" | grep -qx 'INSTALLER_FAMILY=inno'
payload="$run_root/payload"
mkdir -p "$payload"
"$EXTRACTOR" --silent --extract --output-dir "$payload" "$compiled" \
  >"$run_root/payload-extract.log" 2>&1
test -f "$payload/app/vkmt-inno-marker.txt"
cmp "$VKMT/test/installers/vkmt-inno-marker.txt" \
  "$payload/app/vkmt-inno-marker.txt"
stop_server
echo INNO_COMPILED_PAYLOAD_FALLBACK_OK
echo INNO_EXECUTION_AND_EXTRACTION_ALL_OK
