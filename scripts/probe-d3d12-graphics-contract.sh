#!/bin/bash
# D3D12 graphics contract in the canonical prepared prefix.  No prefix
# creation or wineboot is performed; matched PE providers are swapped per lane
# and restored on exit.
set -uo pipefail
VKMT="$(cd "$(dirname "$0")/.." && pwd -P)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
WINE="$BUILD/wine"; SERVER="$BUILD/server/wineserver"
PREFIX="${VKMT_D3D12_GRAPHICS_PREFIX:-$VKMT/build/probe-runs/phase-a-graphics-prefix}"
EVIDENCE="${VKMT_D3D12_GRAPHICS_EVIDENCE_DIR:-$VKMT/docs/validation/d3d12-graphics-contract-p8-20260803}"
DXVK_ROOT="$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b"
VKD3D_ROOT="$VKMT/third_party/vkd3d-proton"
VKD3D_ARM64_BIN="${VKMT_D3D12_ARM64_VKD3D_BIN:-$VKD3D_ROOT/install-arm64/bin}"
RUNS="$VKMT/build/probe-runs"; run_root=""; overall=0
names=(); codes=()
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then timeout_cmd=(gtimeout --signal=TERM --kill-after=5s "${VKMT_D3D12_GRAPHICS_TIMEOUT:-45}s")
elif command -v timeout >/dev/null 2>&1; then timeout_cmd=(timeout --signal=TERM --kill-after=5s "${VKMT_D3D12_GRAPHICS_TIMEOUT:-45}s"); fi

test -x "$WINE" && test -x "$SERVER" && test -d "$PREFIX/.vkmt" || { echo 'missing Wine/server/receipt-backed prefix' >&2; exit 1; }
mkdir -p "$RUNS" "$EVIDENCE"; run_root="$(mktemp -d "$RUNS/d3d12-graphics-contract-p8.XXXXXX")"
system32="$PREFIX/drive_c/windows/system32"; syswow64="$PREFIX/drive_c/windows/syswow64"
cleanup() {
  status=$?; WINEPREFIX="$PREFIX" "$SERVER" -k >/dev/null 2>&1 || true; WINEPREFIX="$PREFIX" "$SERVER" -w >/dev/null 2>&1 || true
  for dir in system32 syswow64; do for base in d3d11.dll dxgi.dll d3d12.dll d3d12core.dll; do
    test -f "$run_root/original-$dir-$base" && install -m 0644 "$run_root/original-$dir-$base" "$PREFIX/drive_c/windows/$dir/$base"
  done; done
  find "$run_root" -maxdepth 1 -type f \( -name '*.log' -o -name '*.tsv' -o -name '*.txt' \) -exec cp -p {} "$EVIDENCE/" \; 2>/dev/null || true
  printf 'status=%s\n' "$status" >"$EVIDENCE/status.txt"
  case "$run_root" in "$RUNS"/*) rm -rf "$run_root";; esac
  exit "$status"
}
trap cleanup EXIT
for dir in system32 syswow64; do for base in d3d11.dll dxgi.dll d3d12.dll d3d12core.dll; do cp "$PREFIX/drive_c/windows/$dir/$base" "$run_root/original-$dir-$base"; done; done
common=(-O2 -g -Wall -Wextra -Werror "$VKMT/test/d3d12_graphics_contract.c" -ld3d12 -ldxgi -ld3dcompiler_47 -luuid)
"$TOOL/aarch64-w64-mingw32-clang" "${common[@]}" -ffixed-x18 -ffixed-x28 -o "$run_root/d3d12_graphics_arm64.exe" >"$run_root/compile-arm64.log" 2>&1 || exit 1
"$TOOL/arm64ec-w64-mingw32-clang" "${common[@]}" -ffixed-x18 -ffixed-x28 -o "$run_root/d3d12_graphics_arm64ec.exe" >"$run_root/compile-arm64ec.log" 2>&1 || exit 1
"$TOOL/x86_64-w64-mingw32-clang" "${common[@]}" -o "$run_root/d3d12_graphics_x86_64.exe" >"$run_root/compile-x86_64.log" 2>&1 || exit 1
"$TOOL/i686-w64-mingw32-clang" "${common[@]}" -o "$run_root/d3d12_graphics_i386.exe" >"$run_root/compile-i386.log" 2>&1 || exit 1

stage_provider() {
  case "$1" in
    arm64) dx="$DXVK_ROOT/aarch64"; vk="$VKD3D_ARM64_BIN"; to="$system32";;
    arm64ec|x86_64) dx="$DXVK_ROOT/arm64ec"; vk="$VKD3D_ROOT/install-arm64ec/bin"; to="$system32";;
    i386) dx="$DXVK_ROOT/x32"; vk="$VKD3D_ROOT/install-win32/bin"; to="$syswow64";;
    *) return 2;;
  esac
  for f in "$dx/d3d11.dll" "$dx/dxgi.dll" "$vk/d3d12.dll" "$vk/d3d12core.dll"; do test -f "$f" || return 1; done
  install -m 0644 "$dx/d3d11.dll" "$dx/dxgi.dll" "$vk/d3d12.dll" "$vk/d3d12core.dll" "$to/"
}
run_lane() {
  name=$1; exe=$2; arch=$3; log="$run_root/$name.log"
  WINEPREFIX="$PREFIX" "$SERVER" -k >/dev/null 2>&1 || true; WINEPREFIX="$PREFIX" "$SERVER" -w >/dev/null 2>&1 || true
  if ! stage_provider "$arch"; then printf '%s\tPROVIDER_MISSING\n' "$arch" >"$run_root/$name.tsv"; names+=("$name"); codes+=(125); overall=1; return; fi
  set +e
  "${timeout_cmd[@]}" env WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_D3D12_GRAPHICS_WINEDEBUG:--all}" VKMT_ALLOW_NON_SINGLE_TEXEL_ALIGNMENT=1 VK_ICD_FILENAMES="$VKMT/test/vkmt_icd.json" MVK_CONFIG_LOG_LEVEL=0 FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 WINEDLLOVERRIDES='dxgi,d3d11,d3d12,d3d12core=n' "$WINE" "Z:$exe" >"$log" 2>&1
  code=$?; set -e; names+=("$name"); codes+=("$code"); grep '^D3D12_' "$log" | sed "s/^D3D12_/${arch}\t/" | awk -F '\t' '{ if (NF == 2) print $0 "\t-"; else print }' >"$run_root/$name.tsv" || true; test "$code" -eq 0 || overall=1
}
run_lane arm64 "$run_root/d3d12_graphics_arm64.exe" arm64
run_lane arm64ec "$run_root/d3d12_graphics_arm64ec.exe" arm64ec
run_lane x86_64 "$run_root/d3d12_graphics_x86_64.exe" x86_64
run_lane i386 "$run_root/d3d12_graphics_i386.exe" i386
{
  printf 'arch\tmarker\tvalue\n'; for name in "${names[@]}"; do test -f "$run_root/$name.tsv" && cat "$run_root/$name.tsv"; done
} >"$EVIDENCE/capability.tsv"
{
  printf '# P8 D3D12 provider and fixture hashes\n'
  shasum -a 256 \
    "$VKD3D_ARM64_BIN/d3d12.dll" "$VKD3D_ARM64_BIN/d3d12core.dll" \
    "$VKD3D_ROOT/install-arm64ec/bin/d3d12.dll" \
    "$VKD3D_ROOT/install-arm64ec/bin/d3d12core.dll" \
    "$VKD3D_ROOT/install-win32/bin/d3d12.dll" \
    "$VKD3D_ROOT/install-win32/bin/d3d12core.dll" \
    "$VKMT/test/d3d12_graphics_contract.c" "$VKMT/scripts/probe-d3d12-graphics-contract.sh"
  printf 'vkd3d_source_commit %s\n' "$(git -C "$VKD3D_ROOT" rev-parse HEAD)"
} >"$EVIDENCE/hashes.sha256"
{
  printf '# D3D12 graphics contract — P8\n\nPrefix: `%s`\n\n' "$PREFIX"
  printf '| Architecture | rc | status |\n|---|---:|---|\n'
  for i in "${!names[@]}"; do test "${codes[$i]}" = 0 && s=PASS || s=CRASH_OR_FAIL; printf '| %s | %s | %s |\n' "${names[$i]}" "${codes[$i]}" "$s"; done
  printf '\n## Coverage and boundaries\n\n- The fixture covers generated VS/PS/CS DXBC, queue/allocator/list, descriptor-table UAV, RTV descriptor heap, graphics/compute pipelines, clear/draw/dispatch, explicit UAV/RTV state barriers, texture/buffer readback, fence timeout/completion, and clean device-removal-reason queries.\n- A second device initialization is proven on ARM64, ARM64EC, and x86_64. The i386/WoW64 thunk currently faults on a second D3D12CreateDevice entry after the first lane completes; it is recorded as `DEVICE_RECREATE_NOT_CLAIMED_I386_WOW64`, not converted into a pass.\n- Swap-chain/present/resize and injected device-loss remain separate window/lifecycle lanes.\n- Nonzero lanes remain visible in `capability.tsv`; this is not a green gate unless every lane is zero.\n- All lanes use matched rebuilt providers, FEX TSO settings of zero, and the existing prefix without wineboot.\n'
} >"$EVIDENCE/RESULTS.md"
if test "$overall" = 0; then echo D3D12_GRAPHICS_CONTRACT_ALL_ARCHITECTURES_OK; else echo D3D12_GRAPHICS_CONTRACT_EXECUTED_WITH_GAPS >&2; fi
exit "$overall"
