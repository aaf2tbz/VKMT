# CEF i386/WoW64 current-provider result

- Prefix: `/Volumes/AverySSD/VKMT/build/probe-runs/phase-a-graphics-prefix`
- TSO modes: `FEX_TSOENABLED=0`, `FEX_VECTORTSOENABLED=0`,
  `FEX_MEMCPYSETTSOENABLED=0`
- ARM64/i386 provider: `ac512105b5feb85227f2814deb77de603d73ff4713ee60045b23e51c2276f386`
- ARM64EC provider: `cccc70a4dd598371ed11c5a7979ca2ecff66a9849ba8086421a69054890c8c5f`

## Observed

- `CEF_I386_EXPORTS_OK`
- `CEF_I386_FEX_ALLOCATION_TRACE_OK`
- Prefix receipt/provider/DXMT verification passed before the run.
- The same prefix's x64+i386 WoW64 contract passed separately with
  `WOW64_VM_CONTRACT_ALL_OK` and correlated i386 FEX invalidations.

## Not accepted

The current i386 CEF browser did not publish a DevTools endpoint. Therefore
navigation, renderer subprocess, CDP, HTTPS/input/audio, screenshot, and pixel
markers are absent. This is a current CEF/WoW64 browser-startup/rendering gap;
it is not evidence to claim the i386 CEF rendering gate is green.
