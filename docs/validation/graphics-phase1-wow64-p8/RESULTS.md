# WoW64 VM contract — P8

Prefix: `/Volumes/AverySSD/VKMT/build/probe-runs/phase-a-graphics-prefix`

| Architecture | rc | status |
|---|---:|---|
| x64 | 0 | PASS |
| i386 | 0 | PASS |

## Coverage

- reserve/commit/decommit/recommit/release, protection, reuse, overlap ordering, file views, concurrent pressure, high-host allocation, guest-aperture policy, and executable-map reuse are emitted as independent markers.
- i386 FEX invalidation requires a correlated nonzero maintenance summary.
- All FEX TSO settings are zero.

**WOW64_VM_CONTRACT_ALL_OK**
