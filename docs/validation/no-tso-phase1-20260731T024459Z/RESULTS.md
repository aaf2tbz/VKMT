# No-TSO Phase 1 acceptance

Phase 1 passed in one fresh disposable prefix on the native ARM64 host.  The
runner forced all three FEX TSO settings off and disabled the Steam bootstrap
wake workaround:

```text
FEX_TSOENABLED=0
FEX_VECTORTSOENABLED=0
FEX_MEMCPYSETTSOENABLED=0
VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY=0
```

## Accepted gates

Both x86_64 and i386/WoW64 passed:

- 1,000,000 release/acquire publications with zero stale reads.
- Wake-before-wait, 20,000 waiter-registration races, WakeSingle/WakeAll with
  eight waiters, and 2,000 timeout/wake races.
- 200,000 condition-variable/critical-section rounds per thread.
- APC delivery during an alertable wait.
- 2,048 repeated thread lifecycles.
- 128/128 concurrent child-process completions.
- Eight concurrent 4-MiB WinHTTP HTTPS range downloads from the pinned Steam
  CDN package.

Every downloaded file matched the native curl reference:

```text
sha256=6c12394e835d27f53cf1df56807ed480a86cd07cce1546eef3a01d1886bd4fbe
x64=8/8
i386=8/8
```

`status.txt` is `0` and `summary.txt` contains `NO_TSO_PHASE1_ALL_OK`.

## i386 HTTPS correction

The first complete run isolated one failure: i386 Schannel generated the same
234-byte TLS ClientHello as x64, but native AFD send attempted a nested callback
into ARM64 PE `wow64.dll` to convert the WSABUF guest pointer.  That nested
native-to-PE transition broke the active i386 Unix-call return contract and
WinHTTP returned `ERROR_WINHTTP_SECURE_CHANNEL_ERROR` (12157).

Native ntdll now resolves i386 pointers without that re-entry:

1. Explicit native host mappings are searched in the native mapping table.
2. Ordinary Darwin i386 memory resolves through ntdll's authoritative high
   guest aperture.
3. The PE callback remains a non-Darwin fallback only.

A one-transfer diagnostic then passed, followed by the eight-transfer i386
gate and this complete all-fixture rerun.  No synthetic wake injection was
used.

## Reproduction

```sh
cd /Volumes/AverySSD/VKMT
make -C wine/build-ec -j8 dlls/ntdll/ntdll.so
VKMT_PHASE1_EVIDENCE_DIR="$PWD/docs/validation/no-tso-phase1-<timestamp>" \
  scripts/probe-no-tso-phase1.sh
```

Accepted artifact hashes:

```text
5bcc38737af9cd65a27ef846d27ec62fbbab2261e7faf04c32f9f49ebb9ab099  wine/build-ec/dlls/ntdll/ntdll.so
b9baa4e3e00eac14364b2e552432388a1a33487c7c42b125f64541058ee55877  scripts/probe-no-tso-phase1.sh
b87f6bf3dc77c7a6f959d9ce36e1ab294e235b16d27dd69d9e303fa0dd8e7783  test/no_tso_phase1_sync.c
4014f38889ad026b92db9c58caf5c7121fc0e16cad2325363cd10af19ead148d  test/no_tso_phase1_cdn.c
```

The exact wineserver was shut down and the disposable run root was removed.
