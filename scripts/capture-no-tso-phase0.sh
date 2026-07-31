#!/bin/sh
set -eu

vkmt_root=/Volumes/AverySSD/VKMT
wine_source="$vkmt_root/wine/wine-11.12"
wine_build="$vkmt_root/wine/build-ec"
fex_source="$vkmt_root/third_party/FEX-2607"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
output=${1:-"$vkmt_root/docs/validation/no-tso-phase0-$stamp"}

case "$output" in
    "$vkmt_root"/*) ;;
    *) echo "Phase 0 evidence must remain below $vkmt_root" >&2; exit 2 ;;
esac

mkdir -p "$output"

capture_git()
{
    name=$1
    source=$2
    (
        cd "$source"
        git rev-parse HEAD
        git status --short
    ) >"$output/$name-source-state.txt"
    git -C "$source" diff --binary >"$output/$name-working-tree.diff"
}

capture_git wine "$wine_source"
capture_git fex "$fex_source"

cat >"$output/runtime-files.txt" <<EOF
$wine_build/wine
$wine_build/server/wineserver
$wine_build/dlls/ntdll/ntdll.so
$wine_build/dlls/xtajit/aarch64-windows/xtajit.dll
$wine_build/dlls/xtajit64/aarch64-windows/xtajit64.dll
$wine_source/runtime-providers/xtajit-arm64-known-good.dll
$wine_source/runtime-providers/xtajit64-arm64ec-known-good.dll
EOF

: >"$output/runtime-sha256.txt"
: >"$output/runtime-architectures.txt"
while IFS= read -r artifact
do
    if test -f "$artifact"
    then
        shasum -a 256 "$artifact" >>"$output/runtime-sha256.txt"
        file "$artifact" >>"$output/runtime-architectures.txt"
    else
        echo "MISSING  $artifact" >>"$output/runtime-sha256.txt"
        echo "MISSING  $artifact" >>"$output/runtime-architectures.txt"
    fi
done <"$output/runtime-files.txt"

{
    echo "Steam-specific temporary compatibility surface"
    rg -n "VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY|steam_wait_poll|steam_bootstrap|synthetic" \
        "$wine_source/dlls/ntdll/sync.c" \
        "$vkmt_root/scripts/launch-steam-client-recovery.sh" \
        "$vkmt_root/scripts/launch-steam-client-supervised.sh" \
        "$vkmt_root/scripts/launch-steam-setup-ssd.sh" 2>/dev/null || true
} >"$output/steam-specific-surface.txt"

{
    echo "Generic synchronization and no-TSO surface"
    rg -n "WowTebOffset|pending_wakes|synchronize_wow64_guest_address|VKMT_WOW64_SYNC_METRICS|ValidateNoTSOContract|VKMT_REQUIRE_NO_TSO" \
        "$wine_source/dlls/ntdll/sync.c" \
        "$wine_source/dlls/ntdll/loader.c" \
        "$fex_source/Source/Windows/Common/TSOHandlerConfig.h" \
        "$fex_source/Source/Windows/ARM64EC/Module.cpp" \
        "$fex_source/Source/Windows/WOW64/Module.cpp"
} >"$output/generic-sync-surface.txt"

{
    echo "captured_utc=$stamp"
    echo "host_arch=$(uname -m)"
    echo "wine_source=$wine_source"
    echo "wine_build=$wine_build"
    echo "fex_source=$fex_source"
    echo "evidence=$output"
} >"$output/MANIFEST.txt"

echo "$output"
