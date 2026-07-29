#!/bin/bash
# Classify an installer without executing it. With --require-runnable,
# unsupported package engines return EX_USAGE (64) after printing a diagnosis.
set -euo pipefail

require_runnable=0
if test "${1:-}" = --require-runnable; then
  require_runnable=1
  shift
fi
test "$#" = 1 || { echo "usage: $0 [--require-runnable] package" >&2; exit 64; }
artifact=$1
test -f "$artifact" || { echo "INSTALLER_ERROR=not_found"; exit 66; }
lower="$(printf '%s' "$artifact" | tr '[:upper:]' '[:lower:]')"
family=unknown
support=diagnostic-only

case "$lower" in
  *.msi) family=msi; support=wine ;;
  *.msix|*.msixbundle) family=msix ;;
  *.appx|*.appxbundle) family=appx ;;
  *.application) family=clickonce ;;
  *.exe)
    strings_output="$(strings -a "$artifact" 2>/dev/null || true)"
    if grep -Eqi 'Inno Setup Setup Data|Inno Setup' <<<"$strings_output"; then
      family=inno; support=wine-or-native-extract
    elif grep -Eqi 'Nullsoft Install System|NSIS' <<<"$strings_output"; then
      family=nsis; support=wine
    elif grep -Eqi 'WixBundle|Burn Bootstrapper|WixBurn' <<<"$strings_output"; then
      family=burn
    elif grep -Eqi 'InstallShield' <<<"$strings_output"; then
      family=installshield
    elif grep -Eqi 'SquirrelAwareVersion|Update\.exe.*Squirrel|Squirrel' <<<"$strings_output"; then
      family=squirrel
    else
      family=generic-pe; support=wine
    fi
    ;;
esac

printf 'INSTALLER_FAMILY=%s\nINSTALLER_SUPPORT=%s\n' "$family" "$support"
if test "$require_runnable" = 1 && test "$support" = diagnostic-only; then
  echo "INSTALLER_DIAGNOSTIC=unsupported_package_engine"
  exit 64
fi
