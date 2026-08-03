#!/bin/bash
# Prove pinned Electron x64 and i386 renderer/runtime behavior in one prepared
# prefix. Pass --prefix to reuse a receipt-backed prefix; without it the
# legacy disposable probe mode is retained.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
RUNS="$VKMT/build/probe-runs"
ELECTRON="$VKMT/third_party/electron-42.7.1"
APP="$VKMT/test/browser/electron"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
PREFIX_ARG="${VKMT_ELECTRON_PREFIX:-}"
EVIDENCE="${VKMT_ELECTRON_EVIDENCE_DIR:-}"

usage()
{
  echo "usage: $0 [--prefix EXISTING_VKMT_PREFIX]" >&2
  exit 2
}

while test "$#" -gt 0; do
  case "$1" in
    --prefix)
      test "$#" -ge 2 || usage
      PREFIX_ARG=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

use_existing_prefix=0
if test -n "$PREFIX_ARG"; then
  case "$PREFIX_ARG" in /*) ;; *) echo "Electron prefix must be absolute" >&2; exit 2 ;; esac
  PREFIX_ARG="$(cd "$PREFIX_ARG" && pwd -P)"
  test -f "$PREFIX_ARG/.vkmt/receipt.json" || {
    echo "Electron prefix is not a receipt-backed VKMT prefix: $PREFIX_ARG" >&2
    exit 1
  }
  use_existing_prefix=1
fi

"$VKMT/scripts/fetch-electron-runtime.sh"
mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/electron-runtime.XXXXXX")"
prefix="${PREFIX_ARG:-$run_root/prefix}"
trace_dir="${VKMT_ELECTRON_TRACE_DIR:-$run_root/traces}"
mkdir -p "$trace_dir"
https_pid=

cleanup()
{
  status=$?
  test -z "$https_pid" || kill "$https_pid" 2>/dev/null || true
  test -z "$https_pid" || wait "$https_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  if test -n "$EVIDENCE"; then
    mkdir -p "$EVIDENCE"
    find "$run_root" -maxdepth 1 -type f -exec cp -p {} "$EVIDENCE/" \;
    if test -d "$trace_dir"; then
      rm -rf "$EVIDENCE/traces"
      cp -R "$trace_dir" "$EVIDENCE/traces"
    fi
  fi
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
  timeout_seconds=$2
  shift 2
  gtimeout --signal=TERM --kill-after=10s "$timeout_seconds" \
    env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
      DYLD_LIBRARY_PATH="$BUILD/dlls/winecoreaudio.drv:$BUILD/dlls/secur32:$BUILD/dlls/ntdll:$BUILD/dlls/win32u${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
      WINEDEBUG="${VKMT_ELECTRON_WINEDEBUG:-+process}" \
      FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
      VKMT_ELECTRON_SOFTWARE_RENDER="${VKMT_ELECTRON_SOFTWARE_RENDER:-1}" \
      VKMT_WOW64_VM_TRACE="${VKMT_WOW64_VM_TRACE:-1}" \
      VKMT_PERF_RUN_ID="${VKMT_PERF_RUN_ID:-electron-bootstrap}" \
      VKMT_PERF_TRACE_HOST_DIR="$trace_dir" \
      "$WINE" "$@" >"$output" 2>&1
}

stop_server()
{
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
}

duration_arg()
{
  case "$1" in
    *s|*m|*h) printf '%s' "$1" ;;
    *) printf '%ss' "$1" ;;
  esac
}

probe_failures=0

electron_extra_args=()
if test -n "${VKMT_ELECTRON_EXTRA_ARGS:-}"; then
  read -r -a electron_extra_args <<<"$VKMT_ELECTRON_EXTRA_ARGS"
fi

winpath()
{
  printf 'Z:%s' "${1//\//\\}"
}

mkdir -p "$prefix/drive_c/windows/system32" "$prefix/drive_c/windows/syswow64"
if test "$use_existing_prefix" = 1; then
  # Keep the prepared prefix as the source of truth. Only sync the rebuilt
  # WoW64 bridge; its i386 closure is already staged and receipt-backed.
  "$VKMT/scripts/vkmt-prefix" sync-wow64 --prefix "$prefix"
else
  for dll in xtajit64 xtajit wow64 wow64win; do
    install -m 0644 "$BUILD/dlls/$dll/aarch64-windows/$dll.dll" \
      "$prefix/drive_c/windows/system32/$dll.dll"
  done
  while IFS= read -r dll; do
    install -m 0644 "$dll" "$prefix/drive_c/windows/syswow64/$(basename "$dll")"
  done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)
fi

mkdir -p "$run_root/https"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=127.0.0.1 \
  -keyout "$run_root/https/key.pem" -out "$run_root/https/cert.pem" \
  >"$run_root/https/cert.log" 2>&1
openssl s_server -quiet -www -accept 127.0.0.1:19444 \
  -key "$run_root/https/key.pem" -cert "$run_root/https/cert.pem" \
  >"$run_root/https/server.log" 2>&1 &
https_pid=$!

if test "$use_existing_prefix" = 0 || test "${VKMT_ELECTRON_RESTAGE_PROVIDERS:-0}" = 1; then
  "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
fi
if test "$use_existing_prefix" = 1; then
  stop_server
  if test "${VKMT_ELECTRON_WINEBOOT_UPDATE:-0}" = 1; then
    VKMT_PERF_RUN_ID=electron-wineboot run_wine \
      "$run_root/wineboot-update.log" "$(duration_arg "${VKMT_ELECTRON_BOOT_TIMEOUT:-120}")" \
      "$WINEBOOT" --update
    stop_server
    "$VKMT/scripts/vkmt-prefix" sync-wow64 --prefix "$prefix"
    test ! -f "$prefix/.vkmt/dxmt-arm64ec.sha256" ||
      "$VKMT/scripts/vkmt-prefix" sync-dxmt --prefix "$prefix"
  fi
else
  VKMT_PERF_RUN_ID=electron-wineboot run_wine \
    "$run_root/wineboot.log" "$(duration_arg "${VKMT_ELECTRON_BOOT_TIMEOUT:-120}")" \
    "$WINEBOOT" --init
  stop_server
fi
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"
if test "$use_existing_prefix" = 1; then
  # Candidate-provider diagnostics may intentionally stage an unpromoted
  # ARM64EC provider into the canonical working prefix. Keep the normal
  # receipt gate strict; only an explicit diagnostic opt-out may skip the
  # project-level hash check, and the caller must restore the canonical
  # provider before accepting the prefix again.
  if test "${VKMT_ELECTRON_SKIP_PREFIX_VERIFY:-0}" != 1; then
    "$VKMT/scripts/vkmt-prefix" verify --prefix "$prefix"
  fi
fi

for spec in x64:x64 i386:ia32; do
  IFS=: read -r arch runtime_arch <<<"$spec"
  case ",${VKMT_ELECTRON_ARCHES:-x64,i386}," in
    *",$arch,"*) ;;
    *) continue ;;
  esac
  result="$run_root/$arch-result.txt"
  log="$run_root/$arch.log"
  arch_status=0
  VKMT_PERF_RUN_ID="electron-$arch" \
  VKMT_ELECTRON_RESULT="$(winpath "$result")" \
  VKMT_ELECTRON_HTTPS_URL="https://127.0.0.1:19444/" \
    run_wine "$log" "$(duration_arg "${VKMT_ELECTRON_PROBE_TIMEOUT:-120}")" \
      "$ELECTRON/windows-$runtime_arch/electron.exe" "$(winpath "$APP")" \
      ${electron_extra_args[@]+"${electron_extra_args[@]}"} || arch_status=$?
  stop_server
  trace_count="$(find "$trace_dir" -type f -name "vkmt-perf-electron-$arch-*.tsv" -print | wc -l | tr -d ' ')"
  if test "$trace_count" -gt 0; then
    echo "ELECTRON_$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')_FEX_ALLOCATION_TRACE_OK files=$trace_count"
  else
    echo "ELECTRON_$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')_FEX_ALLOCATION_TRACE_MISSING"
    arch_status=1
  fi
  if test ! -f "$result" || ! grep -q ELECTRON_HTTPS_INPUT_AUDIO_PIXEL_OK "$result"; then
    echo "ELECTRON_$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')_RESULT_MISSING"
    arch_status=1
  fi
  if ! grep -Eq 'electron.exe.*--type=renderer' "$log"; then
    echo "ELECTRON_$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')_RENDERER_MISSING"
    arch_status=1
  fi
  if ! grep -Eq 'electron.exe.*--type=(gpu-process|utility)' "$log"; then
    echo "ELECTRON_$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')_GPU_UTILITY_MISSING"
    arch_status=1
  fi
  if test "$arch_status" -eq 0; then
    echo "ELECTRON_$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')_OK"
  else
    echo "ELECTRON_$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')_DIAGNOSTIC_FAIL rc=${arch_status}"
    probe_failures=1
  fi
done

if test "$probe_failures" -eq 0; then
  echo "ELECTRON_${VKMT_ELECTRON_ARCHES:-x64,i386}_ALL_OK" | tr '[:lower:],' '[:upper:]_'
else
  echo "ELECTRON_${VKMT_ELECTRON_ARCHES:-x64,i386}_DIAGNOSTIC_COMPLETE" | tr '[:lower:],' '[:upper:]_'
fi
exit "$probe_failures"
