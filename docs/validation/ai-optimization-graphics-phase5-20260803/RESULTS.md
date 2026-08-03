# Graphics/CEF Phase 5 receipt — P8 runtime

Date: 2026-08-03

The graphics phase reused the existing canonical prefix and current P8
providers. No prefix was created and no Wineboot was run by these focused
gates.

## P8 hot-set result

Command: `scripts/probe-perf-p8-hotset.sh` with
`VKMT_P8_PREFIX=build/probe-runs/phase-a-graphics-prefix` and five runs.

```text
P8_HOTSET_OK physical_gbps=0.866817 effective_gbps=2.249713 total_gbps=1.031470 stall_reduction_pct=61.45 warm_regression_pct=0.15
```

This is a 61.45% median cold blocking-stall reduction, with 0.15% warm
regression and incompatible cache rows rejected. The raw compact receipt is
`docs/validation/ai-optimization-p8-hotset-20260803/metrics.tsv`.

## CEF x86_64 OSR result

The existing-prefix CEF OSR gate passed:

```text
CEF_X86_64_OSR_PIXEL_OK
CEF_X86_64_OSR_RENDER_OK
```

The deterministic BGRA paint marker was present and the launcher returned
status 0. The gate is x86_64 product proof; i386 CEF remains a separately
documented compatibility boundary and is not falsely marked green.

## Promotion status

No graphics host-boundary source was changed by the AI candidate pass. The
measured speed improvement is from the already promoted P8 hot-set runtime;
future source candidates must preserve this gate.
