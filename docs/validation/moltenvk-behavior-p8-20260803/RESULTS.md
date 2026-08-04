# MoltenVK direct behavior contract — P8

MoltenVK: /Volumes/AverySSD/VKMT/third_party/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib

Probe status: 0

This fixture distinguishes feature enumeration from behavioral proof.

## Covered behavior

- null storage-buffer descriptors: direct compute readback must be zero;
- robust storage-buffer access: direct out-of-bounds readback must be zero;
- robust storage-image access: direct out-of-bounds readback must be zero;
- transform feedback and indirect count: unsupported claims must be absent;
- typed-buffer alignment: alignment properties are recorded; unaligned offsets are not advertised as proven.

## Evidence

- `probe.log`
- `driver.log`
- `capability.tsv`
- `hashes.sha256`
- `moltenvk-revision.txt`

**MOLTENVK_BEHAVIOR_CONTRACT_OK**
