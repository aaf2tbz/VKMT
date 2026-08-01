# Headless cold-start MoltenVK deferral

Date: 2026-08-01

## Cause

On every cold Wine session, `wineboot` executed the `RunServices` entry for
`winemenubuilder.exe -a -r`. The helper loaded shell32/win32u and eagerly
created a Vulkan instance through MoltenVK even for a trivial console guest.
`WINE_NO_EXPLORER=1` suppressed the display driver but did not suppress this
desktop-integration helper.

## Fix

When `WINE_NO_EXPLORER` is set, wineboot now skips only the desktop-integration
`RunServices` pass. It still launches `services.exe`, preserving the Windows
service contract needed by applications.

Only `programs/wineboot/aarch64-windows/wineboot.exe` was rebuilt.

## Measurement

Five x86_64 launches used a cold wineserver, the retained accepted prefix, the
three no-TSO settings fixed at zero, and `WINE_NO_EXPLORER=1`:

| Run | Exit | Elapsed | MoltenVK records |
| --- | ---: | ---: | ---: |
| 1 | 0 | 0.71 s | 0 |
| 2 | 0 | 0.59 s | 0 |
| 3 | 0 | 0.58 s | 0 |
| 4 | 0 | 0.62 s | 0 |
| 5 | 0 | 0.59 s | 0 |

The previously recorded cold range was approximately 0.88-0.92 seconds and
included complete MoltenVK capability enumeration.

## Regression gate

`scripts/probe-p6-single-prefix-architectures.sh` passed in one fresh prefix:

- `P6_SINGLE_PREFIX_ARM64_OK`
- `P6_SINGLE_PREFIX_ARM64EC_OK`
- `P6_SINGLE_PREFIX_X86_64_OK`
- `P6_SINGLE_PREFIX_I386_OK`
- `P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK`
- final `status=0`

The disposable prefix was stopped through its exact wineserver and removed.
