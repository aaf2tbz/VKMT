#!/usr/bin/env bash
# Safe VKMT integration for sebyx07/c-ai-optimizer.
#
# This tool only pins the upstream optimizer, inventories high-priority Wine
# sources, runs its architecture-safe self-test, and prepares immutable
# candidate inputs. It never overwrites wine/wine-11.12.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd -P)"
WINE_SOURCE="${VKMT_WINE_SOURCE:-$VKMT/wine/wine-11.12}"
OPTIMIZER_URL="${VKMT_CAI_OPTIMIZER_URL:-https://github.com/sebyx07/c-ai-optimizer.git}"
OPTIMIZER_COMMIT="${VKMT_CAI_OPTIMIZER_COMMIT:-c6f96df0ec9973a4cbdb7b015b1fd106c815ad89}"
OPTIMIZER_DIR="${VKMT_CAI_OPTIMIZER_ROOT:-$VKMT/third_party/c-ai-optimizer}"
TARGETS="${VKMT_CAI_TARGETS:-$VKMT/docs/c-ai-optimizer-vkmt-targets.tsv}"
FULL_LEDGER="${VKMT_CAI_FULL_LEDGER:-$VKMT/docs/AI_OPTIMIZATION_LEDGER.tsv}"
DISPOSITION="${VKMT_CAI_DISPOSITION:-$VKMT/docs/AI_OPTIMIZATION_DISPOSITION.tsv}"
CANDIDATES="${VKMT_CAI_CANDIDATES:-$VKMT/build/c-ai-optimizer-candidates}"
SMOKE_OUT="${VKMT_CAI_SMOKE_OUT:-$VKMT/build/c-ai-optimizer-vkmt-arm64-smoke}"

die() { echo "vkmt-c-ai-optimizer: $*" >&2; exit 1; }

usage()
{
    cat >&2 <<EOF
usage: $0 {setup|inventory|prepare|inventory-all|prepare-all|smoke|disposition|verify}

  setup       clone/fetch and pin c-ai-optimizer at the recorded commit
  inventory   hash the high-priority custom Wine source inputs
  prepare     copy immutable source inputs into a new candidate workspace
  inventory-all hash all 82 ledger paths and emit a refreshed full ledger
  prepare-all copy all ledger paths into an immutable candidate workspace
  smoke       run the upstream normal/optimized correctness suite without
              ARM64-incompatible -mavx flags
  disposition validate that every ledger candidate path has a disposition row
  verify      verify the pin and source inventory (no source mutation)
EOF
    exit 2
}

require_file() { test -f "$1" || die "missing required file: $1"; }

setup_optimizer()
{
    local parent
    parent="$(dirname "$OPTIMIZER_DIR")"
    mkdir -p "$parent"
    if test ! -e "$OPTIMIZER_DIR/.git"; then
        test ! -e "$OPTIMIZER_DIR" || die "optimizer path exists without Git metadata: $OPTIMIZER_DIR"
        git clone --filter=blob:none "$OPTIMIZER_URL" "$OPTIMIZER_DIR"
    fi
    git -C "$OPTIMIZER_DIR" diff --quiet ||
        die "optimizer checkout is dirty; preserve or remove it before pinning"
    git -C "$OPTIMIZER_DIR" fetch --depth=1 origin "$OPTIMIZER_COMMIT"
    git -C "$OPTIMIZER_DIR" checkout --detach "$OPTIMIZER_COMMIT" >/dev/null
    test "$(git -C "$OPTIMIZER_DIR" rev-parse HEAD)" = "$OPTIMIZER_COMMIT" ||
        die "optimizer checkout is not pinned to $OPTIMIZER_COMMIT"
    echo "VKMT_CAI_OPTIMIZER_PIN_OK commit=$OPTIMIZER_COMMIT path=$OPTIMIZER_DIR"
}

read_targets()
{
    require_file "$TARGETS"
    while IFS=$'\t' read -r path tier mode rationale; do
        case "$path" in
            ''|'#'*) continue ;;
        esac
        printf '%s\t%s\t%s\t%s\n' "$path" "$tier" "$mode" "$rationale"
    done < "$TARGETS"
}

read_full_targets()
{
    require_file "$FULL_LEDGER"
    while IFS=$'\t' read -r path state tier mode recorded_hash rationale; do
        case "$path" in
            ''|'#'|'path') continue ;;
        esac
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$path" "$state" "$tier" "$mode" "$recorded_hash" "$rationale"
    done < "$FULL_LEDGER"
}

inventory()
{
    local path tier mode rationale hash
    require_file "$TARGETS"
    test -d "$WINE_SOURCE" || die "missing Wine source tree: $WINE_SOURCE"
    printf 'path\ttier\tmode\tsha256\trationale\n'
    while IFS=$'\t' read -r path tier mode rationale; do
        case "$path" in
            ''|'#'*) continue ;;
        esac
        require_file "$WINE_SOURCE/$path"
        hash="$(shasum -a 256 "$WINE_SOURCE/$path" | awk '{print $1}')"
        printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$tier" "$mode" "$hash" "$rationale"
    done < "$TARGETS"
}

prepare()
{
    local run path tier mode rationale hash candidate
    setup_optimizer >/dev/null
    run="$(date +%Y%m%dT%H%M%S).$$"
    candidate="$CANDIDATES/$run"
    mkdir -p "$candidate/input" "$candidate/metadata"
    printf 'optimizer_url\t%s\noptimizer_commit\t%s\nsource_root\t%s\n' \
        "$OPTIMIZER_URL" "$OPTIMIZER_COMMIT" "$WINE_SOURCE" >"$candidate/metadata/run.tsv"
    printf 'path\ttier\tmode\tsha256\trationale\n' >"$candidate/metadata/sources.tsv"
    while IFS=$'\t' read -r path tier mode rationale; do
        case "$path" in
            ''|'#'*) continue ;;
        esac
        require_file "$WINE_SOURCE/$path"
        mkdir -p "$candidate/input/$(dirname "$path")"
        cp -p "$WINE_SOURCE/$path" "$candidate/input/$path"
        hash="$(shasum -a 256 "$WINE_SOURCE/$path" | awk '{print $1}')"
        printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$tier" "$mode" "$hash" "$rationale" \
            >>"$candidate/metadata/sources.tsv"
    done < "$TARGETS"
    printf 'VKMT_CAI_CANDIDATE_READY path=%s\n' "$candidate"
    printf '%s\n' \
        'No candidate was applied to the Wine tree. Review and benchmark each' \
        'function-level change before promotion.' >"$candidate/metadata/STATUS"
}

inventory_all()
{
    local path state tier mode recorded_hash rationale hash
    test -d "$WINE_SOURCE" || die "missing Wine source tree: $WINE_SOURCE"
    printf 'path\tstate\ttier\tmode\tsha256\trationale\n'
    while IFS=$'\t' read -r path state tier mode recorded_hash rationale; do
        require_file "$WINE_SOURCE/$path"
        hash="$(shasum -a 256 "$WINE_SOURCE/$path" | awk '{print $1}')"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$path" "$state" "$tier" "$mode" "$hash" "$rationale"
    done < <(read_full_targets)
}

prepare_all()
{
    local run path state tier mode recorded_hash rationale hash candidate
    setup_optimizer >/dev/null
    run="$(date +%Y%m%dT%H%M%S).$$"
    candidate="$CANDIDATES/$run-all"
    mkdir -p "$candidate/input" "$candidate/metadata"
    printf 'optimizer_url\t%s\noptimizer_commit\t%s\nsource_root\t%s\nledger\t%s\n' \
        "$OPTIMIZER_URL" "$OPTIMIZER_COMMIT" "$WINE_SOURCE" "$FULL_LEDGER" >"$candidate/metadata/run.tsv"
    printf 'path\tstate\ttier\tmode\tsha256\trationale\n' >"$candidate/metadata/sources.tsv"
    while IFS=$'\t' read -r path state tier mode recorded_hash rationale; do
        require_file "$WINE_SOURCE/$path"
        mkdir -p "$candidate/input/$(dirname "$path")"
        cp -p "$WINE_SOURCE/$path" "$candidate/input/$path"
        hash="$(shasum -a 256 "$WINE_SOURCE/$path" | awk '{print $1}')"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$path" "$state" "$tier" "$mode" "$hash" "$rationale" \
            >>"$candidate/metadata/sources.tsv"
    done < <(read_full_targets)
    printf 'VKMT_CAI_FULL_CANDIDATE_READY path=%s files=%s\n' \
        "$candidate" "$(tail -n +2 "$candidate/metadata/sources.tsv" | wc -l | tr -d ' ')"
}

verify_disposition()
{
    require_file "$FULL_LEDGER"
    require_file "$DISPOSITION"
    python3 - "$FULL_LEDGER" "$DISPOSITION" <<'PY'
import csv
import sys

ledger_path, disposition_path = sys.argv[1:]
with open(ledger_path, newline="", encoding="utf-8") as stream:
    ledger = list(csv.DictReader(stream, delimiter="\t"))
with open(disposition_path, newline="", encoding="utf-8") as stream:
    disposition = list(csv.DictReader(stream, delimiter="\t"))

required = {"path", "phase", "ledger_mode", "disposition", "evidence", "next_action"}
if not disposition or set(disposition[0]) != required:
    raise SystemExit("invalid disposition header")

candidates = {row["path"] for row in ledger if row.get("mode") == "candidate"}
rows = {}
for row in disposition:
    path = row["path"]
    if path in rows:
        raise SystemExit(f"duplicate disposition row: {path}")
    rows[path] = row

missing = sorted(candidates - rows.keys())
unknown = sorted(rows.keys() - candidates)
if missing:
    raise SystemExit("missing candidate dispositions: " + ", ".join(missing))
if unknown:
    raise SystemExit("dispositions for non-candidate paths: " + ", ".join(unknown))
for path, row in rows.items():
    if row["ledger_mode"] != "candidate":
        raise SystemExit(f"disposition mode mismatch: {path}")
    if not row["disposition"] or not row["evidence"] or not row["next_action"]:
        raise SystemExit(f"incomplete disposition row: {path}")
print(f"VKMT_CAI_DISPOSITION_OK candidates={len(rows)} path={disposition_path}")
PY
}

smoke()
{
    local root="$OPTIMIZER_DIR" cc omp_prefix
    local -a common omp_cflags omp_ldflags normal_sources optimized_sources tests
    test -d "$root" || die "optimizer is not set up; run '$0 setup' first"
    cc="${VKMT_CAI_CC:-clang}"
    command -v "$cc" >/dev/null 2>&1 || die "compiler not found: $cc"
    omp_prefix="${VKMT_CAI_OPENMP_PREFIX:-/opt/homebrew/opt/libomp}"
    test -f "$omp_prefix/include/omp.h" ||
        die "OpenMP headers missing: $omp_prefix/include/omp.h"
    test -f "$omp_prefix/lib/libomp.dylib" ||
        die "OpenMP library missing: $omp_prefix/lib/libomp.dylib"

    rm -rf "$SMOKE_OUT"
    mkdir -p "$SMOKE_OUT"
    common=(-std=c11 -O3 -Wall -Wextra -I"$root/include" -I"$omp_prefix/include"
            -Xpreprocessor -fopenmp)
    omp_ldflags=(-L"$omp_prefix/lib" -lomp -lm)
    normal_sources=("$root/src/matrix.c" "$root/src/vector.c" "$root/src/stats.c" "$root/src/utils.c")
    optimized_sources=("$root/src_optimized/matrix.c" "$root/src_optimized/vector.c"
                       "$root/src_optimized/stats.c" "$root/src_optimized/utils.c")
    tests=("$root/tests/test_runner.c" "$root/tests/test_matrix.c" "$root/tests/test_vector.c"
           "$root/tests/test_stats.c" "$root/tests/test_matrix_comprehensive.c")

    # Do not inherit the upstream CMake -mavx/-march=native flags.  This host
    # is ARM64; the optimizer's x86 SIMD sections are guarded and its scalar
    # plus OpenMP path is the correct self-test for the native host.
    "$cc" "${common[@]}" "${normal_sources[@]}" "${tests[@]}" "${omp_ldflags[@]}" \
        -o "$SMOKE_OUT/test_normal"
    "$cc" "${common[@]}" "${optimized_sources[@]}" "${tests[@]}" "${omp_ldflags[@]}" \
        -o "$SMOKE_OUT/test_optimized"
    "$SMOKE_OUT/test_normal" >"$SMOKE_OUT/normal.log"
    "$SMOKE_OUT/test_optimized" >"$SMOKE_OUT/optimized.log"
    grep -q 'ALL TESTS PASSED' "$SMOKE_OUT/normal.log"
    grep -q 'ALL TESTS PASSED' "$SMOKE_OUT/optimized.log"
    echo "VKMT_CAI_OPTIMIZER_ARM64_SMOKE_OK output=$SMOKE_OUT"
}

verify()
{
    setup_optimizer >/dev/null
    inventory >/dev/null
    verify_disposition
    echo "VKMT_CAI_OPTIMIZER_VERIFY_OK"
}

test "$#" -eq 1 || usage
case "$1" in
    setup) setup_optimizer ;;
    inventory) inventory ;;
    prepare) prepare ;;
    inventory-all) inventory_all ;;
    prepare-all) prepare_all ;;
    smoke) smoke ;;
    disposition) verify_disposition ;;
    verify) verify ;;
    *) usage ;;
esac
