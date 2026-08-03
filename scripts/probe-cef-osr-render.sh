#!/bin/bash
# Deterministic CEF 109 windowless/OSR pixel gate on the canonical prefix.
# This is intentionally separate from the legacy cefclient/CDP probe: cefclient
# is windowed, while this host owns a CEF render handler and can prove paint.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd -P)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
WINE="$BUILD/wine"
PREFIX="${VKMT_CEF_OSR_PREFIX:-$VKMT/build/probe-runs/phase-a-graphics-prefix}"
EVIDENCE="${VKMT_CEF_OSR_EVIDENCE_DIR:-$VKMT/docs/validation/cef-osr-render-p8}"
URL="${VKMT_CEF_OSR_URL:-}"
test -n "$URL" || URL='data:text/html,<style>body{margin:0;background:rgb(17,34,51)}div{position:absolute;left:100px;top:100px;color:white;font-size:64px;font-family:Arial}</style><div>VKMT_TEXT_OK</div>'
TIMEOUT="${VKMT_CEF_OSR_TIMEOUT:-60}"
HTTPS_TRUST="${VKMT_CEF_OSR_HTTPS_TRUST:-0}"
OPENSSL_BIN="${OPENSSL_BIN:-$(command -v openssl || true)}"
run_root=""
server_pid=""
root_installed=0
timeout_cmd=()

if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=5s)
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=5s)
fi

run_wine_timeout()
{
  if test "${#timeout_cmd[@]}" -gt 0; then
    "${timeout_cmd[@]}" "$@"
  else
    "$@"
  fi
}

case "$PREFIX" in /*) ;; *) echo "CEF OSR prefix must be absolute" >&2; exit 2;; esac
case "$EVIDENCE" in /*) ;; *) echo "CEF OSR evidence directory must be absolute" >&2; exit 2;; esac
case "$TIMEOUT" in ''|*[!0-9]*) echo "CEF OSR timeout must be integer seconds" >&2; exit 2;; esac
case "$HTTPS_TRUST" in 0|1) ;; *) echo "VKMT_CEF_OSR_HTTPS_TRUST must be 0 or 1" >&2; exit 2;; esac
test -f "$PREFIX/.vkmt/receipt.json" || {
  echo "CEF OSR requires the existing receipt-backed prefix: $PREFIX" >&2
  exit 1
}

mkdir -p "$EVIDENCE"

cleanup()
{
  status=$?
  if test "$root_installed" = 1 && test -x "$run_root/tls_trust_arm64.exe" &&
     test -f "$run_root/root.der"; then
    if ! WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
        WINE_NO_EXPLORER=1 WINEDEBUG=-all \
        FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
        run_wine_timeout 20s "$WINE" \
        "Z:$run_root/tls_trust_arm64.exe" remove-root "Z:$run_root/root.der" \
        >"$EVIDENCE/cef-https-root-remove.log" 2>&1; then
      echo "CEF HTTPS trust root removal failed" >&2
      status=1
    fi
  fi
  if test -n "$server_pid"; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  if test -n "$run_root" && test -d "$run_root"; then
    if test "${VKMT_CEF_OSR_KEEP_RUN_ROOT:-0}" = 1; then
      printf 'run_root=%s\n' "$run_root" >"$EVIDENCE/cef-https-run-root.txt"
    else
      case "$run_root" in
        "$VKMT/build/probe-runs"/*) rm -rf "$run_root";;
      esac
    fi
  fi
  exit "$status"
}
trap cleanup EXIT

free_port()
{
  python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()
PY
}

wait_port()
{
  python3 - "$1" <<'PY'
import socket, sys, time
port = int(sys.argv[1])
for _ in range(100):
    try:
        with socket.create_connection(('127.0.0.1', port), 0.1):
            raise SystemExit(0)
    except OSError:
        time.sleep(0.1)
raise SystemExit(1)
PY
}

prepare_https_trust_fixture()
{
  test -x "$WINE" || { echo "missing Wine runtime: $WINE" >&2; return 1; }
  test -x "$OPENSSL_BIN" || { echo "openssl is required for CEF HTTPS trust" >&2; return 1; }
  test -x "$TOOL/aarch64-w64-mingw32-clang" || {
    echo "missing ARM64 LLVM-MinGW compiler: $TOOL/aarch64-w64-mingw32-clang" >&2
    return 1
  }
  run_root="$(mktemp -d "$VKMT/build/probe-runs/cef-osr-https-trust-p8.XXXXXX")"
  mkdir -p "$run_root/web"
  cat >"$run_root/root.ext" <<'EOF'
basicConstraints=critical,CA:TRUE,pathlen:1
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
EOF
  cat >"$run_root/server.ext" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1
authorityKeyIdentifier=keyid,issuer
EOF
  "$OPENSSL_BIN" req -x509 -newkey rsa:2048 -nodes -sha256 -days 3 \
    -keyout "$run_root/root.key" -out "$run_root/root.pem" \
    -subj '/C=US/O=VKMT Test/CN=VKMT CEF Local Root' \
    -addext 'basicConstraints=critical,CA:TRUE,pathlen:1' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign' \
    -addext 'subjectKeyIdentifier=hash' >/dev/null 2>&1 || return 1
  "$OPENSSL_BIN" req -newkey rsa:2048 -nodes -sha256 \
    -keyout "$run_root/server.key" -out "$run_root/server.csr" \
    -subj '/C=US/O=VKMT Test/CN=localhost' >/dev/null 2>&1 || return 1
  "$OPENSSL_BIN" x509 -req -sha256 -days 2 -in "$run_root/server.csr" \
    -CA "$run_root/root.pem" -CAkey "$run_root/root.key" -CAcreateserial \
    -out "$run_root/server.pem" -extfile "$run_root/server.ext" >/dev/null 2>&1 || return 1
  "$OPENSSL_BIN" x509 -in "$run_root/root.pem" -outform DER \
    -out "$run_root/root.der" >/dev/null 2>&1 || return 1
  cat >"$run_root/web/index.html" <<'EOF'
<style>body{margin:0;background:rgb(17,34,51)}div{position:absolute;left:100px;top:100px;color:white;font-size:64px;font-family:Arial}</style><div>VKMT_TEXT_OK</div>
EOF
  "$TOOL/aarch64-w64-mingw32-clang" -std=c11 -O2 -Wall -Wextra -Werror \
    -I"$TOOL/../generic-w64-mingw32/include" -ffixed-x18 -ffixed-x28 \
    -o "$run_root/tls_trust_arm64.exe" "$VKMT/test/tls_trust_contract.c" \
    -lwinhttp -lwininet -lcrypt32 >"$run_root/compile-helper.log" 2>&1 || {
      cat "$run_root/compile-helper.log" >&2
      return 1
    }
  https_port="$(free_port)"
  (cd "$run_root/web" && exec "$OPENSSL_BIN" s_server -quiet -WWW \
      -accept "127.0.0.1:$https_port" -key "$run_root/server.key" \
      -cert "$run_root/server.pem" >"$run_root/https-server.log" 2>&1) &
  server_pid=$!
  wait_port "$https_port" || {
    echo "CEF HTTPS server did not become ready" >&2
    return 1
  }
  WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG=-all \
    FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
    run_wine_timeout 20s "$WINE" "$run_root/tls_trust_arm64.exe" \
    install-root "Z:$run_root/root.der" >"$run_root/root-install.log" 2>&1 || return 1
  grep -q '^TLS_ROOT_INSTALL_OK' "$run_root/root-install.log" || return 1
  root_installed=1
  URL="https://localhost:$https_port/index.html"
  echo "CEF_HTTPS_TRUST_FIXTURE_READY url=$URL root=$run_root/root.der"
}

if test "$HTTPS_TRUST" = 1; then
  prepare_https_trust_fixture || { echo "CEF HTTPS trust fixture setup failed" >&2; exit 1; }
fi

set +e
VKMT_BROWSER_PREFIX="$PREFIX" \
VKMT_BROWSER_LOG_DIR="$EVIDENCE" \
VKMT_BROWSER_URL="$URL" \
VKMT_BROWSER_WINEDEBUG="${VKMT_CEF_OSR_WINEDEBUG:--all}" \
VKMT_BROWSER_WAIT_FOR_RENDER=1 \
VKMT_BROWSER_RENDER_TIMEOUT="$TIMEOUT" \
  "$VKMT/scripts/launch-vkmt-cef-browser.sh" \
  >"$EVIDENCE/driver.log" 2>&1
status=$?
set -e

browser_log="$(find "$EVIDENCE" -maxdepth 1 -type f -name 'browser-*.log' -print | LC_ALL=C sort | tail -1)"
test -n "$browser_log" || { echo "CEF OSR browser log is missing" >&2; exit 1; }
if test "$status" -ne 0; then
  echo "CEF OSR launcher failed (status=$status); log=$browser_log" >&2
  exit "$status"
fi
grep -q 'VKMT_BROWSER_PAINT_BGRA_51_34_17_255' "$browser_log"
grep -q 'VKMT_BROWSER_TEXT_PIXEL_OK' "$browser_log"
grep -q 'VKMT_BROWSER_PIXEL_OK' "$browser_log"
if test "$HTTPS_TRUST" = 1; then
  grep -q '^VKMT_BROWSER_LAUNCH url=https://' "$EVIDENCE/driver.log"
fi
"$VKMT/scripts/vkmt-prefix" verify --prefix "$PREFIX" >"$EVIDENCE/prefix-verify.log"

echo "CEF_X86_64_OSR_PIXEL_OK log=$browser_log text=VKMT_TEXT_OK"
if test "$HTTPS_TRUST" = 1; then
  echo "CEF_X86_64_OSR_HTTPS_TRUST_OK log=$browser_log root=$run_root/root.der"
fi
echo "CEF_X86_64_OSR_RENDER_OK prefix=$PREFIX evidence=$EVIDENCE"
