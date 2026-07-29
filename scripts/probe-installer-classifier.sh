#!/bin/bash
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
CLASSIFIER="$VKMT/scripts/classify-installer.sh"
run_root="$(mktemp -d "$VKMT/build/installer-classifier.XXXXXX")"
cleanup()
{
  status=$?
  /usr/bin/trash "$run_root" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT

make_marker()
{
  path=$1
  marker=$2
  printf 'MZ synthetic classifier fixture\n%s\n' "$marker" >"$path"
}
make_marker "$run_root/inno.exe" 'Inno Setup Setup Data'
make_marker "$run_root/nsis.exe" 'Nullsoft Install System'
make_marker "$run_root/burn.exe" 'WixBundle Burn Bootstrapper'
make_marker "$run_root/installshield.exe" 'InstallShield'
make_marker "$run_root/squirrel.exe" 'SquirrelAwareVersion'
make_marker "$run_root/generic.exe" 'ordinary portable executable'
printf 'fixture\n' >"$run_root/package.msi"
printf 'fixture\n' >"$run_root/package.msix"
printf 'fixture\n' >"$run_root/package.appx"
printf 'fixture\n' >"$run_root/package.application"

for spec in \
  inno.exe:inno nsis.exe:nsis burn.exe:burn \
  installshield.exe:installshield squirrel.exe:squirrel generic.exe:generic-pe \
  package.msi:msi package.msix:msix package.appx:appx \
  package.application:clickonce; do
  IFS=: read -r file expected <<<"$spec"
  output="$("$CLASSIFIER" "$run_root/$file")"
  grep -q "INSTALLER_FAMILY=$expected" <<<"$output"
done
for unsupported in burn.exe installshield.exe squirrel.exe package.msix package.appx package.application; do
  if "$CLASSIFIER" --require-runnable "$run_root/$unsupported" \
      >"$run_root/$unsupported.log" 2>&1; then
    echo "$unsupported unexpectedly classified as runnable" >&2
    exit 1
  else
    code=$?
  fi
  test "$code" = 64
  grep -q 'INSTALLER_DIAGNOSTIC=unsupported_package_engine' \
    "$run_root/$unsupported.log"
done
echo INSTALLER_CLASSIFIER_DIAGNOSTIC_FAILURE_OK
