#!/bin/bash
# Deterministic local trust contract for WinHTTP and WinINet.  This uses the
# existing Phase A prefix and local OpenSSL servers only; it never enables an
# ignore-certificate-errors flag and never invokes wineboot.
set -uo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd -P)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
WINE="$BUILD/wine"
PREFIX="${VKMT_TLS_PREFIX:-$VKMT/build/probe-runs/phase-a-graphics-prefix}"
EVIDENCE="${VKMT_TLS_EVIDENCE_DIR:-$VKMT/docs/validation/tls-trust-contract-p8-20260803}"
TIMEOUT_VALUE="${VKMT_TLS_TIMEOUT:-45}"
TIMEOUT="${TIMEOUT_VALUE%s}s"
OPENSSL_BIN="${OPENSSL_BIN:-$(command -v openssl || true)}"
WINEDEBUG_VALUE="${VKMT_TLS_WINEDEBUG:--all}"
ARCHES="${VKMT_TLS_ARCHES:-arm64 arm64ec x86_64 i386}"
run_root=""
overall=0

usage() { echo "usage: $0 [--prefix ABSOLUTE_PATH] [--evidence-dir ABSOLUTE_PATH]" >&2; exit 2; }
while test "$#" -gt 0; do
    case "$1" in
        --prefix) test "$#" -ge 2 || usage; PREFIX=$2; shift 2;;
        --evidence-dir) test "$#" -ge 2 || usage; EVIDENCE=$2; shift 2;;
        *) usage;;
    esac
done
case "$PREFIX" in /*) ;; *) echo "prefix must be absolute: $PREFIX" >&2; exit 2;; esac
case "$EVIDENCE" in /*) ;; *) echo "evidence directory must be absolute: $EVIDENCE" >&2; exit 2;; esac
test -x "$WINE" || { echo "missing Wine runtime: $WINE" >&2; exit 1; }
test -d "$PREFIX/.vkmt" || { echo "prefix is not receipt-backed: $PREFIX" >&2; exit 1; }
test -n "$OPENSSL_BIN" && test -x "$OPENSSL_BIN" || { echo "openssl is required" >&2; exit 1; }
mkdir -p "$VKMT/build/probe-runs" "$EVIDENCE"
run_root="$(mktemp -d "$VKMT/build/probe-runs/tls-trust-contract-p8.XXXXXX")"

cleanup()
{
    status=$?
    if test -n "${crl_pid:-}"; then
        kill "$crl_pid" 2>/dev/null || true
        wait "$crl_pid" 2>/dev/null || true
    fi
    if test -n "${proxy_pid:-}"; then
        kill "$proxy_pid" 2>/dev/null || true
        wait "$proxy_pid" 2>/dev/null || true
    fi
    if test -x "$run_root/tls_trust_arm64.exe" && test -f "$run_root/root.der" &&
       test -f "$run_root/intermediate.crl"; then
        env WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
            WINE_NO_EXPLORER=1 WINEDEBUG=-all \
            FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
            timeout --signal=TERM --kill-after=5s 15s "$WINE" \
            "Z:$run_root/tls_trust_arm64.exe" remove "Z:$run_root/root.der" \
            "Z:$run_root/intermediate.crl" >/dev/null 2>&1 || true
    fi
    if test -n "$run_root" && test -d "$run_root"; then
        find "$run_root" -maxdepth 1 -type f \( -name '*.log' -o -name '*.txt' -o -name '*.tsv' \) \
            -exec cp -p {} "$EVIDENCE/" \; 2>/dev/null || true
    fi
    printf 'status=%s\n' "$status" >"$EVIDENCE/status.txt"
    if test "${VKMT_TLS_KEEP_RUN_ROOT:-0}" = 1; then
        printf 'run_root=%s\n' "$run_root" >"$EVIDENCE/run-root.txt"
    else
        case "$run_root" in "$VKMT/build/probe-runs"/*) rm -rf "$run_root";; esac
    fi
    exit "$status"
}
trap cleanup EXIT

if ! "$VKMT/scripts/vkmt-prefix" verify --prefix "$PREFIX" >"$run_root/prefix-verify.log" 2>&1; then
    cat "$run_root/prefix-verify.log" >&2
    exit 1
fi

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

CRL_PORT="$(free_port)"

generate_material()
{
    cat >"$run_root/ca.ext" <<'EOF'
basicConstraints=critical,CA:TRUE,pathlen:1
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
EOF
    cat >"$run_root/intermediate.ext" <<EOF
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
authorityKeyIdentifier=keyid,issuer
subjectKeyIdentifier=hash
crlDistributionPoints=URI:http://127.0.0.1:${CRL_PORT}/intermediate.crl
EOF
    cat >"$run_root/server.ext" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost
authorityKeyIdentifier=keyid,issuer
crlDistributionPoints=URI:http://127.0.0.1:${CRL_PORT}/intermediate.crl
EOF
    "$OPENSSL_BIN" req -x509 -newkey rsa:2048 -nodes -sha256 -days 3 \
        -keyout "$run_root/root.key" -out "$run_root/root.pem" \
        -subj '/C=US/O=VKMT Test/CN=VKMT Local Root' \
        -addext 'basicConstraints=critical,CA:TRUE,pathlen:1' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign' \
        -addext 'subjectKeyIdentifier=hash' >/dev/null 2>&1 || return 1
    "$OPENSSL_BIN" req -newkey rsa:2048 -nodes -sha256 \
        -keyout "$run_root/intermediate.key" -out "$run_root/intermediate.csr" \
        -subj '/C=US/O=VKMT Test/CN=VKMT Local Intermediate' >/dev/null 2>&1 || return 1
    "$OPENSSL_BIN" x509 -req -sha256 -days 2 -in "$run_root/intermediate.csr" \
        -CA "$run_root/root.pem" -CAkey "$run_root/root.key" -CAcreateserial \
        -out "$run_root/intermediate.pem" -extfile "$run_root/intermediate.ext" >/dev/null 2>&1 || return 1
    : >"$run_root/index.txt"
    printf '1000\n' >"$run_root/crlnumber"
    printf '%s\n' '[ ca ]' 'default_ca = ca_default' '[ ca_default ]' \
        "database = $run_root/index.txt" "crlnumber = $run_root/crlnumber" \
        "private_key = $run_root/intermediate.key" "certificate = $run_root/intermediate.pem" \
        'default_crl_days = 2' 'default_md = sha256' >"$run_root/crl.conf"
    "$OPENSSL_BIN" ca -batch -gencrl -config "$run_root/crl.conf" \
        -out "$run_root/intermediate.crl.pem" >/dev/null 2>&1 || return 1
    "$OPENSSL_BIN" crl -in "$run_root/intermediate.crl.pem" -outform DER \
        -out "$run_root/intermediate.crl" >/dev/null 2>&1 || return 1
    "$OPENSSL_BIN" req -newkey rsa:2048 -nodes -sha256 \
        -keyout "$run_root/valid.key" -out "$run_root/valid.csr" \
        -subj '/C=US/O=VKMT Test/CN=localhost' >/dev/null 2>&1 || return 1
    "$OPENSSL_BIN" x509 -req -sha256 -days 2 -in "$run_root/valid.csr" \
        -CA "$run_root/intermediate.pem" -CAkey "$run_root/intermediate.key" -CAcreateserial \
        -out "$run_root/valid.pem" -extfile "$run_root/server.ext" >/dev/null 2>&1 || return 1
    cat "$run_root/valid.pem" "$run_root/intermediate.pem" "$run_root/root.pem" >"$run_root/valid-chain.pem"

    "$OPENSSL_BIN" req -newkey rsa:2048 -nodes -sha256 \
        -keyout "$run_root/expired.key" -out "$run_root/expired.csr" \
        -subj '/C=US/O=VKMT Test/CN=localhost' >/dev/null 2>&1 || return 1
    "$OPENSSL_BIN" x509 -req -in "$run_root/expired.csr" \
        -CA "$run_root/intermediate.pem" -CAkey "$run_root/intermediate.key" -CAcreateserial \
        -out "$run_root/expired.pem" -not_before 20000101000000Z -not_after 20000102000000Z \
        -extfile "$run_root/server.ext" >/dev/null 2>&1 || return 1
    cat "$run_root/expired.pem" "$run_root/intermediate.pem" "$run_root/root.pem" >"$run_root/expired-chain.pem"

    "$OPENSSL_BIN" req -x509 -newkey rsa:2048 -nodes -sha256 -days 2 \
        -keyout "$run_root/untrusted-root.key" -out "$run_root/untrusted-root.pem" \
        -subj '/C=US/O=VKMT Test/CN=VKMT Untrusted Root' \
        -addext 'basicConstraints=critical,CA:TRUE' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign' >/dev/null 2>&1 || return 1
    "$OPENSSL_BIN" req -newkey rsa:2048 -nodes -sha256 \
        -keyout "$run_root/untrusted.key" -out "$run_root/untrusted.csr" \
        -subj '/C=US/O=VKMT Test/CN=localhost' >/dev/null 2>&1 || return 1
    "$OPENSSL_BIN" x509 -req -sha256 -days 2 -in "$run_root/untrusted.csr" \
        -CA "$run_root/untrusted-root.pem" -CAkey "$run_root/untrusted-root.key" -CAcreateserial \
        -out "$run_root/untrusted.pem" -extfile "$run_root/server.ext" >/dev/null 2>&1 || return 1
    "$OPENSSL_BIN" x509 -in "$run_root/root.pem" -outform DER -out "$run_root/root.der" || return 1
}

generate_material || { echo "failed to generate local TLS chain" >&2; exit 1; }

server_pid=""
crl_pid=""
proxy_pid=""
start_server()
{
    port=$1; cert=$2; key=$3; log=$4
    chain_args=()
    case "$cert" in
        */valid.pem|*/expired.pem) chain_args=(-cert_chain "$run_root/intermediate.pem");;
        */untrusted.pem) chain_args=(-cert_chain "$run_root/untrusted-root.pem");;
    esac
    "$OPENSSL_BIN" s_server -accept "$port" -cert "$cert" -key "$key" \
        "${chain_args[@]}" -www -quiet -naccept 8 >"$log" 2>&1 &
    server_pid=$!
    i=0
    while test "$i" -lt 50; do
        if ! kill -0 "$server_pid" 2>/dev/null; then return 1; fi
        nc -z 127.0.0.1 "$port" >/dev/null 2>&1 && return 0
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

stop_server()
{
    if test -n "$server_pid"; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
        server_pid=""
    fi
}

stop_proxy()
{
    if test -n "$proxy_pid"; then
        kill "$proxy_pid" 2>/dev/null || true
        wait "$proxy_pid" 2>/dev/null || true
        proxy_pid=""
    fi
}

python3 -m http.server "$CRL_PORT" --bind 127.0.0.1 --directory "$run_root" \
    >"$run_root/crl-server.log" 2>&1 &
crl_pid=$!
if ! nc -z 127.0.0.1 "$CRL_PORT" >/dev/null 2>&1; then
    sleep 0.5
fi

common=(-std=c11 -O2 -Wall -Wextra -Werror -I"$TOOL/../generic-w64-mingw32/include")
for spec in \
    'arm64:aarch64-w64-mingw32-clang:-ffixed-x18 -ffixed-x28' \
    'arm64ec:arm64ec-w64-mingw32-clang:-ffixed-x18 -ffixed-x28' \
    'x86_64:x86_64-w64-mingw32-clang:' \
    'i386:i686-w64-mingw32-clang:'; do
    IFS=: read -r arch compiler extra <<EOF
$spec
EOF
    # shellcheck disable=SC2086
    if ! "$TOOL/$compiler" "${common[@]}" $extra \
        -o "$run_root/tls_trust_${arch}.exe" "$VKMT/test/tls_trust_contract.c" \
        -lwinhttp -lwininet -lcrypt32 >"$run_root/compile-$arch.log" 2>&1; then
        cat "$run_root/compile-$arch.log" >&2
        exit 1
    fi
done

env WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG="$WINEDEBUG_VALUE" \
    FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
    timeout --signal=TERM --kill-after=5s "$TIMEOUT" "$WINE" \
    "Z:$run_root/tls_trust_arm64.exe" install "Z:$run_root/root.der" \
    "Z:$run_root/intermediate.crl" >"$run_root/root-install.log" 2>&1
if test "$?" -ne 0 || ! grep -q '^TLS_ROOT_INSTALL_OK' "$run_root/root-install.log"; then
    cat "$run_root/root-install.log" >&2
    overall=1
fi

run_case()
{
    arch=$1; mode=$2; cert=$3; key=$4; fragmented=${5:-0}
    port="$(free_port)"
    server_log="$run_root/server-${arch}-${mode}.log"
    client_log="$run_root/${arch}-${mode}.log"
    if ! start_server "$port" "$cert" "$key" "$server_log"; then
        echo "failed to start TLS server for $arch/$mode" >&2
        stop_server
        overall=1
        return
    fi
    proxy_arg=()
    if test "$fragmented" = 1; then
        proxy_port="$(free_port)"
        node "$VKMT/test/browser/tls_connect_delay_proxy.mjs" "$proxy_port" 127.0.0.1 "$port" 2 32 \
            >"$run_root/proxy-${arch}-${mode}.log" 2>&1 &
        proxy_pid=$!
        proxy_ready=0
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
            if grep -q VKMT_TLS_CONNECT_PROXY_READY "$run_root/proxy-${arch}-${mode}.log" 2>/dev/null; then
                proxy_ready=1
                break
            fi
            sleep 0.1
        done
        if test "$proxy_ready" != 1; then
            echo "TLS CONNECT proxy failed for $arch/$mode" >&2
            stop_proxy
            stop_server
            overall=1
            return
        fi
        proxy_arg=("proxy=$proxy_port")
    fi
    client_args=("Z:$run_root/tls_trust_${arch}.exe" "$mode" "$port" \
        "Z:$run_root/root.der" "Z:$run_root/intermediate.crl")
    if test "$mode" = valid; then client_args+=(preinstalled); fi
    if test "$mode" = valid-fragmented; then client_args+=(preinstalled); fi
    if test "$fragmented" = 1; then client_args+=("proxy=$proxy_port"); fi
    env WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
        WINE_NO_EXPLORER=1 WINEDEBUG="$WINEDEBUG_VALUE" \
        FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
        timeout --signal=TERM --kill-after=5s "$TIMEOUT" "$WINE" \
        "${client_args[@]}" \
        >"$client_log" 2>&1
    code=$?
    stop_proxy
    stop_server
    if test "$code" -ne 0; then overall=1; fi
}

for arch in $ARCHES; do
    run_case "$arch" valid "$run_root/valid.pem" "$run_root/valid.key"
    run_case "$arch" valid-fragmented "$run_root/valid.pem" "$run_root/valid.key" 1
    run_case "$arch" expired "$run_root/expired.pem" "$run_root/expired.key"
    run_case "$arch" untrusted "$run_root/untrusted.pem" "$run_root/untrusted.key"
done

env WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG=-all \
    FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
    timeout --signal=TERM --kill-after=5s 15s "$WINE" \
    "Z:$run_root/tls_trust_arm64.exe" remove "Z:$run_root/root.der" \
    "Z:$run_root/intermediate.crl" >"$run_root/root-remove.log" 2>&1
if test "$?" -ne 0 || ! grep -q '^TLS_ROOT_REMOVE_OK' "$run_root/root-remove.log"; then
    cat "$run_root/root-remove.log" >&2
    overall=1
fi

{
    printf 'arch\tapi\tstatus\terror\tdetail\n'
    for log in "$run_root"/*.log; do
        test -f "$log" || continue
        grep '^TLS_CAP' "$log" | tr -d '\r' | cut -f2- || true
    done
    for arch in $ARCHES; do
        for mode in valid valid-fragmented expired untrusted; do
            log="$run_root/$arch-$mode.log"
            if test -f "$log" && ! grep -q '^TLS_TRUST_CONTRACT_OK' "$log"; then
                if grep -q 'EXCEPTION_ILLEGAL_INSTRUCTION\|c000001d' "$log" 2>/dev/null; then
                    printf '%s\tloader/FEX\tBLOCKED\t0xc000001d\tguest process failed before TLS output\n' "$arch"
                elif grep -q 'TLS_TRUST_CONTRACT_FAIL' "$log" 2>/dev/null; then
                    printf '%s\t%s\tFAIL\t0x00000001\tfixture reported failure\n' "$arch" "$mode"
                else
                    printf '%s\t%s\tEXECUTION\t0x00000001\tno contract marker (rc or timeout)\n' "$arch" "$mode"
                fi
            fi
        done
    done
} >"$EVIDENCE/capability.tsv"

{
    printf '# TLS trust contract — P8\n\n'
    printf 'Prefix: `%s`\n\n' "$PREFIX"
    if test "$overall" = 0; then
        printf '**Result:** all requested architecture/mode processes completed with rc=0.\n\n'
    else
        printf '**Result:** one or more architecture/mode lanes failed or were blocked; see the capability table.\n\n'
    fi
    printf '## Capability table\n\n| Architecture | API | Status | Error | Detail |\n|---|---|---|---|---|\n'
    awk -F '\t' 'NR > 1 { printf "| %s | %s | %s | %s | %s |\n", $1,$2,$3,$4,$5 }' "$EVIDENCE/capability.tsv"
    printf '\n## Contract\n\n'
    printf '%s\n' \
      '- `valid`: a localhost SAN certificate signed by an intermediate whose root is installed only in the current-user ROOT store.' \
      '- `expired`: the same hostname/chain shape with an expired leaf; it must be rejected.' \
      '- `untrusted`: a valid-shape leaf signed by a different root that is not installed; it must be rejected.' \
      '- Both WinHTTP and WinINet use normal certificate validation; no ignore-errors option is set.' \
      '- `valid-fragmented` repeats the trusted case through a local HTTP CONNECT proxy that fragments both directions (2 ms / 32-byte chunks), proving partial TLS transport handling and proxy configuration.' \
      '- Servers, certificate material, and requests are local; external DNS/network is not used.' \
      '- BoringSSL ignore-verification probes remain diagnostic-only and are not counted here.'
    printf '\nEnvironment: FEX_TSOENABLED=0, FEX_VECTORTSOENABLED=0, FEX_MEMCPYSETTSOENABLED=0, wineboot=not-run.\n'
} >"$EVIDENCE/RESULTS.md"

if test "$overall" = 0; then
    echo TLS_TRUST_CONTRACT_ALL_ARCHITECTURES_OK
else
    echo TLS_TRUST_CONTRACT_GAPS >&2
fi
exit "$overall"
