#!/bin/bash
# Build and run the M6.0 i386 guest-execution smoke test under native ARM64 Wine.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM_MINGW="${LLVM_MINGW:-$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
WINE_BUILD="$VKMT/wine/build-ec"
PROBE="$VKMT/test/i386_smoke.exe"
XTAJIT="$WINE_BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
WOW64="$WINE_BUILD/dlls/wow64/aarch64-windows/wow64.dll"

test -x "$WINE_BUILD/wine" || { echo "Missing native Wine build" >&2; exit 1; }
test -f "$XTAJIT" || { echo "Missing FEX xtajit.dll; run scripts/build-fex-wow64.sh" >&2; exit 1; }
test -f "$WOW64" || { echo "Missing ARM64 wow64.dll; rebuild the targeted Wine wow64 module" >&2; exit 1; }

export PATH="$LLVM_MINGW/bin:$PATH"
i686-w64-mingw32-gcc -O2 -Wall -Wextra "$VKMT/test/i386_smoke.c" -o "$PROBE"

machine="$($LLVM_MINGW/bin/llvm-readobj --file-headers "$PROBE" | awk '/Machine:/ {print $2; exit}')"
test "$machine" = "IMAGE_FILE_MACHINE_I386" || {
  echo "Probe is not i386: $machine" >&2
  exit 1
}

RUNS_DIR="$VKMT/build/probe-runs"
mkdir -p "$RUNS_DIR"
run_root="$(mktemp -d "$RUNS_DIR/i386-wow64.XXXXXX")"
prefix="$run_root/prefix"
log="$run_root/probe.log"
bootstrap_log="$run_root/bootstrap.log"
marker="$run_root/guest-passed"
marker_win="Z:$marker"
wine_pid=""
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_I386_TIMEOUT:-90}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_I386_TIMEOUT:-90}s")
fi
cleanup() {
  status=$?
  if [[ -n "$wine_pid" ]]; then
    kill -TERM "$wine_pid" 2>/dev/null || true
  fi
  # Ask the server selected by this exact prefix to terminate.  This avoids
  # pattern-killing unrelated Wine sessions and also reaches its child
  # services, whose command lines do not retain WINEPREFIX.
  WINEPREFIX="$prefix" "$WINE_BUILD/server/wineserver" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINE_BUILD/server/wineserver" -w 2>/dev/null || true
  # This is an exact mktemp-created child of the external-SSD run directory.
  # Move it to Trash instead of recursively deleting a Wine prefix.
  case "$run_root" in
    "$RUNS_DIR"/*)
      if [[ "${VKMT_KEEP_PROBE_RUN:-0}" = 1 ]]; then
        echo "Retained disposable probe run: $run_root" >&2
      else
        /usr/bin/trash "$run_root" 2>/dev/null || true
      fi
      ;;
  esac
  exit "$status"
}
trap cleanup EXIT

# A fresh Wine prefix does not install the source-tree i386 module set by
# itself on this custom ARM64EC build.  Stage the provider and every built
# PE32 DLL before the first launch so the gate proves only in-tree artifacts,
# never files inherited from an older prefix.
system32="$prefix/drive_c/windows/system32"
syswow64="$prefix/drive_c/windows/syswow64"
mkdir -p "$system32" "$syswow64"
install -m 0644 "$XTAJIT" "$system32/xtajit.dll"
install -m 0644 "$WOW64" "$system32/wow64.dll"
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
i386_dlls=()
while IFS= read -r dll; do
  i386_dlls+=("$dll")
done < <(find "$WINE_BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)
test "${#i386_dlls[@]}" -gt 0 || { echo "No source-built i386 Wine DLLs found" >&2; exit 1; }
for dll in "${i386_dlls[@]}"; do
  install -m 0644 "$dll" "$syswow64/$(basename "$dll")"
done

echo "i386 probe: $PROBE"
echo "xtajit: $XTAJIT"
echo "staged source-built i386 DLLs: ${#i386_dlls[@]}"

# The first application launch performs Wine's implicit fresh-prefix setup
# around the source-built DLLs staged above.
# On this headless Darwin build that setup can return before it starts the
# requested image, while an explicit wineboot remains attached to Explorer.
# Use the same fixture as a bounded bootstrap pass, then launch it again in the
# initialized prefix for the actual gate.
"${timeout_cmd[@]}" env WINEPREFIX="$prefix" "$WINE_BUILD/wine" "$PROBE" "$marker_win" >"$bootstrap_log" 2>&1 &
wine_pid=$!
if wait "$wine_pid"; then bootstrap_code=0; else bootstrap_code=$?; fi
wine_pid=""

if rg -F 'VKMT i386 WoW64 execution contract passed' "$bootstrap_log" >/dev/null; then
    cp "$bootstrap_log" "$log"
else
    : >"$log"
fi
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

"${timeout_cmd[@]}" env WINEPREFIX="$prefix" "$WINE_BUILD/wine" "$PROBE" "$marker_win" >>"$log" 2>&1 &
wine_pid=$!
if wait "$wine_pid"; then
    probe_code=0
else
    probe_code=$?
    wine_pid=""
    echo "Wine rejected the i386 process before guest execution (bootstrap=$bootstrap_code probe=$probe_code)" >&2
    rg -F 'FEX i386 enter' "$log" >&2 || true
    rg -i 'xtajit|sub-4gb|out of memory|failed to load' "$log" >&2 || true
    tail -n 80 "$log" >&2
    exit 1
fi
wine_pid=""

# The loader client can return after handing the process to wineserver.  Give
# the actual guest a bounded window to complete and publish its gate marker.
for _ in $(seq 1 "${VKMT_I386_MARKER_WAIT:-60}"); do
  [[ -f "$marker" ]] && break
  sleep 1
done

if [[ ! -f "$marker" ]] || ! rg -F 'VKMT i386 WoW64 execution contract passed' "$marker"; then
  echo "i386 guest code did not execute (bootstrap=$bootstrap_code probe=$probe_code main_started=$([[ -f "$marker.started" ]] && echo yes || echo no))" >&2
  rg -i 'xtajit|sub-4gb|out of memory|failed to load' "$log" >&2 || true
  exit 1
fi

echo "i386 execution gate passed"
rg -F 'VKMT i386 WoW64 execution contract passed' "$marker"
rg -i 'xtajit' "$log" || true
