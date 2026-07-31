#!/bin/bash
# Phase 5 cross-architecture process/provider handoff and Steam binary gates.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
XTAJIT64_BOOTSTRAP="$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll"
XTAJIT_BOOTSTRAP="$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
STEAM_ROOT="$VKMT/prefixes/steam-fullstack-prefix/drive_c/Program Files (x86)/Steam"

export VKMT_XTAJIT64_SOURCE="${VKMT_XTAJIT64_SOURCE:-$VKMT/build/no-tso-phase2/providers/xtajit64-no-tso-final-v15.dll}"
export VKMT_XTAJIT64_SHA256="${VKMT_XTAJIT64_SHA256:-a0a586eb6687dd45bdb4818e44c64294f4cfed89dc5b5bafd806c3d402100513}"
export VKMT_XTAJIT_SOURCE="${VKMT_XTAJIT_SOURCE:-$VKMT/build/no-tso-phase2/providers/xtajit-no-tso-final-v15.dll}"
export VKMT_XTAJIT_SHA256="${VKMT_XTAJIT_SHA256:-67192836cb4eb15cb51ef5487a4ec30a3fa210bfac370e3193ede3760a4e4273}"
export FEX_TSOENABLED=0
export FEX_VECTORTSOENABLED=0
export FEX_MEMCPYSETTSOENABLED=0
export VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY=0

for required in "$WINE" "$WINESERVER" "$WINEBOOT" \
    "$VKMT/test/no_tso_phase5_handoff.c" "$VKMT/test/steam/steamservice_probe.c" \
    "$VKMT/test/steam/steamclient_probe.c" "$VKMT_XTAJIT_SOURCE" \
    "$VKMT_XTAJIT64_SOURCE" "$STEAM_ROOT/steamclient.dll" \
    "$STEAM_ROOT/steamclient64.dll" "$STEAM_ROOT/bin/SteamService.dll" \
    "$STEAM_ROOT/bin/cef/cef.win7x64/steamwebhelper.exe"; do
  test -e "$required" || { echo "Missing Phase 5 input: $required" >&2; exit 1; }
done

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/no-tso-phase5.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=""
bootstrap_staged=0

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  if test "$bootstrap_staged" = 1; then
    install -m 0644 "$run_root/xtajit64.bootstrap.before.dll" "$XTAJIT64_BOOTSTRAP" || status=1
    install -m 0644 "$run_root/xtajit.bootstrap.before.dll" "$XTAJIT_BOOTSTRAP" || status=1
    cmp -s "$run_root/xtajit64.bootstrap.before.dll" "$XTAJIT64_BOOTSTRAP" || status=1
    cmp -s "$run_root/xtajit.bootstrap.before.dll" "$XTAJIT_BOOTSTRAP" || status=1
  fi
  if test -n "${VKMT_PHASE5_EVIDENCE_DIR:-}"; then
    case "$VKMT_PHASE5_EVIDENCE_DIR" in
      "$VKMT"/*)
        mkdir -p "$VKMT_PHASE5_EVIDENCE_DIR"
        find "$run_root" -maxdepth 1 -type f \
          \( -name '*.log' -o -name '*.txt' -o -name '*.sha256' \) \
          -exec cp {} "$VKMT_PHASE5_EVIDENCE_DIR"/ \;
        printf 'status=%s\n' "$status" >"$VKMT_PHASE5_EVIDENCE_DIR/status.txt"
        ;;
      *) echo "Refusing non-VKMT evidence directory: $VKMT_PHASE5_EVIDENCE_DIR" >&2 ;;
    esac
  fi
  case "$run_root" in
    "$RUNS"/no-tso-phase5.*) find "$run_root" -depth -delete 2>/dev/null || true ;;
  esac
  exit "$status"
}
trap cleanup EXIT

run_wine()
{
  output=$1
  debug=$2
  shift 2
  env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG="$debug" WINEDEBUGGER=none \
    "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then code=0; else code=$?; fi
  wine_pid=""
  return "$code"
}

"$TOOL/i686-w64-mingw32-clang" -std=c11 -O2 -Wall -Wextra -Werror -municode \
  "$VKMT/test/no_tso_phase5_handoff.c" -o "$run_root/handoff_i386.exe" -lws2_32
"$TOOL/x86_64-w64-mingw32-clang" -std=c11 -O2 -Wall -Wextra -Werror -municode \
  "$VKMT/test/no_tso_phase5_handoff.c" -o "$run_root/handoff_x64.exe" -lws2_32
"$TOOL/i686-w64-mingw32-clang" -std=c11 -O2 -Wall -Wextra -Werror -municode \
  "$VKMT/test/steam/steamservice_probe.c" -o "$run_root/steamservice_i386.exe" -ladvapi32
for arch in i386 x64; do
  case "$arch" in i386) compiler="$TOOL/i686-w64-mingw32-clang" ;; x64) compiler="$TOOL/x86_64-w64-mingw32-clang" ;; esac
  "$compiler" -std=c11 -O2 -Wall -Wextra -Werror -municode \
    "$VKMT/test/steam/steamclient_probe.c" -o "$run_root/steamclient_$arch.exe"
done
shasum -a 256 "$run_root"/*.exe >"$run_root/fixtures.sha256"

install -m 0644 "$XTAJIT64_BOOTSTRAP" "$run_root/xtajit64.bootstrap.before.dll"
install -m 0644 "$XTAJIT_BOOTSTRAP" "$run_root/xtajit.bootstrap.before.dll"
shasum -a 256 "$run_root"/*.bootstrap.before.dll >"$run_root/bootstrap-before.sha256"
bootstrap_staged=1
install -m 0644 "$VKMT_XTAJIT64_SOURCE" "$XTAJIT64_BOOTSTRAP"
install -m 0644 "$VKMT_XTAJIT_SOURCE" "$XTAJIT_BOOTSTRAP"
echo "$VKMT_XTAJIT64_SHA256  $XTAJIT64_BOOTSTRAP" | shasum -a 256 -c -
echo "$VKMT_XTAJIT_SHA256  $XTAJIT_BOOTSTRAP" | shasum -a 256 -c -

system32="$prefix/drive_c/windows/system32"
syswow64="$prefix/drive_c/windows/syswow64"
mkdir -p "$system32" "$syswow64"
install -m 0644 "$VKMT_XTAJIT64_SOURCE" "$system32/xtajit64.dll"
install -m 0644 "$VKMT_XTAJIT_SOURCE" "$system32/xtajit.dll"
install -m 0644 "$BUILD/dlls/wow64/aarch64-windows/wow64.dll" "$system32/wow64.dll"
install -m 0644 "$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll" "$system32/wow64win.dll"
while IFS= read -r dll; do install -m 0644 "$dll" "$syswow64/$(basename "$dll")"; done \
  < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine "$run_root/wineboot.log" -all "$WINEBOOT" --init
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

mkdir -p "$run_root/handoff-cwd"
win_root="Z:$run_root"
run_wine "$run_root/handoff.log" warn+sync "$run_root/handoff_i386.exe" --root \
  "$win_root/handoff_i386.exe" "$win_root/handoff_x64.exe" "$win_root/handoff-cwd"
grep -q 'NO_TSO_PHASE5_HANDOFF_CHAIN_OK' "$run_root/handoff.log"
grep -q 'VKMT_PROVIDER_ATTACH provider=wow64-i386' "$run_root/handoff.log"
grep -q 'VKMT_PROVIDER_ATTACH provider=arm64ec-x86_64' "$run_root/handoff.log"

steam_win='Z:\Volumes\AverySSD\VKMT\prefixes\steam-fullstack-prefix\drive_c\Program Files (x86)\Steam'
run_wine "$run_root/steamservice.log" -all "$run_root/steamservice_i386.exe" \
  "$steam_win\bin\SteamService.dll"
grep -q 'STEAMSERVICE_I386_IMPORT_TLS_SEH_NONPERSISTENT_DISPATCH_OK' "$run_root/steamservice.log"
run_wine "$run_root/steamclient-i386.log" -all "$run_root/steamclient_i386.exe" \
  "$steam_win\steamclient.dll"
grep -q 'STEAMCLIENT_LOAD_IMPORTS_EXPORTS_FACTORY_SAFE_INIT_OK' "$run_root/steamclient-i386.log"
run_wine "$run_root/steamclient-x64.log" -all "$run_root/steamclient_x64.exe" \
  "$steam_win\steamclient64.dll"
grep -q 'STEAMCLIENT_LOAD_IMPORTS_EXPORTS_FACTORY_SAFE_INIT_OK' "$run_root/steamclient-x64.log"

# A Steam WebHelper subprocess is not a standalone executable: its parent
# supplies Chromium IPC channels, process type, and Steam window handles.
# Inventing those arguments makes the official binary intentionally CHECK.
# Verify the exact x64 image/closure here; Phase 6 proves the real parent launch.
"$TOOL/llvm-readobj" --file-headers --coff-imports \
  "$STEAM_ROOT/bin/cef/cef.win7x64/steamwebhelper.exe" \
  >"$run_root/steamwebhelper-image.txt"
grep -q 'Format: COFF-x86-64' "$run_root/steamwebhelper-image.txt"
grep -q 'Machine: IMAGE_FILE_MACHINE_AMD64' "$run_root/steamwebhelper-image.txt"
grep -q 'Name: KERNEL32.dll' "$run_root/steamwebhelper-image.txt"
grep -q 'Name: USER32.dll' "$run_root/steamwebhelper-image.txt"
echo 'NO_TSO_PHASE5_STEAMWEBHELPER_IMAGE_OK' >"$run_root/webhelper-result.txt"

cat >"$run_root/summary.txt" <<EOF
NO_TSO_PHASE5_CHILD_HANDOFF_OK
FEX_TSOENABLED=0
FEX_VECTORTSOENABLED=0
FEX_MEMCPYSETTSOENABLED=0
chain=i386-root,i386-service,x64-client,x64-webhelper
steamservice=i386-pass
steamclient_i386=pass
steamclient_x64=pass
steamwebhelper_x64=image-and-import-closure-pass
steamwebhelper_parent_launch=phase6-gate
EOF
cat "$run_root/summary.txt"
