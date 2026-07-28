#!/bin/bash
# Prove install, repair, and uninstall through MSI APIs in every guest mode.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
FIXTURES="$VKMT/build/installer-fixtures"
SOURCE="$VKMT/test/msi_runtime_probe.c"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
XTAJIT64="$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll"
XTAJIT="$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
WOW64="$BUILD/dlls/wow64/aarch64-windows/wow64.dll"
WOW64WIN="$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll"

"$VKMT/scripts/build-installer-fixtures.sh"
for required in "$SOURCE" "$WINE" "$WINESERVER" "$WINEBOOT" "$XTAJIT64" \
    "$XTAJIT" "$WOW64" "$WOW64WIN" "$FIXTURES/vkmt-msi-x86.msi" \
    "$FIXTURES/vkmt-msi-x64.msi"; do
  test -e "$required" || { echo "Missing MSI-runtime artifact: $required" >&2; exit 1; }
done

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/msi-runtime.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=""
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_MSI_TIMEOUT:-180}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_MSI_TIMEOUT:-180}s")
fi

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in "$RUNS"/*) /usr/bin/trash "$run_root" 2>/dev/null || true;; esac
  exit "$status"
}
trap cleanup EXIT

stop_server()
{
  WINEPREFIX="$prefix" "$WINESERVER" -k
  WINEPREFIX="$prefix" "$WINESERVER" -w
}

run_wine()
{
  output=$1
  shift
  "${timeout_cmd[@]}" env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" \
    WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_MSI_WINEDEBUG:--all}" \
    "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then code=0; else code=$?; fi
  wine_pid=""
  return "$code"
}

compile()
{
  compiler=$1
  output=$2
  shift 2
  "$TOOL/$compiler" -O2 -g -Wall -Wextra "$@" "$SOURCE" -o "$output" -lmsi
}
compile aarch64-w64-mingw32-clang "$run_root/arm64.exe" -ffixed-x18 -ffixed-x28
compile arm64ec-w64-mingw32-clang "$run_root/arm64ec.exe" -ffixed-x18 -ffixed-x28
compile x86_64-w64-mingw32-clang "$run_root/x86_64.exe" -fno-vectorize -fno-slp-vectorize
compile i686-w64-mingw32-clang "$run_root/i386.exe"

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

run_wine "$run_root/wineboot.log" "$WINEBOOT" --init || {
  echo "MSI-runtime wineboot failed" >&2
  tail -n 160 "$run_root/wineboot.log" >&2
  exit 1
}
stop_server

for arch in ${VKMT_MSI_ARCHES:-arm64 arm64ec x86_64 i386}; do
  package="$FIXTURES/vkmt-msi-x86.msi"
  test "$arch" != x86_64 || package="$FIXTURES/vkmt-msi-x64.msi"
  windows_package="Z:${package//\//\\}"
  for action in install damage repair uninstall; do
    log="$run_root/${arch}_${action}.log"
    if ! run_wine "$log" "$run_root/$arch.exe" "$action" "$windows_package"; then
      install -m 0644 "$log" "$VKMT/build/msi-runtime.latest.log"
      echo "$arch MSI $action failed" >&2
      tail -n 200 "$log" >&2
      exit 1
    fi
    grep -q "MSI_$(printf '%s' "$action" | tr '[:lower:]' '[:upper:]')_OK" "$log" || {
      echo "$arch MSI $action marker missing" >&2
      tail -n 200 "$log" >&2
      exit 1
    }
  done
  arch_upper="$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')"
  echo "MSI_${arch_upper}_INSTALL_REPAIR_UNINSTALL_OK"
  stop_server
done
echo MSI_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
