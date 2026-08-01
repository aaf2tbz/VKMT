#!/bin/bash
# Prove the i386 Java candidate uses software TSO lowering in generated ARM64.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM_MINGW="${LLVM_MINGW:-$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
WINE_BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
CANDIDATE="${VKMT_XTAJIT_SOURCE:-$VKMT/build/fex-wow64-java-final/provider/xtajit.dll}"
CANDIDATE_SHA="${VKMT_XTAJIT_SHA256:-}"
FEX_SOURCE="${VKMT_FEX_SOURCE:-$VKMT/third_party/FEX-2607-java-baseline}"
GOLDEN="$VKMT/wine/wine-11.12/runtime-providers/xtajit-arm64-known-good.dll"
GOLDEN_SHA="$(shasum -a 256 "$GOLDEN" | awk '{print $1}')"
RUNS_DIR="$VKMT/build/probe-runs"
EVIDENCE="$VKMT/docs/validation/windows-java-j0-20260729"

test -f "$CANDIDATE"
test -x "$WINE_BUILD/wine"
test -x "$WINE_BUILD/server/wineserver"
test -f "$GOLDEN"
printf '%s  %s\n' "$GOLDEN_SHA" "$GOLDEN" | shasum -a 256 -c -
if test -z "$CANDIDATE_SHA"; then
  CANDIDATE_SHA="$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')"
fi
printf '%s  %s\n' "$CANDIDATE_SHA" "$CANDIDATE" | shasum -a 256 -c -

mkdir -p "$RUNS_DIR"
run_root="$(mktemp -d "$RUNS_DIR/windows-java.j0-tso.XXXXXX")"
prefix="$run_root/prefix"
fixture="$run_root/java_tso_preflight.exe"
marker="$run_root/java-tso.marker"
bootstrap_log="$run_root/wineboot.log"
disassembly_log="$run_root/tso-disassembly.log"
jit_trace="$run_root/fex-jit.log"
jit_raw="$run_root/fex-jit.raw"
jit_object="$run_root/fex-jit.o"
jit_map="$run_root/fex-jit-map.txt"
wine_pid=

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINE_BUILD/server/wineserver" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINE_BUILD/server/wineserver" -w 2>/dev/null || true
  case "$run_root" in
    "$RUNS_DIR"/*)
      if test "${VKMT_KEEP_PROBE_RUN:-0}" = 1; then
        echo "Retained J0 run: $run_root" >&2
      else
        /usr/bin/trash "$run_root" 2>/dev/null || true
      fi
      ;;
  esac
  exit "$status"
}
trap cleanup EXIT

export PATH="$LLVM_MINGW/bin:$PATH"
i686-w64-mingw32-clang -O1 -g -Wall -Wextra \
  -Wl,--stack,0x1000000 \
  "$VKMT/test/i386/java_tso_preflight.c" -o "$fixture"
machine="$(llvm-readobj --file-headers "$fixture" |
  awk '/^[[:space:]]*Machine:/ {print $2; exit}')"
test "$machine" = IMAGE_FILE_MACHINE_I386

system32="$prefix/drive_c/windows/system32"
syswow64="$prefix/drive_c/windows/syswow64"
mkdir -p "$system32" "$syswow64"
install -m 0644 "$WINE_BUILD/dlls/wow64/aarch64-windows/wow64.dll" \
  "$system32/wow64.dll"
install -m 0644 "$WINE_BUILD/dlls/wow64win/aarch64-windows/wow64win.dll" \
  "$system32/wow64win.dll"
while IFS= read -r dll; do
  install -m 0644 "$dll" "$syswow64/$(basename "$dll")"
done < <(find "$WINE_BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print |
  LC_ALL=C sort)

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"

run_wine()
{
  output=$1
  shift
  env WINEPREFIX="$prefix" WINEBUILDDIR="$WINE_BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG=-all "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then result=0; else result=$?; fi
  wine_pid=
  return "$result"
}

run_wine "$bootstrap_log" "$WINE_BUILD/wine" \
  "$WINE_BUILD/programs/wineboot/aarch64-windows/wineboot.exe" --init

# Wineboot refreshes system32 from the canonical build tree. Select the
# candidate only after bootstrap so no setup operation can silently replace it.
VKMT_XTAJIT_SOURCE="$CANDIDATE" VKMT_XTAJIT_SHA256="$CANDIDATE_SHA" \
  "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
VKMT_XTAJIT_SOURCE="$CANDIDATE" VKMT_XTAJIT_SHA256="$CANDIDATE_SHA" \
  "$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

if ! env FEX_TSOENABLED=1 FEX_JITDUMP=1 FEX_SILENTLOG=0 \
  WINEPREFIX="$prefix" WINEBUILDDIR="$WINE_BUILD" WINEBOOTSTRAPMODE=1 \
  WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_JAVA_J0_WINEDEBUG:--all}" \
  "$WINE_BUILD/wine" "$fixture" "Z:$marker" >"$jit_trace" 2>&1; then
  tail -n 120 "$jit_trace" >&2
  exit 1
fi

if test ! -f "$marker" || ! grep -F 'JAVA_TSO_PREFLIGHT_OK' "$marker"; then
  echo "J0 fixture did not create its success marker" >&2
  tail -n 160 "$jit_trace" >&2
  exit 1
fi
test -s "$jit_trace"
"$VKMT/scripts/extract-fex-jit.py" "$jit_trace" "$jit_raw" "$jit_map"
llvm-objcopy -I binary -O elf64-littleaarch64 -B aarch64 \
  "$jit_raw" "$jit_object"
llvm-objdump --arch=aarch64 -D "$jit_object" >"$disassembly_log"
grep -Eiq '\bldar(b|h)?\b' "$disassembly_log"
grep -Eiq '\bstlr(b|h)?\b' "$disassembly_log"
grep -Eiq 'dmb[[:space:]]+ishld' "$disassembly_log"
grep -Eiq 'dmb[[:space:]]+ish([^a-z]|$)' "$disassembly_log"
grep -Eiq '\b(casal|casalh|casalb|ldaxr|ldaxp)\b' "$disassembly_log"
if grep -Eiq '\bldapr(b|h)?\b|\bldapur(b|h)?\b' "$disassembly_log"; then
  echo "Java baseline emitted an RCpc/LDAPR-family TSO load" >&2
  exit 1
fi

if rg -q 'CTX\\.SetHardwareTSOSupport\\(true\\)|FEX::Windows::UnixLib::TryEnableHardwareTSO\\(\\)' \
  "$FEX_SOURCE/Source/Windows/Common/TSOHandlerConfig.h"; then
  echo "Windows provider still enables host hardware TSO" >&2
  exit 1
fi

mkdir -p "$EVIDENCE"
{
  printf 'root_commit=%s\n' "$(git -C "$VKMT" rev-parse HEAD)"
  printf 'wine_commit=%s\n' "$(git -C "$VKMT/wine/wine-11.12" rev-parse HEAD)"
  printf 'fex_source=%s\n' "$FEX_SOURCE"
  printf 'fex_memoryops_sha256=%s\n' \
    "$(shasum -a 256 "$FEX_SOURCE/FEXCore/Source/Interface/Core/JIT/MemoryOps.cpp" | awk '{print $1}')"
  printf 'fex_tso_config_sha256=%s\n' \
    "$(shasum -a 256 "$FEX_SOURCE/Source/Windows/Common/TSOHandlerConfig.h" | awk '{print $1}')"
  printf 'golden_sha256=%s\n' "$GOLDEN_SHA"
  printf 'candidate_sha256=%s\n' "$CANDIDATE_SHA"
  printf 'fixture_machine=%s\n' "$machine"
  cat "$marker"
  printf 'software_tso=1\n'
  printf 'hardware_tso=0\n'
} >"$EVIDENCE/RESULTS.txt"
rg -i -m 80 'ldar|stlr|dmb[[:space:]]+ish|casal|ldaxr|ldaxp' \
  "$disassembly_log" >"$EVIDENCE/tso-disassembly-excerpt.txt"
install -m 0644 "$jit_map" "$EVIDENCE/fex-jit-map.txt"

# The candidate run must not alter either accepted provider.
printf '%s  %s\n' "$GOLDEN_SHA" "$GOLDEN" | shasum -a 256 -c -
printf '%s  %s\n' "$GOLDEN_SHA" \
  "$WINE_BUILD/dlls/xtajit/aarch64-windows/xtajit.dll" | shasum -a 256 -c -

echo "VKMT_WINDOWS_JAVA_J0_TSO_OK $CANDIDATE_SHA"
