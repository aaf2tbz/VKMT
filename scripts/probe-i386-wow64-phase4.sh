#!/bin/bash
# Prove the complete Phase 4 i386/WoW64 system contract in one clean prefix.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM_MINGW="${LLVM_MINGW:-$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
WINE_BUILD="$VKMT/wine/build-ec"
TEST_DIR="$VKMT/test/i386"
PHASE4_EXE="$TEST_DIR/phase4_contract.exe"
PHASE4_DLL="$TEST_DIR/phase4_helper.dll"
PHASE3_EXE="$VKMT/test/i386_smoke.exe"
XTAJIT="${VKMT_XTAJIT_SOURCE:-$WINE_BUILD/dlls/xtajit/aarch64-windows/xtajit.dll}"
XTAJIT_SHA256="${VKMT_XTAJIT_SHA256:-$(shasum -a 256 "$XTAJIT" | awk '{print $1}')}"
WOW64="$WINE_BUILD/dlls/wow64/aarch64-windows/wow64.dll"
WOW64WIN="$WINE_BUILD/dlls/wow64win/aarch64-windows/wow64win.dll"
NTDLL_SO="$WINE_BUILD/dlls/ntdll/ntdll.so"
WINEBOOT="$WINE_BUILD/programs/wineboot/aarch64-windows/wineboot.exe"

test -x "$WINE_BUILD/wine" || { echo "Missing native Wine build" >&2; exit 1; }
test -f "$XTAJIT" || { echo "Missing FEX xtajit.dll" >&2; exit 1; }
echo "$XTAJIT_SHA256  $XTAJIT" | shasum -a 256 -c -
test -f "$WOW64" || { echo "Missing ARM64 wow64.dll" >&2; exit 1; }
test -f "$WOW64WIN" || { echo "Missing ARM64 wow64win.dll" >&2; exit 1; }
test -f "$WINEBOOT" || { echo "Missing native ARM64 wineboot.exe" >&2; exit 1; }
export PATH="$LLVM_MINGW/bin:$PATH"

# Host executables and Unix bridges must be native ARM64-only. Guest execution
# is provided by ARM64 PE modules; no x86 Mach-O/Rosetta component is valid.
for macho in "$WINE_BUILD/wine" "$WINE_BUILD/server/wineserver" "$NTDLL_SO"; do
  archs="$(/usr/bin/lipo -archs "$macho")"
  test "$archs" = arm64 || { echo "Non-ARM64-only host artifact: $macho ($archs)" >&2; exit 1; }
done
for pe in "$XTAJIT" "$WOW64" "$WOW64WIN"; do
  machine="$($LLVM_MINGW/bin/llvm-readobj --file-headers "$pe" | awk '/Machine:/ {print $2; exit}')"
  test "$machine" = IMAGE_FILE_MACHINE_ARM64 || { echo "Non-ARM64 WoW64 host PE: $pe ($machine)" >&2; exit 1; }
done

i686-w64-mingw32-clang -O2 -g -Wall -Wextra -shared \
  "$TEST_DIR/phase4_helper.c" -Wl,--kill-at -o "$PHASE4_DLL"
i686-w64-mingw32-clang -O2 -g -Wall -Wextra \
  "$TEST_DIR/phase4_contract.c" -o "$PHASE4_EXE" -luser32
i686-w64-mingw32-clang -O2 -g -Wall -Wextra \
  "$VKMT/test/i386_smoke.c" -o "$PHASE3_EXE"

for pe in "$PHASE4_EXE" "$PHASE4_DLL" "$PHASE3_EXE"; do
  machine="$($LLVM_MINGW/bin/llvm-readobj --file-headers "$pe" | awk '/Machine:/ {print $2; exit}')"
  test "$machine" = IMAGE_FILE_MACHINE_I386 || { echo "Not i386: $pe ($machine)" >&2; exit 1; }
done

RUNS_DIR="$VKMT/build/probe-runs"
mkdir -p "$RUNS_DIR"
run_root="$(mktemp -d "$RUNS_DIR/i386-phase4.XXXXXX")"
prefix="$run_root/prefix"
log="$run_root/phase4.log"
bootstrap_log="$run_root/bootstrap.log"
phase4_marker="$run_root/phase4-markers"
phase3_marker="$run_root/phase3-marker"
wine_pid=""
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_I386_PHASE4_TIMEOUT:-120}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_I386_PHASE4_TIMEOUT:-120}s")
fi

cleanup() {
  status=$?
  [[ -z "$wine_pid" ]] || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINE_BUILD/server/wineserver" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINE_BUILD/server/wineserver" -w 2>/dev/null || true
  case "$run_root" in
    "$RUNS_DIR"/*)
      if [[ "${VKMT_KEEP_PROBE_RUN:-0}" = 1 ]]; then
        echo "Retained disposable Phase 4 run: $run_root" >&2
      else
        find "$run_root" -depth -delete 2>/dev/null || true
      fi
      ;;
  esac
  exit "$status"
}
trap cleanup EXIT

system32="$prefix/drive_c/windows/system32"
syswow64="$prefix/drive_c/windows/syswow64"
mkdir -p "$system32" "$syswow64"
install -m 0644 "$XTAJIT" "$system32/xtajit.dll"
install -m 0644 "$WOW64" "$system32/wow64.dll"
install -m 0644 "$WOW64WIN" "$system32/wow64win.dll"
i386_dlls=()
while IFS= read -r dll; do i386_dlls+=("$dll"); done \
  < <(find "$WINE_BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)
test "${#i386_dlls[@]}" -gt 0 || { echo "No source-built i386 Wine DLLs found" >&2; exit 1; }
for dll in "${i386_dlls[@]}"; do
  install -m 0644 "$dll" "$syswow64/$(basename "$dll")"
done
install -m 0644 "$PHASE4_DLL" "$syswow64/phase4_helper.dll"

run_wine() {
  local output=$1
  shift
  "${timeout_cmd[@]}" env WINEPREFIX="$prefix" WINEBUILDDIR="$WINE_BUILD" WINEBOOTSTRAPMODE=1 \
    WINEDEBUG="${VKMT_I386_WINEDEBUG:--all}" WINE_NO_EXPLORER=1 \
    FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
    "$WINE_BUILD/wine" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then run_code=0; else run_code=$?; fi
  wine_pid=""
  return "$run_code"
}

echo "Phase 4 i386 DLLs staged: ${#i386_dlls[@]}"
# Prove the named bootstrap boundary explicitly. Build-tree mode lets the
# native ARM64 wineboot resolve in-tree builtins before prefix links exist.
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
if ! run_wine "$bootstrap_log" "$WINEBOOT" --init; then
  echo "Phase 4 native ARM64 wineboot failed" >&2
  tail -n 120 "$bootstrap_log" >&2
  exit 1
fi
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

if run_wine "$log" "$PHASE4_EXE" "Z:$phase4_marker"; then code=0; else code=$?; fi
for _ in $(seq 1 "${VKMT_I386_PHASE4_MARKER_WAIT:-60}"); do
  if [[ -f "$phase4_marker" ]] && rg -q 'P4_(ALL_SYSTEM_CONTRACT_OK|FAIL_)' "$phase4_marker"; then break; fi
  sleep 1
done
if [[ "$code" -ne 0 ]] || [[ ! -f "$phase4_marker" ]] || rg -q 'P4_FAIL_' "$phase4_marker"; then
  echo "Phase 4 fixture failed with exit $code" >&2
  [[ ! -f "$phase4_marker" ]] || { echo "Completed markers:" >&2; sed -n '1,120p' "$phase4_marker" >&2; }
  tail -n 120 "$log" >&2
  exit 1
fi
required=(LOADLIBRARY SYSCALL_RETURN TLS_MAIN CONTEXT SEH APC SECOND_THREAD USER_CALLBACK THREAD_LIFECYCLE ALL_SYSTEM_CONTRACT)
for gate in "${required[@]}"; do
  rg -F "P4_${gate}_OK" "$phase4_marker" >/dev/null || { echo "Missing Phase 4 gate: $gate" >&2; exit 1; }
done

if run_wine "$run_root/phase3.log" "$PHASE3_EXE" "Z:$phase3_marker"; then
  :
else
  echo "Phase 3 regression failed inside Phase 4 prefix" >&2
  exit 1
fi
rg -F 'VKMT i386 WoW64 execution contract passed' "$phase3_marker" >/dev/null || {
  echo "Missing Phase 3 regression marker" >&2
  exit 1
}

echo "Phase 4 WoW64 system contract passed"
sed -n '1,120p' "$phase4_marker"
sed -n '1,20p' "$phase3_marker"
