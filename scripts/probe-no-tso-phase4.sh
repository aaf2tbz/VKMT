#!/bin/bash
# Phase 4 asynchronous networking gate. Hardware/FEX TSO stays disabled.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
SOURCE="$VKMT/test/no_tso_phase4_network.c"
XTAJIT64_BOOTSTRAP="$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll"
XTAJIT_BOOTSTRAP="$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"

export VKMT_XTAJIT64_SOURCE="${VKMT_XTAJIT64_SOURCE:-$VKMT/build/no-tso-phase2/providers/xtajit64-no-tso-final-v15.dll}"
export VKMT_XTAJIT64_SHA256="${VKMT_XTAJIT64_SHA256:-a0a586eb6687dd45bdb4818e44c64294f4cfed89dc5b5bafd806c3d402100513}"
export VKMT_XTAJIT_SOURCE="${VKMT_XTAJIT_SOURCE:-$VKMT/build/no-tso-phase2/providers/xtajit-no-tso-final-v15.dll}"
export VKMT_XTAJIT_SHA256="${VKMT_XTAJIT_SHA256:-67192836cb4eb15cb51ef5487a4ec30a3fa210bfac370e3193ede3760a4e4273}"
export FEX_TSOENABLED=0
export FEX_VECTORTSOENABLED=0
export FEX_MEMCPYSETTSOENABLED=0
export VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY=0

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$SOURCE" \
    "$VKMT_XTAJIT_SOURCE" "$VKMT_XTAJIT64_SOURCE"; do
  test -e "$required" || { echo "Missing Phase 4 input: $required" >&2; exit 1; }
done

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/no-tso-phase4.XXXXXX")"
prefix="$run_root/prefix"
bootstrap_staged=0
wine_pid=""

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
  if test -n "${VKMT_PHASE4_EVIDENCE_DIR:-}"; then
    case "$VKMT_PHASE4_EVIDENCE_DIR" in
      "$VKMT"/*)
        mkdir -p "$VKMT_PHASE4_EVIDENCE_DIR"
        find "$run_root" -maxdepth 1 -type f \
          \( -name '*.log' -o -name '*.txt' -o -name '*.sha256' \) \
          -exec cp {} "$VKMT_PHASE4_EVIDENCE_DIR"/ \;
        printf 'status=%s\n' "$status" >"$VKMT_PHASE4_EVIDENCE_DIR/status.txt"
        ;;
      *) echo "Refusing non-VKMT evidence directory: $VKMT_PHASE4_EVIDENCE_DIR" >&2 ;;
    esac
  fi
  case "$run_root" in
    "$RUNS"/no-tso-phase4.*) find "$run_root" -depth -delete 2>/dev/null || true ;;
  esac
  exit "$status"
}
trap cleanup EXIT

run_wine()
{
  output=$1
  shift
  env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_PHASE4_WINEDEBUG:--all}" \
    "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then code=0; else code=$?; fi
  wine_pid=""
  return "$code"
}

"$TOOL/x86_64-w64-mingw32-clang" -std=c11 -O2 -Wall -Wextra -Werror \
  "$SOURCE" -o "$run_root/phase4_x64.exe" -lwinhttp -lws2_32
"$TOOL/i686-w64-mingw32-clang" -std=c11 -O2 -Wall -Wextra -Werror \
  "$SOURCE" -o "$run_root/phase4_i386.exe" -lwinhttp -lws2_32
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
while IFS= read -r dll; do
  install -m 0644 "$dll" "$syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine "$run_root/wineboot.log" "$WINEBOOT" --init
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

package_url='https://client-update.steamstatic.com/steamui_websrc_all.zip.vz.eafcb4aedb55ba1695abbdf9e0df6354a2ea1a92_26734899'
/usr/bin/curl --fail --silent --show-error --location --range 0-4194303 \
  --output "$run_root/native-reference.bin" "$package_url"
native_hash="$(shasum -a 256 "$run_root/native-reference.bin" | awk '{print $1}')"
test "$(stat -f %z "$run_root/native-reference.bin")" = 4194304
printf 'url=%s\nbytes=4194304\nnative_sha256=%s\n' "$package_url" "$native_hash" \
  >"$run_root/cdn-reference.txt"

for arch in x64 i386; do
  output_directory="$run_root/output-$arch"
  mkdir -p "$output_directory"
  run_wine "$run_root/$arch-network.log" "$run_root/phase4_$arch.exe" \
    "Z:$output_directory"
  grep -q 'NO_TSO_PHASE4_ASYNC_CDN_OK downloads=8 bytes_each=4194304' \
    "$run_root/$arch-network.log"
  grep -q 'NO_TSO_PHASE4_IOCP_PEER_CLOSE_OK' "$run_root/$arch-network.log"
  : >"$run_root/$arch-output.sha256"
  for slot in "$output_directory"/slot-*.bin; do
    test "$(stat -f %z "$slot")" = 4194304
    hash="$(shasum -a 256 "$slot" | awk '{print $1}')"
    test "$hash" = "$native_hash"
    printf '%s  %s\n' "$hash" "$(basename "$slot")" >>"$run_root/$arch-output.sha256"
  done
  test "$(wc -l <"$run_root/$arch-output.sha256" | tr -d ' ')" = 8
  echo "NO_TSO_PHASE4_$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')_ASYNC_CDN_OK"
done

cat >"$run_root/summary.txt" <<EOF
NO_TSO_PHASE4_ASYNC_NETWORK_OK
FEX_TSOENABLED=0
FEX_VECTORTSOENABLED=0
FEX_MEMCPYSETTSOENABLED=0
x64_downloads=8/8
i386_downloads=8/8
bytes_each=4194304
native_sha256=$native_hash
EOF
cat "$run_root/summary.txt"
