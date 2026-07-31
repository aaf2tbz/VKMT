#!/bin/bash
# Phase 2 x86 memory-model litmus gates. All FEX TSO settings stay disabled.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
SOURCE="$VKMT/test/no_tso_phase2_litmus.c"
DEFAULT_CANDIDATES="$VKMT/docs/validation/no-tso-phase0-20260731T013101Z/candidates"
XTAJIT64_BOOTSTRAP="$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll"
XTAJIT_BOOTSTRAP="$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"

export VKMT_XTAJIT_SOURCE="${VKMT_XTAJIT_SOURCE:-$DEFAULT_CANDIDATES/xtajit-authoritative-v12.dll}"
export VKMT_XTAJIT_SHA256="${VKMT_XTAJIT_SHA256:-b2a24e4585b44119b1d8ff9a8907987036ab8ed7992d6dcb148600fbaba4422e}"
export VKMT_XTAJIT64_SOURCE="${VKMT_XTAJIT64_SOURCE:-$DEFAULT_CANDIDATES/xtajit64-authoritative-v12.dll}"
export VKMT_XTAJIT64_SHA256="${VKMT_XTAJIT64_SHA256:-455730fec28029be1c646147214f164164726f1ee5b542f2f69b409b11a07c86}"
export FEX_TSOENABLED=0
export FEX_VECTORTSOENABLED=0
export FEX_MEMCPYSETTSOENABLED=0
export VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY=0

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$SOURCE" \
    "$VKMT_XTAJIT_SOURCE" "$VKMT_XTAJIT64_SOURCE"; do
  test -e "$required" || { echo "Missing Phase 2 input: $required" >&2; exit 1; }
done
for macho in "$WINE" "$WINESERVER" "$BUILD/dlls/ntdll/ntdll.so"; do
  test "$(/usr/bin/lipo -archs "$macho")" = arm64 || {
    echo "Non-ARM64 host artifact: $macho" >&2
    exit 1
  }
done
if translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null)"; then
  test "$translated" = 0 || { echo "Phase 2 runner is under Rosetta" >&2; exit 1; }
fi

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/no-tso-phase2.XXXXXX")"
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
    if ! install -m 0644 "$run_root/xtajit64.bootstrap.before.dll" "$XTAJIT64_BOOTSTRAP" ||
       ! install -m 0644 "$run_root/xtajit.bootstrap.before.dll" "$XTAJIT_BOOTSTRAP" ||
       ! cmp -s "$run_root/xtajit64.bootstrap.before.dll" "$XTAJIT64_BOOTSTRAP" ||
       ! cmp -s "$run_root/xtajit.bootstrap.before.dll" "$XTAJIT_BOOTSTRAP"; then
      echo "Failed to restore bootstrap CPU providers" >&2
      status=1
    fi
  fi
  if test -n "${VKMT_PHASE2_EVIDENCE_DIR:-}"; then
    case "$VKMT_PHASE2_EVIDENCE_DIR" in
      "$VKMT"/*)
        mkdir -p "$VKMT_PHASE2_EVIDENCE_DIR"
        find "$run_root" -maxdepth 1 -type f \
          \( -name '*.log' -o -name '*.txt' -o -name '*.sha256' \) \
          -exec cp {} "$VKMT_PHASE2_EVIDENCE_DIR"/ \;
        printf 'status=%s\n' "$status" >"$VKMT_PHASE2_EVIDENCE_DIR/status.txt"
        ;;
      *) echo "Refusing non-VKMT evidence directory: $VKMT_PHASE2_EVIDENCE_DIR" >&2 ;;
    esac
  fi
  case "$run_root" in
    "$RUNS"/no-tso-phase2.*) find "$run_root" -depth -delete 2>/dev/null || true ;;
  esac
  exit "$status"
}
trap cleanup EXIT

run_wine()
{
  output=$1
  shift
  env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_PHASE2_WINEDEBUG:--all}" \
    "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then code=0; else code=$?; fi
  wine_pid=""
  return "$code"
}

for arch in i386 x64; do
  case "$arch" in
    i386) compiler="$TOOL/i686-w64-mingw32-clang" ;;
    x64) compiler="$TOOL/x86_64-w64-mingw32-clang" ;;
  esac
  "$compiler" -std=c11 -O2 -Wall -Wextra -Werror \
    -o "$run_root/no_tso_phase2_${arch}.exe" "$SOURCE"
done
shasum -a 256 "$run_root"/*.exe >"$run_root/fixtures.sha256"

# The x64 bootstrap loads its CPU provider from WINEBUILDDIR before the
# prefix copy is usable. Stage candidates there only for this disposable run,
# then restore the exact prior bytes in cleanup. Without this, a prefix can
# verify a candidate while the process silently executes the old provider.
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

rounds="${VKMT_PHASE2_ROUNDS:-1000000}"
arches="${VKMT_PHASE2_ARCHES:-x64 i386}"
for arch in $arches; do
  case "$arch" in x64|i386) ;; *) echo "Invalid Phase 2 architecture: $arch" >&2; exit 2 ;; esac
  log="$run_root/${arch}-store-buffering.log"
  run_wine "$log" "$run_root/no_tso_phase2_${arch}.exe" "$rounds" || {
    echo "Phase 2 $arch store-buffering gate failed" >&2
    tail -n 80 "$log" >&2
    exit 1
  }
  grep -q "NO_TSO_PHASE2_STORE_BUFFERING_OK rounds=$rounds forbidden=0" "$log"
  echo "NO_TSO_PHASE2_$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')_STORE_BUFFERING_OK"
done

cat >"$run_root/summary.txt" <<EOF
NO_TSO_PHASE2_LITMUS_OK
FEX_TSOENABLED=0
FEX_VECTORTSOENABLED=0
FEX_MEMCPYSETTSOENABLED=0
rounds=$rounds
arches=$arches
EOF
cat "$run_root/summary.txt"
