# P6 GPU translation-cache acceptance — 2026-08-01

## Accepted implementation

- DXVK source commit: `398baae`
- Cache generation: `v2-aa3c4119e90f37e8`
- macOS: `27.0` build `26A5388g`
- Hardware/GPU: `Mac16,12`, Apple M4, Metal 4
- Scalar, vector, and memcpy/set FEX TSO: disabled
- Rosetta process translation: disabled

The runtime stages one per-prefix cache identity covering DXVK,
vkd3d-proton, DXMT/Winemetal, MoltenVK, and MetalSharp OpenGL artifacts.
`scripts/vkmt-gpu-cache-env.sh` supplies isolated cache roots to every normal
runtime launch. `scripts/stage-gpu-cache-runtime.sh` publishes the manifest
atomically, retains at most two generations, and rejects incompatible
OS/GPU/runtime identities.

## Deterministic DXVK measurements

The i386 D3D11 fixture compiles a fixed compute shader, dispatches it, copies
the result to a staging buffer, and verifies `0x504b3656`.

- cold shader translations: 1
- warm shader translations: 0
- warm cache hits: 1
- warm cache hit rate: 100%
- repeated shader-translation reduction: 100%
- cold pipeline interval: 70,199,700 ns
- warm pipeline p95 fixture interval: 43,209,300 ns
- incompatible manifest rejected and safely regenerated: yes
- exact wineserver shutdown and disposable-prefix cleanup: yes

Terminal markers:

```text
P6_DXVK_SHADER_CACHE_OK generation=v2-aa3c4119e90f37e8 reduction=100%
P6_GPU_CACHE_ACCEPTANCE_OK
```

## Regression gates

The same staged runtime passed the complete i386 VKMT DLL, DXGI, D3D12, and
D3D11 ladder. vkd3d-proton logged its cache remap into the schema-2 generation.
The final fresh single-prefix run returned status 0 for ARM64, ARM64EC,
x86_64, and i386 and ended with:

```text
P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
```

Raw compact evidence is preserved under `build/perf-p6/gpu-cache-i386/`,
`build/perf-p6/regression-p5-i386-vkmt/`, and
`build/perf-p6/single-prefix-all-arch/`. Failed disposable prefixes were
deleted before the next attempt.
