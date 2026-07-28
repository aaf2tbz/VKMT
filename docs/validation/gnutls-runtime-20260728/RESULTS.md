# Native ARM64 GnuTLS runtime — 2026-07-28

Wine 11.12 was configured with `--with-gnutls` and its native ARM64
`secur32.so` dynamically loads `libgnutls.30.dylib`.

`scripts/stage-gnutls-runtime.sh` recursively stages GnuTLS and its ten-dylib
ARM64 closure in `wine/build-ec/dlls/secur32`, rewrites every Homebrew
dependency to `@loader_path`, assigns relative install names, and ad-hoc signs
each artifact. The stage includes the required gettext, p11-kit, IDN,
Unicode, ASN.1, nettle/hogweed, and GMP dependencies.

`scripts/probe-gnutls-runtime.sh` creates a fresh disposable prefix and proves:

- outbound Schannel credential creation;
- WinHTTP HTTPS and certificate validation against `example.com`;
- WinINet HTTPS and certificate validation against `example.com`;
- HTTP status 200 through both APIs;
- dyld loaded the staged `dlls/secur32/libgnutls.30.dylib`;
- no staged dylib references `/opt/homebrew`.

Accepted markers:

```text
GNUTLS_ARM64_HTTPS_OK
GNUTLS_NATIVE_ARM64_SERVER_HTTPS_OK
```

The authoritative scope is the native ARM64 Wine server/Unix provider path.
Guest-architecture HTTPS repetitions are diagnostics rather than acceptance
requirements. The runner stops only its exact wineserver and removes only its
own disposable prefix on success or failure.
