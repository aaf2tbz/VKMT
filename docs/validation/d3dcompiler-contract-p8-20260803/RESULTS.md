# D3DCompiler contract — P8

Prefix: `/Volumes/AverySSD/VKMT/build/probe-runs/phase-a-graphics-prefix`

## Result

The required compiler lanes and enabled consumer lanes completed with rc=0.

## Architecture/API capability table

| Architecture | DLL | API | Status | HRESULT | Detail |
|---|---|---|---|---|---|
| arm64 | d3dcompiler_47 | VS_compile | PASS | 0x00000000 | vs_5_0 macros include flags |
| arm64 | d3dcompiler_47 | PS_compile | PASS | 0x00000000 | ps_5_0 |
| arm64 | d3dcompiler_47 | CS_compile | PASS | 0x00000000 | cs_5_0 DXBC producer |
| arm64 | d3dcompiler_47 | include_handler | PASS | 0x00000000 | Open/Close local include |
| arm64 | d3dcompiler_47 | preprocess | PASS | 0x00000000 | macros include expansion |
| arm64 | d3dcompiler_47 | compile_failure_diagnostics | PASS | 0x80004005 | invalid HLSL returns diagnostic blob |
| arm64 | d3dcompiler_47 | compile_from_file_unicode | PASS | 0x00000000 | UTF-16 path |
| arm64 | d3dcompiler_47 | read_file_blob | PASS | 0x00000000 | UTF-16 path |
| arm64 | d3dcompiler_47 | disassembly | PASS | 0x00000000 | DXBC disassembly blob |
| arm64 | d3dcompiler_47 | legacy_reflection_fixture | PASS | 0x00000000 | vs_4_0 fixture for d3dcompiler_43 |
| arm64 | d3dcompiler_47 | reflection_VS_metadata | PASS | 0x00000000 | input/output signature |
| arm64 | d3dcompiler_47 | reflection_CS_metadata | PASS | 0x00000000 | UAV binding metadata |
| arm64 | d3dcompiler_47 | signature_blob | PASS | 0x00000000 | input signature part |
| arm64 | d3d11 | DXBC_consumption | SKIP | 0x00000001 | consumer lane disabled for this architecture |
| arm64 | d3d12 | DXBC_consumption | SKIP | 0x00000001 | consumer lane disabled for this architecture |
| arm64 | d3dcompiler_43.dll | LoadLibrary | PASS | 0x00000000 | builtin/runtime DLL loaded |
| arm64 | d3dcompiler_43.dll | D3DCompile | PASS | 0x00000000 | cs_5_0 |
| arm64 | d3dcompiler_43.dll | legacy_reflection_compile | PASS | 0x00000000 | version-local vs_4_0 DXBC |
| arm64 | d3dcompiler_43.dll | D3DCompile2 | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| arm64 | d3dcompiler_43.dll | D3DPreprocess | PASS | 0x00000000 | simple source |
| arm64 | d3dcompiler_43.dll | D3DDisassemble | PASS | 0x00000000 | DXBC |
| arm64 | d3dcompiler_43.dll | D3DReflect | KNOWN_LIMITATION | 0x80004002 | Wine d3dcompiler_43 rejects this reflection interface |
| arm64 | d3dcompiler_43.dll | D3DCompileFromFile | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| arm64 | d3dcompiler_43.dll | D3DReadFileToBlob | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| arm64 | d3dcompiler_43.dll | D3DLoadModule | EXPECTED_MISSING | 0x00000001 | not exported by this DLL |
| arm64 | d3dcompiler_43.dll | D3DSetBlobPart | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| arm64 | d3dcompiler_43.dll | D3DCompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_43.dll | D3DDecompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_43.dll | D3DDisassemble10Effect | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_43.dll | D3DDisassemble11Trace | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| arm64 | d3dcompiler_43.dll | D3DDisassembleRegion | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| arm64 | d3dcompiler_43.dll | D3DGetTraceInstructionOffsets | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| arm64 | d3dcompiler_43.dll | D3DReflectLibrary | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| arm64 | d3dcompiler_43.dll | D3DReturnFailure1 | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_43.dll | DebugSetMute | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_43.dll | D3DCreateFunctionLinkingGraph | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| arm64 | d3dcompiler_43.dll | D3DCreateLinker | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| arm64 | d3dcompiler_46.dll | LoadLibrary | PASS | 0x00000000 | builtin/runtime DLL loaded |
| arm64 | d3dcompiler_46.dll | D3DCompile | PASS | 0x00000000 | cs_5_0 |
| arm64 | d3dcompiler_46.dll | D3DCompile2 | PASS | 0x00000000 | cs_5_0 no secondary data |
| arm64 | d3dcompiler_46.dll | D3DPreprocess | PASS | 0x00000000 | simple source |
| arm64 | d3dcompiler_46.dll | D3DDisassemble | PASS | 0x00000000 | DXBC |
| arm64 | d3dcompiler_46.dll | D3DReflect | PASS | 0x00000000 | DXBC metadata |
| arm64 | d3dcompiler_46.dll | D3DCompileFromFile | PASS | 0x00000000 | Unicode path |
| arm64 | d3dcompiler_46.dll | D3DReadFileToBlob | PASS | 0x00000000 | Unicode path |
| arm64 | d3dcompiler_46.dll | D3DLoadModule | EXPECTED_MISSING | 0x00000001 | not exported by this DLL |
| arm64 | d3dcompiler_46.dll | D3DSetBlobPart | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec stub raises unimplemented-function exception |
| arm64 | d3dcompiler_46.dll | D3DCompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_46.dll | D3DDecompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_46.dll | D3DDisassemble10Effect | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_46.dll | D3DDisassemble11Trace | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_46.dll | D3DDisassembleRegion | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_46.dll | D3DGetTraceInstructionOffsets | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_46.dll | D3DReflectLibrary | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| arm64 | d3dcompiler_46.dll | D3DReturnFailure1 | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_46.dll | DebugSetMute | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_46.dll | D3DCreateFunctionLinkingGraph | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| arm64 | d3dcompiler_46.dll | D3DCreateLinker | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| arm64 | d3dcompiler_47.dll | LoadLibrary | PASS | 0x00000000 | builtin/runtime DLL loaded |
| arm64 | d3dcompiler_47.dll | D3DCompile | PASS | 0x00000000 | cs_5_0 |
| arm64 | d3dcompiler_47.dll | D3DCompile2 | PASS | 0x00000000 | cs_5_0 no secondary data |
| arm64 | d3dcompiler_47.dll | D3DPreprocess | PASS | 0x00000000 | simple source |
| arm64 | d3dcompiler_47.dll | D3DDisassemble | PASS | 0x00000000 | DXBC |
| arm64 | d3dcompiler_47.dll | D3DReflect | PASS | 0x00000000 | DXBC metadata |
| arm64 | d3dcompiler_47.dll | D3DCompileFromFile | PASS | 0x00000000 | Unicode path |
| arm64 | d3dcompiler_47.dll | D3DReadFileToBlob | PASS | 0x00000000 | Unicode path |
| arm64 | d3dcompiler_47.dll | D3DLoadModule | KNOWN_STUB | 0x80004001 | Wine source documents E_NOTIMPL |
| arm64 | d3dcompiler_47.dll | D3DSetBlobPart | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec stub raises unimplemented-function exception |
| arm64 | d3dcompiler_47.dll | D3DCompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_47.dll | D3DDecompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_47.dll | D3DDisassemble10Effect | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_47.dll | D3DDisassemble11Trace | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_47.dll | D3DDisassembleRegion | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_47.dll | D3DGetTraceInstructionOffsets | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_47.dll | D3DReflectLibrary | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_47.dll | D3DReturnFailure1 | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_47.dll | DebugSetMute | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64 | d3dcompiler_47.dll | D3DCreateFunctionLinkingGraph | PASS | 0x00000000 | API availability |
| arm64 | d3dcompiler_47.dll | D3DCreateLinker | PASS | 0x00000000 | API availability |
| arm64ec | d3dcompiler_47 | VS_compile | PASS | 0x00000000 | vs_5_0 macros include flags |
| arm64ec | d3dcompiler_47 | PS_compile | PASS | 0x00000000 | ps_5_0 |
| arm64ec | d3dcompiler_47 | CS_compile | PASS | 0x00000000 | cs_5_0 DXBC producer |
| arm64ec | d3dcompiler_47 | include_handler | PASS | 0x00000000 | Open/Close local include |
| arm64ec | d3dcompiler_47 | preprocess | PASS | 0x00000000 | macros include expansion |
| arm64ec | d3dcompiler_47 | compile_failure_diagnostics | PASS | 0x80004005 | invalid HLSL returns diagnostic blob |
| arm64ec | d3dcompiler_47 | compile_from_file_unicode | PASS | 0x00000000 | UTF-16 path |
| arm64ec | d3dcompiler_47 | read_file_blob | PASS | 0x00000000 | UTF-16 path |
| arm64ec | d3dcompiler_47 | disassembly | PASS | 0x00000000 | DXBC disassembly blob |
| arm64ec | d3dcompiler_47 | legacy_reflection_fixture | PASS | 0x00000000 | vs_4_0 fixture for d3dcompiler_43 |
| arm64ec | d3dcompiler_47 | reflection_VS_metadata | PASS | 0x00000000 | input/output signature |
| arm64ec | d3dcompiler_47 | reflection_CS_metadata | PASS | 0x00000000 | UAV binding metadata |
| arm64ec | d3dcompiler_47 | signature_blob | PASS | 0x00000000 | input signature part |
| arm64ec | d3d11 | DXBC_consumption | SKIP | 0x00000001 | consumer lane disabled for this architecture |
| arm64ec | d3d12 | DXBC_consumption | SKIP | 0x00000001 | consumer lane disabled for this architecture |
| arm64ec | d3dcompiler_43.dll | LoadLibrary | PASS | 0x00000000 | builtin/runtime DLL loaded |
| arm64ec | d3dcompiler_43.dll | D3DCompile | PASS | 0x00000000 | cs_5_0 |
| arm64ec | d3dcompiler_43.dll | legacy_reflection_compile | PASS | 0x00000000 | version-local vs_4_0 DXBC |
| arm64ec | d3dcompiler_43.dll | D3DCompile2 | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| arm64ec | d3dcompiler_43.dll | D3DPreprocess | PASS | 0x00000000 | simple source |
| arm64ec | d3dcompiler_43.dll | D3DDisassemble | PASS | 0x00000000 | DXBC |
| arm64ec | d3dcompiler_43.dll | D3DReflect | KNOWN_LIMITATION | 0x80004002 | Wine d3dcompiler_43 rejects this reflection interface |
| arm64ec | d3dcompiler_43.dll | D3DCompileFromFile | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| arm64ec | d3dcompiler_43.dll | D3DReadFileToBlob | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| arm64ec | d3dcompiler_43.dll | D3DLoadModule | EXPECTED_MISSING | 0x00000001 | not exported by this DLL |
| arm64ec | d3dcompiler_43.dll | D3DSetBlobPart | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| arm64ec | d3dcompiler_43.dll | D3DCompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_43.dll | D3DDecompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_43.dll | D3DDisassemble10Effect | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_43.dll | D3DDisassemble11Trace | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| arm64ec | d3dcompiler_43.dll | D3DDisassembleRegion | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| arm64ec | d3dcompiler_43.dll | D3DGetTraceInstructionOffsets | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| arm64ec | d3dcompiler_43.dll | D3DReflectLibrary | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| arm64ec | d3dcompiler_43.dll | D3DReturnFailure1 | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_43.dll | DebugSetMute | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_43.dll | D3DCreateFunctionLinkingGraph | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| arm64ec | d3dcompiler_43.dll | D3DCreateLinker | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| arm64ec | d3dcompiler_46.dll | LoadLibrary | PASS | 0x00000000 | builtin/runtime DLL loaded |
| arm64ec | d3dcompiler_46.dll | D3DCompile | PASS | 0x00000000 | cs_5_0 |
| arm64ec | d3dcompiler_46.dll | D3DCompile2 | PASS | 0x00000000 | cs_5_0 no secondary data |
| arm64ec | d3dcompiler_46.dll | D3DPreprocess | PASS | 0x00000000 | simple source |
| arm64ec | d3dcompiler_46.dll | D3DDisassemble | PASS | 0x00000000 | DXBC |
| arm64ec | d3dcompiler_46.dll | D3DReflect | PASS | 0x00000000 | DXBC metadata |
| arm64ec | d3dcompiler_46.dll | D3DCompileFromFile | PASS | 0x00000000 | Unicode path |
| arm64ec | d3dcompiler_46.dll | D3DReadFileToBlob | PASS | 0x00000000 | Unicode path |
| arm64ec | d3dcompiler_46.dll | D3DLoadModule | EXPECTED_MISSING | 0x00000001 | not exported by this DLL |
| arm64ec | d3dcompiler_46.dll | D3DSetBlobPart | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec stub raises unimplemented-function exception |
| arm64ec | d3dcompiler_46.dll | D3DCompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_46.dll | D3DDecompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_46.dll | D3DDisassemble10Effect | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_46.dll | D3DDisassemble11Trace | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_46.dll | D3DDisassembleRegion | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_46.dll | D3DGetTraceInstructionOffsets | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_46.dll | D3DReflectLibrary | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| arm64ec | d3dcompiler_46.dll | D3DReturnFailure1 | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_46.dll | DebugSetMute | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_46.dll | D3DCreateFunctionLinkingGraph | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| arm64ec | d3dcompiler_46.dll | D3DCreateLinker | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| arm64ec | d3dcompiler_47.dll | LoadLibrary | PASS | 0x00000000 | builtin/runtime DLL loaded |
| arm64ec | d3dcompiler_47.dll | D3DCompile | PASS | 0x00000000 | cs_5_0 |
| arm64ec | d3dcompiler_47.dll | D3DCompile2 | PASS | 0x00000000 | cs_5_0 no secondary data |
| arm64ec | d3dcompiler_47.dll | D3DPreprocess | PASS | 0x00000000 | simple source |
| arm64ec | d3dcompiler_47.dll | D3DDisassemble | PASS | 0x00000000 | DXBC |
| arm64ec | d3dcompiler_47.dll | D3DReflect | PASS | 0x00000000 | DXBC metadata |
| arm64ec | d3dcompiler_47.dll | D3DCompileFromFile | PASS | 0x00000000 | Unicode path |
| arm64ec | d3dcompiler_47.dll | D3DReadFileToBlob | PASS | 0x00000000 | Unicode path |
| arm64ec | d3dcompiler_47.dll | D3DLoadModule | KNOWN_STUB | 0x80004001 | Wine source documents E_NOTIMPL |
| arm64ec | d3dcompiler_47.dll | D3DSetBlobPart | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec stub raises unimplemented-function exception |
| arm64ec | d3dcompiler_47.dll | D3DCompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_47.dll | D3DDecompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_47.dll | D3DDisassemble10Effect | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_47.dll | D3DDisassemble11Trace | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_47.dll | D3DDisassembleRegion | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_47.dll | D3DGetTraceInstructionOffsets | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_47.dll | D3DReflectLibrary | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_47.dll | D3DReturnFailure1 | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_47.dll | DebugSetMute | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| arm64ec | d3dcompiler_47.dll | D3DCreateFunctionLinkingGraph | PASS | 0x00000000 | API availability |
| arm64ec | d3dcompiler_47.dll | D3DCreateLinker | PASS | 0x00000000 | API availability |
| x86_64 | d3dcompiler_47 | VS_compile | PASS | 0x00000000 | vs_5_0 macros include flags |
| x86_64 | d3dcompiler_47 | PS_compile | PASS | 0x00000000 | ps_5_0 |
| x86_64 | d3dcompiler_47 | CS_compile | PASS | 0x00000000 | cs_5_0 DXBC producer |
| x86_64 | d3dcompiler_47 | include_handler | PASS | 0x00000000 | Open/Close local include |
| x86_64 | d3dcompiler_47 | preprocess | PASS | 0x00000000 | macros include expansion |
| x86_64 | d3dcompiler_47 | compile_failure_diagnostics | PASS | 0x80004005 | invalid HLSL returns diagnostic blob |
| x86_64 | d3dcompiler_47 | compile_from_file_unicode | PASS | 0x00000000 | UTF-16 path |
| x86_64 | d3dcompiler_47 | read_file_blob | PASS | 0x00000000 | UTF-16 path |
| x86_64 | d3dcompiler_47 | disassembly | PASS | 0x00000000 | DXBC disassembly blob |
| x86_64 | d3dcompiler_47 | legacy_reflection_fixture | PASS | 0x00000000 | vs_4_0 fixture for d3dcompiler_43 |
| x86_64 | d3dcompiler_47 | reflection_VS_metadata | PASS | 0x00000000 | input/output signature |
| x86_64 | d3dcompiler_47 | reflection_CS_metadata | PASS | 0x00000000 | UAV binding metadata |
| x86_64 | d3dcompiler_47 | signature_blob | PASS | 0x00000000 | input signature part |
| x86_64 | d3d11 | DXBC_consumption | SKIP | 0x00000001 | consumer lane disabled for this architecture |
| x86_64 | d3d12 | DXBC_consumption | SKIP | 0x00000001 | consumer lane disabled for this architecture |
| x86_64 | d3dcompiler_43.dll | LoadLibrary | PASS | 0x00000000 | builtin/runtime DLL loaded |
| x86_64 | d3dcompiler_43.dll | D3DCompile | PASS | 0x00000000 | cs_5_0 |
| x86_64 | d3dcompiler_43.dll | legacy_reflection_compile | PASS | 0x00000000 | version-local vs_4_0 DXBC |
| x86_64 | d3dcompiler_43.dll | D3DCompile2 | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| x86_64 | d3dcompiler_43.dll | D3DPreprocess | PASS | 0x00000000 | simple source |
| x86_64 | d3dcompiler_43.dll | D3DDisassemble | PASS | 0x00000000 | DXBC |
| x86_64 | d3dcompiler_43.dll | D3DReflect | KNOWN_LIMITATION | 0x80004002 | Wine d3dcompiler_43 rejects this reflection interface |
| x86_64 | d3dcompiler_43.dll | D3DCompileFromFile | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| x86_64 | d3dcompiler_43.dll | D3DReadFileToBlob | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| x86_64 | d3dcompiler_43.dll | D3DLoadModule | EXPECTED_MISSING | 0x00000001 | not exported by this DLL |
| x86_64 | d3dcompiler_43.dll | D3DSetBlobPart | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| x86_64 | d3dcompiler_43.dll | D3DCompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_43.dll | D3DDecompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_43.dll | D3DDisassemble10Effect | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_43.dll | D3DDisassemble11Trace | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| x86_64 | d3dcompiler_43.dll | D3DDisassembleRegion | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| x86_64 | d3dcompiler_43.dll | D3DGetTraceInstructionOffsets | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| x86_64 | d3dcompiler_43.dll | D3DReflectLibrary | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| x86_64 | d3dcompiler_43.dll | D3DReturnFailure1 | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_43.dll | DebugSetMute | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_43.dll | D3DCreateFunctionLinkingGraph | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| x86_64 | d3dcompiler_43.dll | D3DCreateLinker | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| x86_64 | d3dcompiler_46.dll | LoadLibrary | PASS | 0x00000000 | builtin/runtime DLL loaded |
| x86_64 | d3dcompiler_46.dll | D3DCompile | PASS | 0x00000000 | cs_5_0 |
| x86_64 | d3dcompiler_46.dll | D3DCompile2 | PASS | 0x00000000 | cs_5_0 no secondary data |
| x86_64 | d3dcompiler_46.dll | D3DPreprocess | PASS | 0x00000000 | simple source |
| x86_64 | d3dcompiler_46.dll | D3DDisassemble | PASS | 0x00000000 | DXBC |
| x86_64 | d3dcompiler_46.dll | D3DReflect | PASS | 0x00000000 | DXBC metadata |
| x86_64 | d3dcompiler_46.dll | D3DCompileFromFile | PASS | 0x00000000 | Unicode path |
| x86_64 | d3dcompiler_46.dll | D3DReadFileToBlob | PASS | 0x00000000 | Unicode path |
| x86_64 | d3dcompiler_46.dll | D3DLoadModule | EXPECTED_MISSING | 0x00000001 | not exported by this DLL |
| x86_64 | d3dcompiler_46.dll | D3DSetBlobPart | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec stub raises unimplemented-function exception |
| x86_64 | d3dcompiler_46.dll | D3DCompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_46.dll | D3DDecompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_46.dll | D3DDisassemble10Effect | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_46.dll | D3DDisassemble11Trace | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_46.dll | D3DDisassembleRegion | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_46.dll | D3DGetTraceInstructionOffsets | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_46.dll | D3DReflectLibrary | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| x86_64 | d3dcompiler_46.dll | D3DReturnFailure1 | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_46.dll | DebugSetMute | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_46.dll | D3DCreateFunctionLinkingGraph | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| x86_64 | d3dcompiler_46.dll | D3DCreateLinker | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| x86_64 | d3dcompiler_47.dll | LoadLibrary | PASS | 0x00000000 | builtin/runtime DLL loaded |
| x86_64 | d3dcompiler_47.dll | D3DCompile | PASS | 0x00000000 | cs_5_0 |
| x86_64 | d3dcompiler_47.dll | D3DCompile2 | PASS | 0x00000000 | cs_5_0 no secondary data |
| x86_64 | d3dcompiler_47.dll | D3DPreprocess | PASS | 0x00000000 | simple source |
| x86_64 | d3dcompiler_47.dll | D3DDisassemble | PASS | 0x00000000 | DXBC |
| x86_64 | d3dcompiler_47.dll | D3DReflect | PASS | 0x00000000 | DXBC metadata |
| x86_64 | d3dcompiler_47.dll | D3DCompileFromFile | PASS | 0x00000000 | Unicode path |
| x86_64 | d3dcompiler_47.dll | D3DReadFileToBlob | PASS | 0x00000000 | Unicode path |
| x86_64 | d3dcompiler_47.dll | D3DLoadModule | KNOWN_STUB | 0x80004001 | Wine source documents E_NOTIMPL |
| x86_64 | d3dcompiler_47.dll | D3DSetBlobPart | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec stub raises unimplemented-function exception |
| x86_64 | d3dcompiler_47.dll | D3DCompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_47.dll | D3DDecompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_47.dll | D3DDisassemble10Effect | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_47.dll | D3DDisassemble11Trace | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_47.dll | D3DDisassembleRegion | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_47.dll | D3DGetTraceInstructionOffsets | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_47.dll | D3DReflectLibrary | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_47.dll | D3DReturnFailure1 | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_47.dll | DebugSetMute | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| x86_64 | d3dcompiler_47.dll | D3DCreateFunctionLinkingGraph | PASS | 0x00000000 | API availability |
| x86_64 | d3dcompiler_47.dll | D3DCreateLinker | PASS | 0x00000000 | API availability |
| i386 | d3dcompiler_47 | VS_compile | PASS | 0x00000000 | vs_5_0 macros include flags |
| i386 | d3dcompiler_47 | PS_compile | PASS | 0x00000000 | ps_5_0 |
| i386 | d3dcompiler_47 | CS_compile | PASS | 0x00000000 | cs_5_0 DXBC producer |
| i386 | d3dcompiler_47 | include_handler | PASS | 0x00000000 | Open/Close local include |
| i386 | d3dcompiler_47 | preprocess | PASS | 0x00000000 | macros include expansion |
| i386 | d3dcompiler_47 | compile_failure_diagnostics | PASS | 0x80004005 | invalid HLSL returns diagnostic blob |
| i386 | d3dcompiler_47 | compile_from_file_unicode | PASS | 0x00000000 | UTF-16 path |
| i386 | d3dcompiler_47 | read_file_blob | PASS | 0x00000000 | UTF-16 path |
| i386 | d3dcompiler_47 | disassembly | PASS | 0x00000000 | DXBC disassembly blob |
| i386 | d3dcompiler_47 | legacy_reflection_fixture | PASS | 0x00000000 | vs_4_0 fixture for d3dcompiler_43 |
| i386 | d3dcompiler_47 | reflection_VS_metadata | PASS | 0x00000000 | input/output signature |
| i386 | d3dcompiler_47 | reflection_CS_metadata | PASS | 0x00000000 | UAV binding metadata |
| i386 | d3dcompiler_47 | signature_blob | PASS | 0x00000000 | input signature part |
| i386 | d3dcompiler_43.dll | LoadLibrary | PASS | 0x00000000 | builtin/runtime DLL loaded |
| i386 | d3dcompiler_43.dll | D3DCompile | PASS | 0x00000000 | cs_5_0 |
| i386 | d3dcompiler_43.dll | legacy_reflection_compile | PASS | 0x00000000 | version-local vs_4_0 DXBC |
| i386 | d3dcompiler_43.dll | D3DCompile2 | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| i386 | d3dcompiler_43.dll | D3DPreprocess | PASS | 0x00000000 | simple source |
| i386 | d3dcompiler_43.dll | D3DDisassemble | PASS | 0x00000000 | DXBC |
| i386 | d3dcompiler_43.dll | D3DReflect | KNOWN_LIMITATION | 0x80004002 | Wine d3dcompiler_43 rejects this reflection interface |
| i386 | d3dcompiler_43.dll | D3DCompileFromFile | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| i386 | d3dcompiler_43.dll | D3DReadFileToBlob | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| i386 | d3dcompiler_43.dll | D3DLoadModule | EXPECTED_MISSING | 0x00000001 | not exported by this DLL |
| i386 | d3dcompiler_43.dll | D3DSetBlobPart | EXPECTED_MISSING | 0x00000001 | not exported by 43 |
| i386 | d3dcompiler_43.dll | D3DCompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_43.dll | D3DDecompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_43.dll | D3DDisassemble10Effect | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_43.dll | D3DDisassemble11Trace | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| i386 | d3dcompiler_43.dll | D3DDisassembleRegion | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| i386 | d3dcompiler_43.dll | D3DGetTraceInstructionOffsets | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| i386 | d3dcompiler_43.dll | D3DReflectLibrary | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| i386 | d3dcompiler_43.dll | D3DReturnFailure1 | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_43.dll | DebugSetMute | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_43.dll | D3DCreateFunctionLinkingGraph | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| i386 | d3dcompiler_43.dll | D3DCreateLinker | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| i386 | d3dcompiler_46.dll | LoadLibrary | PASS | 0x00000000 | builtin/runtime DLL loaded |
| i386 | d3dcompiler_46.dll | D3DCompile | PASS | 0x00000000 | cs_5_0 |
| i386 | d3dcompiler_46.dll | D3DCompile2 | PASS | 0x00000000 | cs_5_0 no secondary data |
| i386 | d3dcompiler_46.dll | D3DPreprocess | PASS | 0x00000000 | simple source |
| i386 | d3dcompiler_46.dll | D3DDisassemble | PASS | 0x00000000 | DXBC |
| i386 | d3dcompiler_46.dll | D3DReflect | PASS | 0x00000000 | DXBC metadata |
| i386 | d3dcompiler_46.dll | D3DCompileFromFile | PASS | 0x00000000 | Unicode path |
| i386 | d3dcompiler_46.dll | D3DReadFileToBlob | PASS | 0x00000000 | Unicode path |
| i386 | d3dcompiler_46.dll | D3DLoadModule | EXPECTED_MISSING | 0x00000001 | not exported by this DLL |
| i386 | d3dcompiler_46.dll | D3DSetBlobPart | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec stub raises unimplemented-function exception |
| i386 | d3dcompiler_46.dll | D3DCompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_46.dll | D3DDecompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_46.dll | D3DDisassemble10Effect | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_46.dll | D3DDisassemble11Trace | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_46.dll | D3DDisassembleRegion | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_46.dll | D3DGetTraceInstructionOffsets | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_46.dll | D3DReflectLibrary | EXPECTED_MISSING | 0x00000001 | export is not present in this version |
| i386 | d3dcompiler_46.dll | D3DReturnFailure1 | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_46.dll | DebugSetMute | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_46.dll | D3DCreateFunctionLinkingGraph | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| i386 | d3dcompiler_46.dll | D3DCreateLinker | EXPECTED_MISSING | 0x00000001 | not exported by 46 |
| i386 | d3dcompiler_47.dll | LoadLibrary | PASS | 0x00000000 | builtin/runtime DLL loaded |
| i386 | d3dcompiler_47.dll | D3DCompile | PASS | 0x00000000 | cs_5_0 |
| i386 | d3dcompiler_47.dll | D3DCompile2 | PASS | 0x00000000 | cs_5_0 no secondary data |
| i386 | d3dcompiler_47.dll | D3DPreprocess | PASS | 0x00000000 | simple source |
| i386 | d3dcompiler_47.dll | D3DDisassemble | PASS | 0x00000000 | DXBC |
| i386 | d3dcompiler_47.dll | D3DReflect | PASS | 0x00000000 | DXBC metadata |
| i386 | d3dcompiler_47.dll | D3DCompileFromFile | PASS | 0x00000000 | Unicode path |
| i386 | d3dcompiler_47.dll | D3DReadFileToBlob | PASS | 0x00000000 | Unicode path |
| i386 | d3dcompiler_47.dll | D3DLoadModule | KNOWN_STUB | 0x80004001 | Wine source documents E_NOTIMPL |
| i386 | d3dcompiler_47.dll | D3DSetBlobPart | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec stub raises unimplemented-function exception |
| i386 | d3dcompiler_47.dll | D3DCompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_47.dll | D3DDecompressShaders | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_47.dll | D3DDisassemble10Effect | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_47.dll | D3DDisassemble11Trace | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_47.dll | D3DDisassembleRegion | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_47.dll | D3DGetTraceInstructionOffsets | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_47.dll | D3DReflectLibrary | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_47.dll | D3DReturnFailure1 | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_47.dll | DebugSetMute | KNOWN_STUB_NOT_CALLED | 0x80004001 | Wine spec @stub; not called because it may abort the guest |
| i386 | d3dcompiler_47.dll | D3DCreateFunctionLinkingGraph | PASS | 0x00000000 | API availability |
| i386 | d3dcompiler_47.dll | D3DCreateLinker | PASS | 0x00000000 | API availability |
| i386 | d3d11 | DXBC_compute_readback | PASS | 0x00000000 | generated cs_5_0 |
| i386 | d3d12 | DXBC_compute_pipeline | PASS | 0x00000000 | generated cs_5_0 |

## Known boundaries

- `d3dcompiler_43!D3DReflect` is recorded as `KNOWN_LIMITATION` with observed `E_NOINTERFACE`; it is not counted as a pass.
- `D3DLoadModule` is safely called on 47 and recorded as `KNOWN_STUB` / `E_NOTIMPL`.
- `D3DSetBlobPart` is a Wine spec stub and is intentionally not called because it raises an unimplemented-function exception; the table records `KNOWN_STUB_NOT_CALLED` / `E_NOTIMPL`.
- `D3DCompressShaders`, `D3DDecompressShaders`, trace/effect helpers, and `D3DReflectLibrary` remain source-declared stubs and are not reported as implemented.
- D3D11 and D3D12 consumers run in separate i386 processes; combining DXVK D3D11 and vkd3d-proton D3D12 in one process currently faults after the D3D11 pass.
- All lanes use FEX TSO settings of zero and do not invoke wineboot.
