#!/bin/bash
# Prove native ARM64 MSI/WiX upgrade, environment, shortcut, service,
# msiexec, and msidb behavior in one disposable prefix. Guest architectures
# can be selected explicitly for diagnostics; the core all-architecture MSI
# API lifecycle is covered by probe-msi-runtime.sh.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
RUNS="$VKMT/build/probe-runs"
FIXTURES="$VKMT/build/installer-fixtures"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
XTAJIT64="$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll"
XTAJIT="$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
WOW64="$BUILD/dlls/wow64/aarch64-windows/wow64.dll"
WOW64WIN="$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll"

"$VKMT/scripts/build-installer-fixtures.sh"
mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/installer-extended.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=""
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_INSTALLER_TIMEOUT:-120}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_INSTALLER_TIMEOUT:-120}s")
fi

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in
    "$RUNS"/*)
      test "${VKMT_KEEP_PROBE_RUN:-0}" = 1 ||
        /usr/bin/trash "$run_root" 2>/dev/null || true
      ;;
  esac
  exit "$status"
}
trap cleanup EXIT

run_wine()
{
  output=$1
  shift
  "${timeout_cmd[@]}" env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_INSTALLER_WINEDEBUG:--all}" \
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

system32="$prefix/drive_c/windows/system32"
syswow64="$prefix/drive_c/windows/syswow64"
mkdir -p "$system32" "$syswow64"
install -m 0644 "$XTAJIT64" "$system32/xtajit64.dll"
install -m 0644 "$XTAJIT" "$system32/xtajit.dll"
install -m 0644 "$WOW64" "$system32/wow64.dll"
install -m 0644 "$WOW64WIN" "$system32/wow64win.dll"
while IFS= read -r dll; do
  install -m 0644 "$dll" "$syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

run_wine "$run_root/wineboot.log" "$WINEBOOT" --init
stop_server

for arch in ${VKMT_INSTALLER_ARCHES:-arm64}; do
  case "$arch" in
    arm64|arm64ec)
      msiexec="$BUILD/programs/msiexec/aarch64-windows/msiexec.exe"
      msidb="$BUILD/programs/msidb/aarch64-windows/msidb.exe"
      fixture_arch=x86
      ;;
    x86_64)
      msiexec="$BUILD/programs/msiexec/x86_64-windows/msiexec.exe"
      msidb="$BUILD/programs/msidb/x86_64-windows/msidb.exe"
      fixture_arch=x64
      ;;
    i386)
      msiexec="$BUILD/programs/msiexec/i386-windows/msiexec.exe"
      msidb="$BUILD/programs/msidb/i386-windows/msidb.exe"
      fixture_arch=x86
      ;;
  esac
  v1="$FIXTURES/vkmt-msi-extended-$fixture_arch-v1.msi"
  v2="$FIXTURES/vkmt-msi-extended-$fixture_arch-v2.msi"
  win_v1="Z:${v1//\//\\}"
  win_v2="Z:${v2//\//\\}"
  export_dir="$run_root/msidb-$arch"
  mkdir -p "$export_dir"
  win_export="Z:${export_dir//\//\\}"

  run_wine "$run_root/$arch-msidb.log" "$msidb" -d "$win_v1" -f "$win_export" -e Property
  test -s "$export_dir/Property.idt"
  grep -q 'ProductVersion.*1.0.0' "$export_dir/Property.idt"

  run_wine "$run_root/$arch-install.log" "$msiexec" /i "$win_v1" /qn
  stop_server
  test -f "$prefix/drive_c/VKMT MSI Extended/vkmt-msi-marker.txt"
  grep -q 'VKMT_MSI_PAYLOAD_V1' "$prefix/drive_c/VKMT MSI Extended/vkmt-msi-marker.txt"
  grep -q 'VKMT_MSI_ENV' "$prefix/user.reg"
  grep -q 'VKMTMsiProbe' "$prefix/system.reg"
  find "$prefix/drive_c/users" -type f -name 'VKMT MSI Extended.lnk' -print -quit |
    grep -q .

  run_wine "$run_root/$arch-upgrade.log" "$msiexec" /i "$win_v2" /qn
  stop_server
  grep -q 'VKMT_MSI_PAYLOAD_V2' "$prefix/drive_c/VKMT MSI Extended/vkmt-msi-v2-marker.txt"
  test ! -e "$prefix/drive_c/VKMT MSI Extended/vkmt-msi-marker.txt"

  run_wine "$run_root/$arch-uninstall.log" "$msiexec" /x \
    '{D0A8B320-6D92-4CA7-A071-000000000202}' /qn
  stop_server
  test ! -e "$prefix/drive_c/VKMT MSI Extended"
  arch_upper="$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')"
  echo "INSTALLER_${arch_upper}_MSI_EXTENDED_OK"
done

echo INSTALLER_NATIVE_ARM64_MSI_WIX_EXTENDED_OK
