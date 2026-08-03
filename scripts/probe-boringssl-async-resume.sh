#!/bin/bash
# Gate Chromium's asynchronous certificate verification / TLS resume shape.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_ROOT="${VKMT_RUNTIME_ROOT:-$VKMT}"
BUILD="${VKMT_WINE_BUILD:-$RUNTIME_ROOT/wine/build-ec}"
RUNS="${VKMT_PROBE_RUNS:-$VKMT/build/probe-runs}"
PROVIDER_SCRIPT="${VKMT_PROVIDER_SCRIPT:-$RUNTIME_ROOT/scripts/stage-runtime-providers.sh}"
XTAJIT64_SOURCE="${VKMT_XTAJIT64_SOURCE:-}"
XTAJIT64_SHA256="${VKMT_XTAJIT64_SHA256:-}"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
PROBE="$VKMT/build/boringssl-chromium109-x64/boringssl-async-resume-probe.exe"

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/boringssl-async.XXXXXX")"
prefix="$run_root/prefix"
server_pid=

cleanup()
{
  rc=$?
  test -z "$server_pid" || kill "$server_pid" 2>/dev/null || true
  test -z "$server_pid" || wait "$server_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  if test -n "${VKMT_BORINGSSL_ASYNC_EVIDENCE_DIR:-}"; then
    mkdir -p "$VKMT_BORINGSSL_ASYNC_EVIDENCE_DIR"
    find "$run_root" -maxdepth 1 -type f -name '*.log' \
      -exec cp -p {} "$VKMT_BORINGSSL_ASYNC_EVIDENCE_DIR/" \;
    cp -p "$run_root/https/cert.pem" "$VKMT_BORINGSSL_ASYNC_EVIDENCE_DIR/" 2>/dev/null || true
  fi
  case "$run_root" in "$RUNS"/*)
    test "${VKMT_KEEP_PROBE_RUN:-0}" = 1 ||
      find "$run_root" -depth -delete 2>/dev/null || true
  esac
  exit "$rc"
}
trap cleanup EXIT

test -x "$WINE" && test -x "$WINESERVER" && test -f "$WINEBOOT"
test -x "$PROVIDER_SCRIPT" && test -f "$PROBE"
mkdir -p "$prefix/drive_c/windows/system32" "$prefix/drive_c/windows/syswow64" "$run_root/https"

openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
  -nodes -days 1 -subj /CN=localhost \
  -keyout "$run_root/https/key.pem" -out "$run_root/https/cert.pem" \
  >"$run_root/cert.log" 2>&1
openssl s_server -quiet -www -accept 127.0.0.1:19445 \
  -key "$run_root/https/key.pem" -cert "$run_root/https/cert.pem" \
  >"$run_root/server.log" 2>&1 &
server_pid=$!

for dll in xtajit64 xtajit wow64 wow64win; do
  install -m 0644 "$BUILD/dlls/$dll/aarch64-windows/$dll.dll" \
    "$prefix/drive_c/windows/system32/$dll.dll"
done
while IFS= read -r dll; do
  install -m 0644 "$dll" "$prefix/drive_c/windows/syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

export VKMT_RUNTIME_ROOT="$RUNTIME_ROOT" WINEBUILDDIR="$BUILD" WINEPREFIX="$prefix"
env -u VKMT_XTAJIT64_SOURCE -u VKMT_XTAJIT64_SHA256 \
  "$PROVIDER_SCRIPT" --prefix "$prefix"
env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
  WINE_NO_EXPLORER=1 WINEDEBUG=-all FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 \
  FEX_MEMCPYSETTSOENABLED=0 \
  DYLD_LIBRARY_PATH="$BUILD/dlls/winecoreaudio.drv:$BUILD/dlls/secur32:$BUILD/dlls/ntdll:$BUILD/dlls/win32u${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
  gtimeout --signal=TERM --kill-after=10s 120s "$WINE" "$WINEBOOT" --init \
  >"$run_root/wineboot.log" 2>&1
WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
env -u VKMT_XTAJIT64_SOURCE -u VKMT_XTAJIT64_SHA256 \
  "$PROVIDER_SCRIPT" --prefix "$prefix"
env -u VKMT_XTAJIT64_SOURCE -u VKMT_XTAJIT64_SHA256 \
  "$PROVIDER_SCRIPT" --verify-prefix "$prefix"
if test -n "$XTAJIT64_SOURCE"; then
  test -n "$XTAJIT64_SHA256"
  echo "$XTAJIT64_SHA256  $XTAJIT64_SOURCE" | shasum -a 256 -c -
  install -m 0644 "$XTAJIT64_SOURCE" \
    "$prefix/drive_c/windows/system32/xtajit64.dll"
fi

cp -p "$PROBE" "$run_root/"
cp -p "$VKMT/build/boringssl-chromium109-x64/libwinpthread-1.dll" "$run_root/"
env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
  WINE_NO_EXPLORER=1 WINEDEBUG=-all FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 \
  FEX_MEMCPYSETTSOENABLED=0 \
  DYLD_LIBRARY_PATH="$BUILD/dlls/winecoreaudio.drv:$BUILD/dlls/secur32:$BUILD/dlls/ntdll:$BUILD/dlls/win32u${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
  gtimeout --signal=TERM --kill-after=10s 60s "$WINE" \
  "$run_root/boringssl-async-resume-probe.exe" 19445 \
  >"$run_root/probe.log" 2>&1
grep -q VKMT_BORINGSSL_ASYNC_OK "$run_root/probe.log"
cat "$run_root/probe.log"
echo BORINGSSL_ASYNC_CERT_VERIFY_RESUME_OK
