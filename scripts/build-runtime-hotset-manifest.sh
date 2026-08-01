#!/bin/bash
# Convert one or more five-second VM snapshots into a bounded relocatable manifest.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX=${WINEPREFIX:-}
OUTPUT=
CAP_BYTES=${VKMT_HOTSET_CAP_BYTES:-268435456}

usage()
{
  echo "usage: WINEPREFIX=PREFIX $0 OUTPUT RAW.tsv [RAW.tsv ...]" >&2
  exit 2
}

test $# -ge 2 || usage
test -n "$PREFIX" && test -d "$PREFIX" || usage
OUTPUT=$1
shift
for input in "$@"; do test -f "$input" || usage; done

work="$(mktemp -d "$VKMT/build/perf-p8/manifest.XXXXXX")"
cleanup()
{
  case "$work" in "$VKMT/build/perf-p8"/*) find "$work" -depth -delete 2>/dev/null || true ;; esac
}
trap cleanup EXIT

: >"$work/candidates.tsv"
for input in "$@"; do
  awk -F '\t' -v vkmt="$VKMT/" -v prefix="$PREFIX/" '
    NR == 1 { next }
    index($1, vkmt) == 1 || index($1, prefix) == 1 {
      amount = $3
      if ($4 > 0 && $4 < amount) amount = $4
      if (amount < 16384) amount = 16384
      print $4 "\t" $1 "\t" $2 "\t" amount
    }
  ' "$input" >>"$work/candidates.tsv"
done
LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 -k3,3n "$work/candidates.tsv" |
  awk -F '\t' '!seen[$2 FS $3 FS $4]++' >"$work/sorted.tsv"

mkdir -p "$(dirname "$OUTPUT")"
printf 'scope\tpath\toffset\tlength\tfile_size\tmtime\n' >"$OUTPUT"
total=0
while IFS=$'\t' read -r resident path offset length; do
  test -f "$path" || continue
  case "$path" in
    "$VKMT/wine/build-ec/"*|"$VKMT/wine/wine-11.12/nls/"*) scope=VKMT; relative=${path#"$VKMT/"} ;;
    "$PREFIX/"*) scope=PREFIX; relative=${path#"$PREFIX/"} ;;
    *) continue ;;
  esac
  case "$relative" in *$'\t'*|*'../'*) continue ;; esac
  size="$(stat -f %z "$path")"
  mtime="$(stat -f %m "$path")"
  test "$offset" -lt "$size" || continue
  available=$((size - offset))
  test "$length" -le "$available" || length=$available
  test $((total + length)) -le "$CAP_BYTES" || continue
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$scope" "$relative" "$offset" "$length" "$size" "$mtime" >>"$OUTPUT"
  total=$((total + length))
done <"$work/sorted.tsv"

entries=$(( $(wc -l <"$OUTPUT") - 1 ))
test "$entries" -gt 0 && test "$total" -gt 0
printf 'VKMT_HOTSET_MANIFEST_OK entries=%s bytes=%s cap=%s output=%s\n' "$entries" "$total" "$CAP_BYTES" "$OUTPUT"
