#!/bin/bash
# Phase 1: deterministic x86_64/i386 ordering, wait, lifecycle, child, and CDN fixtures.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
WOW64="$BUILD/dlls/wow64/aarch64-windows/wow64.dll"
WOW64WIN="$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll"
SOURCE_SYNC="$VKMT/test/no_tso_phase1_sync.c"
SOURCE_CDN="$VKMT/test/no_tso_phase1_cdn.c"
XTAJIT64_BOOTSTRAP="$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll"
XTAJIT_BOOTSTRAP="$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"

DEFAULT_CANDIDATES="$VKMT/docs/validation/no-tso-phase0-20260731T013101Z/candidates"
export VKMT_XTAJIT_SOURCE="${VKMT_XTAJIT_SOURCE:-$DEFAULT_CANDIDATES/xtajit-authoritative-v12.dll}"
export VKMT_XTAJIT_SHA256="${VKMT_XTAJIT_SHA256:-b2a24e4585b44119b1d8ff9a8907987036ab8ed7992d6dcb148600fbaba4422e}"
export VKMT_XTAJIT64_SOURCE="${VKMT_XTAJIT64_SOURCE:-$DEFAULT_CANDIDATES/xtajit64-authoritative-v12.dll}"
export VKMT_XTAJIT64_SHA256="${VKMT_XTAJIT64_SHA256:-455730fec28029be1c646147214f164164726f1ee5b542f2f69b409b11a07c86}"

# The accepted Phase 1 lane never enables any FEX TSO mode.
export FEX_TSOENABLED=0
export FEX_VECTORTSOENABLED=0
export FEX_MEMCPYSETTSOENABLED=0
export VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY=0

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$WOW64" "$WOW64WIN" \
    "$SOURCE_SYNC" "$SOURCE_CDN" "$VKMT_XTAJIT_SOURCE" "$VKMT_XTAJIT64_SOURCE"; do
  test -e "$required" || { echo "Missing Phase 1 input: $required" >&2; exit 1; }
done

for macho in "$WINE" "$WINESERVER" "$BUILD/dlls/ntdll/ntdll.so"; do
  test "$(/usr/bin/lipo -archs "$macho")" = arm64 || {
    echo "Non-ARM64 host artifact: $macho" >&2
    exit 1
  }
done
if translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null)"; then
  test "$translated" = 0 || { echo "Phase 1 runner is under Rosetta" >&2; exit 1; }
fi

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/no-tso-phase1.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=""
bootstrap_staged=0
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_PHASE1_TIMEOUT:-240}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_PHASE1_TIMEOUT:-240}s")
fi

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  if test "$bootstrap_staged" = 1; then
    if ! install -m 0644 "$run_root/xtajit64.bootstrap.before.dll" "$XTAJIT64_BOOTSTRAP" ||
       ! install -m 0644 "$run_root/xtajit.bootstrap.before.dll" "$XTAJIT_BOOTSTRAP" ||
       ! cmp -s "$run_root/xtajit64.bootstrap.before.dll" "$XTAJIT64_BOOTSTRAP" ||
       ! cmp -s "$run_root/xtajit.bootstrap.before.dll" "$XTAJIT_BOOTSTRAP"; then
      echo "Failed to restore bootstrap CPU providers" >&2
      status=1
    fi
  fi
  if test -n "${VKMT_PHASE1_EVIDENCE_DIR:-}"; then
    case "$VKMT_PHASE1_EVIDENCE_DIR" in
      "$VKMT"/*)
        mkdir -p "$VKMT_PHASE1_EVIDENCE_DIR"
        find "$run_root" -maxdepth 1 -type f \
          \( -name '*.log' -o -name '*.txt' -o -name '*.sha256' \) \
          -exec cp {} "$VKMT_PHASE1_EVIDENCE_DIR"/ \;
        printf 'status=%s\n' "$status" >"$VKMT_PHASE1_EVIDENCE_DIR/status.txt"
        ;;
      *) echo "Refusing non-VKMT evidence directory: $VKMT_PHASE1_EVIDENCE_DIR" >&2 ;;
    esac
  fi
  case "$run_root" in
    "$RUNS"/no-tso-phase1.*)
      if test "${VKMT_KEEP_PHASE1_RUN:-0}" = 1; then
        echo "Retained disposable Phase 1 run: $run_root" >&2
      else
        find "$run_root" -depth -delete 2>/dev/null || true
      fi
      ;;
  esac
  exit "$status"
}
trap cleanup EXIT

run_wine()
{
  output=$1
  shift
  "${timeout_cmd[@]}" env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" \
    WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 \
    WINEDEBUG="${VKMT_PHASE1_WINEDEBUG:--all}" \
    "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then code=0; else code=$?; fi
  wine_pid=""
  return "$code"
}

"$TOOL/i686-w64-mingw32-clang" -std=c11 -O2 -Wall -Wextra -Werror \
  -o "$run_root/no_tso_phase1_i386.exe" "$SOURCE_SYNC"
"$TOOL/x86_64-w64-mingw32-clang" -std=c11 -O2 -Wall -Wextra -Werror \
  -o "$run_root/no_tso_phase1_x64.exe" "$SOURCE_SYNC"
"$TOOL/i686-w64-mingw32-clang" -std=c11 -O2 -Wall -Wextra -Werror \
  -o "$run_root/no_tso_phase1_cdn_i386.exe" "$SOURCE_CDN" -lwinhttp
"$TOOL/x86_64-w64-mingw32-clang" -std=c11 -O2 -Wall -Wextra -Werror \
  -o "$run_root/no_tso_phase1_cdn_x64.exe" "$SOURCE_CDN" -lwinhttp

for spec in \
    "no_tso_phase1_i386.exe:IMAGE_FILE_MACHINE_I386" \
    "no_tso_phase1_x64.exe:IMAGE_FILE_MACHINE_AMD64" \
    "no_tso_phase1_cdn_i386.exe:IMAGE_FILE_MACHINE_I386" \
    "no_tso_phase1_cdn_x64.exe:IMAGE_FILE_MACHINE_AMD64"; do
  fixture=${spec%%:*}
  expected=${spec#*:}
  machine="$("$TOOL/llvm-readobj" --file-headers "$run_root/$fixture" |
    awk '/Machine:/ {print $2; exit}')"
  test "$machine" = "$expected" || {
    echo "Wrong Phase 1 fixture architecture: $fixture ($machine)" >&2
    exit 1
  }
done

shasum -a 256 "$run_root"/*.exe >"$run_root/fixtures.sha256"

# Wine loads the x64 CPU provider from WINEBUILDDIR before the prefix copy is
# available. Test the selected providers at that real bootstrap boundary and
# restore the exact prior bytes during cleanup.
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
install -m 0644 "$WOW64" "$system32/wow64.dll"
install -m 0644 "$WOW64WIN" "$system32/wow64win.dll"
while IFS= read -r dll; do
  install -m 0644 "$dll" "$syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine "$run_root/wineboot.log" "$WINEBOOT" --init || {
  echo "Phase 1 wineboot failed" >&2
  tail -n 120 "$run_root/wineboot.log" >&2
  exit 1
}
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

run_case()
{
  arch=$1
  test_name=$2
  executable="$run_root/no_tso_phase1_${arch}.exe"
  log="$run_root/${arch}-${test_name}.log"
  run_wine "$log" "$executable" --test "$test_name" || {
    echo "Phase 1 $arch $test_name failed" >&2
    tail -n 120 "$log" >&2
    exit 1
  }
  grep -q 'NO_TSO_.*_OK' "$log" || {
    echo "Phase 1 $arch $test_name emitted no success marker" >&2
    tail -n 120 "$log" >&2
    exit 1
  }
  arch_tag="$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')"
  test_tag="$(printf '%s' "$test_name" | tr '[:lower:]' '[:upper:]')"
  echo "NO_TSO_PHASE1_${arch_tag}_${test_tag}_OK"
}

if test "${VKMT_PHASE1_DIAGNOSTIC:-0}" != 1; then
  for arch in x64 i386; do
    for test_name in ordering wait condition apc threads children; do
      run_case "$arch" "$test_name"
    done
  done
fi

package_url='https://client-update.steamstatic.com/steamui_websrc_all.zip.vz.eafcb4aedb55ba1695abbdf9e0df6354a2ea1a92_26734899'
/usr/bin/curl --fail --silent --show-error --location --range 0-4194303 \
  --output "$run_root/native-reference.bin" "$package_url"
test "$(stat -f %z "$run_root/native-reference.bin")" = 4194304
native_hash="$(shasum -a 256 "$run_root/native-reference.bin" | awk '{print $1}')"
printf 'url=%s\nbytes=4194304\nnative_sha256=%s\n' "$package_url" "$native_hash" \
  >"$run_root/cdn-reference.txt"

cdn_arches="${VKMT_PHASE1_CDN_ARCHES:-x64 i386}"
cdn_count="${VKMT_PHASE1_CDN_COUNT:-8}"
case "$cdn_count" in
  1|2|3|4|5|6|7|8) ;;
  *) echo "VKMT_PHASE1_CDN_COUNT must be 1..8" >&2; exit 2 ;;
esac
for arch in $cdn_arches; do
  output_directory="$run_root/cdn-$arch"
  mkdir -p "$output_directory"
  windows_output="Z:${output_directory}"
  run_wine "$run_root/${arch}-cdn.log" "$run_root/no_tso_phase1_cdn_${arch}.exe" \
    "$windows_output" "$cdn_count" || {
    echo "Phase 1 $arch CDN fixture failed" >&2
    tail -n 160 "$run_root/${arch}-cdn.log" >&2
    exit 1
  }
  aggregate=$((cdn_count * 4194304))
  grep -q "NO_TSO_CDN_OK downloads=$cdn_count bytes_each=4194304 aggregate=$aggregate" \
    "$run_root/${arch}-cdn.log"
  : >"$run_root/${arch}-cdn.sha256"
  for slot in "$output_directory"/slot-*.bin; do
    test "$(stat -f %z "$slot")" = 4194304
    hash="$(shasum -a 256 "$slot" | awk '{print $1}')"
    test "$hash" = "$native_hash" || {
      echo "Phase 1 $arch CDN hash mismatch: $slot" >&2
      exit 1
    }
    printf '%s  %s\n' "$hash" "$(basename "$slot")" >>"$run_root/${arch}-cdn.sha256"
  done
  test "$(wc -l <"$run_root/${arch}-cdn.sha256" | tr -d ' ')" = "$cdn_count"
  arch_tag="$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')"
  echo "NO_TSO_PHASE1_${arch_tag}_CDN_OK"
done

if test "${VKMT_PHASE1_DIAGNOSTIC:-0}" = 1; then
  printf 'NO_TSO_PHASE1_DIAGNOSTIC_DONE\ncdn_arches=%s\ncdn_count=%s\n' \
    "$cdn_arches" "$cdn_count" >"$run_root/summary.txt"
  cat "$run_root/summary.txt"
  exit 0
fi

cat >"$run_root/summary.txt" <<EOF
NO_TSO_PHASE1_ALL_OK
FEX_TSOENABLED=0
FEX_VECTORTSOENABLED=0
FEX_MEMCPYSETTSOENABLED=0
x64_children=128/128
i386_children=128/128
x64_cdn=8/8
i386_cdn=8/8
cdn_bytes_each=4194304
cdn_native_sha256=$native_hash
EOF
cat "$run_root/summary.txt"
