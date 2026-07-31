# Steam WebHelper rendered-login acceptance

Date: 2026-07-31

The preserved all-architecture prefix
`prefixes/steam-no-tso-phase6` launched installed Windows Steam through the
native ARM64 Wine host with all FEX TSO options disabled. Steam's x86 client
successfully handed off to the x86_64 CEF helper and rendered the complete
Steam sign-in UI, including account/password controls, QR code, links, and
text.

The accepted MetalSharp-compatible layout is:

```text
Steam/bin/cef/cef.win64/
├── steamwebhelper.exe       # MetalSharp forwarding wrapper
└── steamwebhelper_real.exe  # Steam's original x86_64 helper
```

The wrapper SHA-256 is
`f46a1e8c39c850ba22861f63559f13b4f68557acf04a92e6d1b899769b2ea1f9`.
It forwards Steam's arguments to `steamwebhelper_real.exe` and adds
`--in-process-gpu --disable-gpu`.

Steam itself was launched with:

```text
-no-cef-sandbox -cef-single-process -noverifyfiles -no-dwrite
```

The decisive boundary was `--in-process-gpu`. `-cef-disable-gpu` alone
correctly selected SwiftShader and disabled GPU compositing, but still created
a black window. The wrapper's in-process GPU route removed the failing
cross-process shared-image/presentation dependency and produced visible pixels
in approximately 28 seconds. No Rosetta process, hardware TSO, wake injection,
updater bypass, or diagnostic layer coloring participated.

The reproducible launcher is
`scripts/launch-steam-metalsharp-compatible.sh`. It repairs the wrapper layout
after Steam updates, verifies the wrapper hash, enforces all no-TSO variables,
loads VKMT's staged runtime environment, and holds the exact wineserver until
Steam exits.
