# P8 prepared-prefix architecture baseline after WoW64 Phase 1

Prefix: `/Volumes/AverySSD/VKMT/build/probe-runs/phase-a-graphics-prefix`

| Architecture | rc | status |
|---|---:|---|
| ARM64 | 0 | PASS |
| ARM64EC | 0 | PASS |
| x86_64/FEX | 0 | PASS |
| i386/WoW64/FEX | 0 | PASS |

The baseline reused the existing prefix and did not invoke Wineboot. The
custom WoW64 module from nested Wine commit `f108c09` was staged in place
before the run. All three FEX TSO settings were zero.

**P8_SINGLE_PREFIX_ALL_ARCHITECTURES_OK**
