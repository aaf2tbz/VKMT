# P8 final non-WoW64 architecture gate

The gate reused the receipt-backed canonical prefix:

`build/probe-runs/phase-a-graphics-prefix`

No prefix recreation or Wineboot was performed. All FEX TSO controls were
zero. The supporting P6 runner was invoked with `--skip-i386` and completed
with `status=0`:

- ARM64 smoke: `rc=0`
- ARM64EC smoke: `rc=0`
- x86_64 smoke: `rc=0`
- i386/WoW64: intentionally excluded from this final gate

The final prefix verification also completed with `rc=0`, including provider
and DXMT closure checks.
