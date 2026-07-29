# Wine Mono 11.2.0 acceptance — 2026-07-29

Official Wine Mono 11.2.0 is pinned by SHA-256 for both its GitHub runtime and
matching source archives. The upstream x86 and x86_64 engines are retained,
and the ARM64 engine is source-built with VKMT's x18/x28 ABI and Darwin
16-KiB W^X contract.

Targeted build:

```text
scripts/build-wine-mono-arm64.sh
VKMT_WINE_MONO_11_2_0_ARM64_BUILD_OK
```

This rebuilds only the required Mono ARM64 targets, ARM64X `mscoree.dll` and
`ntdll.dll`, native `ntdll.so`, and `wineserver`. It does not rebuild Wine as
a whole.

Fresh disposable-prefix managed gate:

```text
scripts/probe-wine-mono-runtime.sh
VKMT_WINE_MONO_11_2_0_I386_OK
VKMT_WINE_MONO_11_2_0_ARM64_OK
VKMT_WINE_MONO_11_2_0_X86_64_OK
VKMT_WINE_MONO_11_2_0_ALL_OK
```

The probe compiles all three managed images in the same prefix, then verifies
pointer width, threads, reflection, XML, and kernel32 P/Invoke. PE32+ x86_64
IL-only images enter the native ARM64 CLR contract before Wine creates an
ARM64EC stack or starts `xtajit64`; native-code x86_64 routing is unchanged.

Post-change architecture regression:

```text
scripts/probe-p6-single-prefix-architectures.sh
P6_SINGLE_PREFIX_ARM64_OK
P6_SINGLE_PREFIX_ARM64EC_OK
P6_SINGLE_PREFIX_X86_64_OK
P6_SINGLE_PREFIX_I386_OK
P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
```

Both probes used exact-prefix wineserver shutdown. No disposable prefix or
diagnostic log root from this acceptance is retained.
