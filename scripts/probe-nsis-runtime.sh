#!/bin/bash
# Prove a real NSIS silent install, installed payload launch, and uninstall.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
FIXTURE="$VKMT/build/installer-fixtures/vkmt-nsis-probe.exe"

"$VKMT/scripts/build-installer-fixtures.sh"
"$VKMT/scripts/build-nsis-fixture.sh"
mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/nsis-runtime.XXXXXX")"
prefix="$run_root/prefix"
timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_NSIS_TIMEOUT:-180}s")
cleanup()
{
  status=$?
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in
    "$RUNS"/*)
      if test "${VKMT_KEEP_PROBE_RUN:-0}" = 1; then
        echo "Retained disposable NSIS run: $run_root" >&2
      else
        /usr/bin/trash "$run_root" 2>/dev/null || true
      fi
      ;;
  esac
  exit "$status"
}
trap cleanup EXIT
run()
{
  log=$1
  shift
  "${timeout_cmd[@]}" env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" \
    WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_NSIS_WINEDEBUG:--all}" \
    "$WINE" "$@" >"$log" 2>&1
}

run_nsis()
{
  log=$1
  shift
  if run "$log" "$@"; then
    return 0
  else
    code=$?
  fi
  # The NSIS outer stub may return ERROR_BAD_LENGTH (24) after handing
  # installation to its inner process. Completion is gated on filesystem
  # state below, not the short-lived launcher's status.
  test "$code" = 24
}

wait_for_path()
{
  mode=$1
  path=$2
  count=0
  while test "$count" -lt 240; do
    if test "$mode" = present && test -e "$path"; then return 0; fi
    if test "$mode" = absent && test ! -e "$path"; then return 0; fi
    sleep 0.25
    count=$((count + 1))
  done
  return 1
}

mkdir -p "$prefix/drive_c/windows/system32" "$prefix/drive_c/windows/syswow64"
install -m 0644 "$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll" \
  "$prefix/drive_c/windows/system32/xtajit.dll"
install -m 0644 "$BUILD/dlls/wow64/aarch64-windows/wow64.dll" \
  "$prefix/drive_c/windows/system32/wow64.dll"
install -m 0644 "$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll" \
  "$prefix/drive_c/windows/system32/wow64win.dll"
while IFS= read -r dll; do
  install -m 0644 "$dll" "$prefix/drive_c/windows/syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run "$run_root/wineboot.log" "$WINEBOOT" --init
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"
WINEPREFIX="$prefix" "$WINESERVER" -k
WINEPREFIX="$prefix" "$WINESERVER" -w
windows_fixture="Z:${FIXTURE//\//\\}"
install_dir="$prefix/drive_c/users/$USER/AppData/Local/VKMTNSISProbe"
run_nsis "$run_root/install.log" "$windows_fixture" /NCRC /S
wait_for_path present "$install_dir/installed.txt"
run "$run_root/payload.log" \
  "C:\\users\\$USER\\AppData\\Local\\VKMTNSISProbe\\vkmt-nsis-payload.exe"
grep -q NSIS_INSTALLED_PAYLOAD_OK "$run_root/payload.log"
run_nsis "$run_root/uninstall.log" \
  "C:\\users\\$USER\\AppData\\Local\\VKMTNSISProbe\\uninstall.exe" /S \
  "_?=C:\\users\\$USER\\AppData\\Local\\VKMTNSISProbe"
wait_for_path absent "$install_dir/installed.txt"
wait_for_path absent "$install_dir/vkmt-nsis-payload.exe"
WINEPREFIX="$prefix" "$WINESERVER" -k
WINEPREFIX="$prefix" "$WINESERVER" -w
if grep -Fq '[Software\\\\VKMT\\\\NSISProbe]' "$prefix/user.reg"; then
  echo "NSIS uninstall left its probe registry key behind" >&2
  exit 1
fi
echo NSIS_I386_WOW64_INSTALL_PAYLOAD_INPLACE_UNINSTALL_OK
