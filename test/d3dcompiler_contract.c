/* VKMT D3DCompiler contract: compiler APIs, reflection, version DLLs, and
 * generated-DXBC consumers.  Every capability is printed explicitly so a
 * Wine stub is visible instead of being mistaken for a pass. */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <d3d11.h>
#include <d3d12.h>
#include <d3dcompiler.h>
#include <stdio.h>
#include <string.h>

#if defined(__arm64ec__) || defined(_M_ARM64EC)
# define VKMT_ARCH "arm64ec"
#elif defined(__aarch64__) || defined(_M_ARM64)
# define VKMT_ARCH "arm64"
#elif defined(__i386__) || defined(_M_IX86)
# define VKMT_ARCH "i386"
#elif defined(__x86_64__) || defined(_M_X64)
# define VKMT_ARCH "x86_64"
#else
# define VKMT_ARCH "unknown"
#endif

#define ARRAY_SIZE(x) (sizeof(x) / sizeof((x)[0]))

static unsigned int failures;

static void capability(const char *dll, const char *api, const char *status,
        HRESULT hr, const char *detail)
{
    printf("D3DCOMPILER_CAP\t%s\t%s\t%s\t%s\t0x%08lx\t%s\n", VKMT_ARCH,
            dll, api, status, (unsigned long)hr, detail ? detail : "-");
}

static void require_result(const char *api, HRESULT hr)
{
    if (FAILED(hr))
    {
        fprintf(stderr, "D3DCOMPILER_REQUIRED_FAIL api=%s hr=0x%08lx\n",
                api, (unsigned long)hr);
        ++failures;
    }
}

static void release_blob(ID3DBlob **blob)
{
    if (*blob) ID3D10Blob_Release(*blob);
    *blob = NULL;
}

static int blob_contains(ID3DBlob *blob, const char *needle)
{
    const char *data;
    SIZE_T size, needle_size = strlen(needle);
    SIZE_T i;

    if (!blob) return 0;
    data = ID3D10Blob_GetBufferPointer(blob);
    size = ID3D10Blob_GetBufferSize(blob);
    if (needle_size > size) return 0;
    for (i = 0; i <= size - needle_size; ++i)
        if (!memcmp(data + i, needle, needle_size)) return 1;
    return 0;
}

struct include_fixture
{
    ID3DInclude iface;
    unsigned int opens;
    unsigned int closes;
};

static const char include_text[] =
    "#define VKMT_INCLUDED_SCALE 2.0\n"
    "#define VKMT_INCLUDED_MARKER 1\n";

static HRESULT WINAPI include_open(ID3DInclude *iface, D3D_INCLUDE_TYPE type,
        const char *filename, const void *parent, const void **data, UINT *bytes)
{
    struct include_fixture *fixture = CONTAINING_RECORD(iface, struct include_fixture, iface);
    (void)parent;
    if (type != D3D_INCLUDE_LOCAL || strcmp(filename, "vkmt_contract.inc")) return E_FAIL;
    ++fixture->opens;
    *data = include_text;
    *bytes = sizeof(include_text) - 1;
    return S_OK;
}

static HRESULT WINAPI include_close(ID3DInclude *iface, const void *data)
{
    struct include_fixture *fixture = CONTAINING_RECORD(iface, struct include_fixture, iface);
    if (data != include_text) return E_FAIL;
    ++fixture->closes;
    return S_OK;
}

static ID3DIncludeVtbl include_vtbl =
{
    include_open,
    include_close,
};

static const char vs_source[] =
    "#include \"vkmt_contract.inc\"\n"
    "struct VSIn { float4 pos : POSITION; float4 color : COLOR0; };\n"
    "struct VSOut { float4 pos : SV_POSITION; float4 color : COLOR0; };\n"
    "VSOut main(VSIn input) { VSOut output; output.pos = input.pos; "
    "output.color = input.color * VKMT_INCLUDED_SCALE; return output; }\n";

static const char ps_source[] =
    "float4 main(float4 color : COLOR0) : SV_TARGET { return color; }\n";

static const char cs_source[] =
    "RWStructuredBuffer<uint> output : register(u0);\n"
    "[numthreads(1,1,1)] void main() { output[0] = 0x44434343; }\n";

static const char d3d12_cs_source[] =
    "[numthreads(1,1,1)] void main() { }\n";

/* d3dcompiler_43 predates the RDEF forms used by newer compute shaders.  A
 * shader-model-4 vertex shader is the portable reflection fixture for that
 * version; 46/47 additionally exercise the compute-resource metadata above. */
static const char legacy_vs_source[] =
    "float4 main(float4 pos : POSITION) : SV_POSITION { return pos; }\n";

static HRESULT compile_shader(const char *source, SIZE_T size, const char *name,
        const D3D_SHADER_MACRO *macros, ID3DInclude *include, const char *entry,
        const char *profile, UINT flags, ID3DBlob **shader, ID3DBlob **errors)
{
    return D3DCompile(source, size, name, macros, include, entry, profile,
            flags, 0, shader, errors);
}

static void test_compile_and_frontend(ID3DBlob **vs_blob, ID3DBlob **ps_blob,
        ID3DBlob **cs_blob, WCHAR *shader_file)
{
    static const D3D_SHADER_MACRO macros[] =
    {
        { "VKMT_CONTRACT_MACRO", "1" },
        { NULL, NULL },
    };
    static const char preprocess_source[] =
        "#include \"vkmt_contract.inc\"\n"
        "#if VKMT_CONTRACT_MACRO\n"
        "float4 vkmt_value = float4(VKMT_INCLUDED_SCALE, 0, 0, 1);\n"
        "#endif\n";
    struct include_fixture fixture;
    ID3DBlob *errors = NULL, *preprocessed = NULL, *disassembly = NULL;
    ID3DBlob *file_blob = NULL, *file_read = NULL, *bad_errors = NULL;
    HRESULT hr;
    HANDLE file;
    DWORD written;
    const char file_source[] =
        "RWStructuredBuffer<uint> output : register(u0);\n"
        "[numthreads(1,1,1)] void main() { output[0] = 0x46494c45; }\n";
    const char invalid_source[] = "float4 main( { this is not valid HLSL";

    memset(&fixture, 0, sizeof(fixture));
    fixture.iface.lpVtbl = &include_vtbl;

    hr = compile_shader(vs_source, sizeof(vs_source) - 1, "vkmt_vs.hlsl",
            macros, &fixture.iface, "main", "vs_5_0",
            D3DCOMPILE_DEBUG | D3DCOMPILE_ENABLE_STRICTNESS |
            D3DCOMPILE_OPTIMIZATION_LEVEL3, vs_blob, &errors);
    require_result("D3DCompile.VS", hr);
    if (errors) release_blob(&errors);
    capability("d3dcompiler_47", "VS_compile", SUCCEEDED(hr) ? "PASS" : "FAIL",
            hr, "vs_5_0 macros include flags");

    hr = compile_shader(ps_source, sizeof(ps_source) - 1, "vkmt_ps.hlsl", NULL,
            NULL, "main", "ps_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL2,
            ps_blob, &errors);
    require_result("D3DCompile.PS", hr);
    if (errors) release_blob(&errors);
    capability("d3dcompiler_47", "PS_compile", SUCCEEDED(hr) ? "PASS" : "FAIL",
            hr, "ps_5_0");

    hr = compile_shader(cs_source, sizeof(cs_source) - 1, "vkmt_cs.hlsl", NULL,
            NULL, "main", "cs_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL3,
            cs_blob, &errors);
    require_result("D3DCompile.CS", hr);
    if (errors) release_blob(&errors);
    capability("d3dcompiler_47", "CS_compile", SUCCEEDED(hr) ? "PASS" : "FAIL",
            hr, "cs_5_0 DXBC producer");

    if (fixture.opens != 1 || fixture.closes != 1)
    {
        fprintf(stderr, "include handler count open=%u close=%u\n", fixture.opens, fixture.closes);
        ++failures;
    }
    capability("d3dcompiler_47", "include_handler", fixture.opens == 1 && fixture.closes == 1 ?
            "PASS" : "FAIL", S_OK, "Open/Close local include");

    hr = D3DPreprocess(preprocess_source, sizeof(preprocess_source) - 1,
            "vkmt_preprocess.hlsl", macros, &fixture.iface, &preprocessed, &errors);
    require_result("D3DPreprocess", hr);
    if (SUCCEEDED(hr) && !blob_contains(preprocessed, "2.0")) ++failures;
    capability("d3dcompiler_47", "preprocess", SUCCEEDED(hr) ? "PASS" : "FAIL",
            hr, "macros include expansion");
    if (errors) release_blob(&errors);
    release_blob(&preprocessed);

    hr = D3DCompile(invalid_source, sizeof(invalid_source) - 1, "vkmt_bad.hlsl",
            NULL, NULL, "main", "vs_5_0", 0, 0, NULL, &bad_errors);
    if (SUCCEEDED(hr) || !bad_errors || !ID3D10Blob_GetBufferSize(bad_errors)) ++failures;
    capability("d3dcompiler_47", "compile_failure_diagnostics",
            FAILED(hr) && bad_errors && ID3D10Blob_GetBufferSize(bad_errors) ? "PASS" : "FAIL",
            hr, "invalid HLSL returns diagnostic blob");
    release_blob(&bad_errors);

    file = CreateFileW(shader_file, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
            FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE || !WriteFile(file, file_source,
            sizeof(file_source) - 1, &written, NULL) || written != sizeof(file_source) - 1)
    {
        fprintf(stderr, "unable to write Unicode shader file error=%lu\n", GetLastError());
        ++failures;
    }
    if (file != INVALID_HANDLE_VALUE) CloseHandle(file);

    hr = D3DCompileFromFile(shader_file, NULL, D3D_COMPILE_STANDARD_FILE_INCLUDE,
            "main", "cs_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &file_blob, &errors);
    require_result("D3DCompileFromFile", hr);
    capability("d3dcompiler_47", "compile_from_file_unicode",
            SUCCEEDED(hr) ? "PASS" : "FAIL", hr, "UTF-16 path");
    if (errors) release_blob(&errors);

    hr = D3DReadFileToBlob(shader_file, &file_read);
    require_result("D3DReadFileToBlob", hr);
    capability("d3dcompiler_47", "read_file_blob",
            SUCCEEDED(hr) ? "PASS" : "FAIL", hr, "UTF-16 path");

    if (*cs_blob)
    {
        hr = D3DDisassemble(ID3D10Blob_GetBufferPointer(*cs_blob),
                ID3D10Blob_GetBufferSize(*cs_blob),
                D3D_DISASM_ENABLE_INSTRUCTION_NUMBERING, "VKMT D3DCompiler", &disassembly);
        require_result("D3DDisassemble", hr);
        capability("d3dcompiler_47", "disassembly",
                SUCCEEDED(hr) && disassembly && ID3D10Blob_GetBufferSize(disassembly) ? "PASS" : "FAIL",
                hr, "DXBC disassembly blob");
    }

    release_blob(&disassembly);
    release_blob(&file_blob);
    release_blob(&file_read);
    if (fixture.opens != fixture.closes)
    {
        fprintf(stderr, "include handler leak open=%u close=%u\n", fixture.opens, fixture.closes);
        ++failures;
    }
}

static void test_reflection(ID3DBlob *vs_blob, ID3DBlob *cs_blob)
{
    ID3D11ShaderReflection *vs_reflection = NULL, *cs_reflection = NULL;
    D3D11_SHADER_DESC vs_desc, cs_desc;
    D3D11_SHADER_INPUT_BIND_DESC binding;
    HRESULT hr;

    memset(&vs_desc, 0, sizeof(vs_desc));
    memset(&cs_desc, 0, sizeof(cs_desc));
    memset(&binding, 0, sizeof(binding));
    hr = D3DReflect(ID3D10Blob_GetBufferPointer(vs_blob), ID3D10Blob_GetBufferSize(vs_blob),
            &IID_ID3D11ShaderReflection, (void **)&vs_reflection);
    if (SUCCEEDED(hr)) hr = vs_reflection->lpVtbl->GetDesc(vs_reflection, &vs_desc);
    if (FAILED(hr) || !vs_desc.InputParameters || !vs_desc.OutputParameters) ++failures;
    capability("d3dcompiler_47", "reflection_VS_metadata",
            SUCCEEDED(hr) && vs_desc.InputParameters && vs_desc.OutputParameters ? "PASS" : "FAIL",
            hr, "input/output signature");
    if (vs_reflection) vs_reflection->lpVtbl->Release(vs_reflection);

    hr = D3DReflect(ID3D10Blob_GetBufferPointer(cs_blob), ID3D10Blob_GetBufferSize(cs_blob),
            &IID_ID3D11ShaderReflection, (void **)&cs_reflection);
    if (SUCCEEDED(hr)) hr = cs_reflection->lpVtbl->GetDesc(cs_reflection, &cs_desc);
    if (SUCCEEDED(hr) && cs_desc.BoundResources)
        hr = cs_reflection->lpVtbl->GetResourceBindingDesc(cs_reflection, 0, &binding);
    if (FAILED(hr) || !cs_desc.BoundResources || binding.Type != D3D_SIT_UAV_RWSTRUCTURED) ++failures;
    capability("d3dcompiler_47", "reflection_CS_metadata",
            SUCCEEDED(hr) && cs_desc.BoundResources && binding.Type == D3D_SIT_UAV_RWSTRUCTURED ? "PASS" : "FAIL",
            hr, "UAV binding metadata");
    if (cs_reflection) cs_reflection->lpVtbl->Release(cs_reflection);

    {
        ID3DBlob *part = NULL;
        hr = D3DGetInputSignatureBlob(ID3D10Blob_GetBufferPointer(vs_blob),
                ID3D10Blob_GetBufferSize(vs_blob), &part);
        capability("d3dcompiler_47", "signature_blob",
                SUCCEEDED(hr) && part ? "PASS" : "FAIL", hr, "input signature part");
        if (FAILED(hr)) ++failures;
        release_blob(&part);
    }
}

static void test_d3d11_consumption(ID3DBlob *cs_blob)
{
    typedef HRESULT (WINAPI *create_device_fn)(IDXGIAdapter *, D3D_DRIVER_TYPE,
            HMODULE, UINT, const D3D_FEATURE_LEVEL *, UINT, UINT, ID3D11Device **,
            D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);
    HMODULE module = LoadLibraryA("d3d11.dll");
    create_device_fn create_device;
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    ID3D11ComputeShader *shader = NULL;
    ID3D11Buffer *output = NULL, *staging = NULL;
    ID3D11UnorderedAccessView *uav = NULL;
    D3D11_BUFFER_DESC desc;
    D3D11_UNORDERED_ACCESS_VIEW_DESC uav_desc;
    D3D11_MAPPED_SUBRESOURCE mapped;
    D3D_FEATURE_LEVEL feature_level;
    HRESULT hr;

    memset(&desc, 0, sizeof(desc));
    memset(&uav_desc, 0, sizeof(uav_desc));
    memset(&mapped, 0, sizeof(mapped));
    if (!module || !(create_device = (create_device_fn)GetProcAddress(module, "D3D11CreateDevice")))
    {
        capability("d3d11", "DXBC_consumption", "SKIP", S_FALSE, "D3D11CreateDevice unavailable");
        if (module) FreeLibrary(module);
        return;
    }
    hr = create_device(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
            D3D11_SDK_VERSION, &device, &feature_level, &context);
    if (FAILED(hr))
    {
        capability("d3d11", "DXBC_consumption", "SKIP", hr, "device unavailable");
        FreeLibrary(module);
        return;
    }
    hr = ID3D11Device_CreateComputeShader(device, ID3D10Blob_GetBufferPointer(cs_blob),
            ID3D10Blob_GetBufferSize(cs_blob), NULL, &shader);
    desc.ByteWidth = sizeof(UINT);
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
    desc.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    desc.StructureByteStride = sizeof(UINT);
    if (SUCCEEDED(hr)) hr = ID3D11Device_CreateBuffer(device, &desc, NULL, &output);
    uav_desc.Format = DXGI_FORMAT_UNKNOWN;
    uav_desc.ViewDimension = D3D11_UAV_DIMENSION_BUFFER;
    uav_desc.Buffer.NumElements = 1;
    if (SUCCEEDED(hr)) hr = ID3D11Device_CreateUnorderedAccessView(device,
            (ID3D11Resource *)output, &uav_desc, &uav);
    if (SUCCEEDED(hr))
    {
        ID3D11DeviceContext_CSSetShader(context, shader, NULL, 0);
        ID3D11DeviceContext_CSSetUnorderedAccessViews(context, 0, 1, &uav, NULL);
        ID3D11DeviceContext_Dispatch(context, 1, 1, 1);
        desc.Usage = D3D11_USAGE_STAGING;
        desc.BindFlags = 0;
        desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        desc.MiscFlags = 0;
        desc.StructureByteStride = 0;
        hr = ID3D11Device_CreateBuffer(device, &desc, NULL, &staging);
    }
    if (SUCCEEDED(hr))
    {
        ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)staging,
                (ID3D11Resource *)output);
        hr = ID3D11DeviceContext_Map(context, (ID3D11Resource *)staging, 0,
                D3D11_MAP_READ, 0, &mapped);
    }
    if (SUCCEEDED(hr))
    {
        if (*(const UINT *)mapped.pData != 0x44434343u) hr = E_FAIL;
        ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)staging, 0);
    }
    capability("d3d11", "DXBC_compute_readback", SUCCEEDED(hr) ? "PASS" : "FAIL",
            hr, "generated cs_5_0");
    if (FAILED(hr)) ++failures;
    if (staging) ID3D11Buffer_Release(staging);
    if (uav) ID3D11UnorderedAccessView_Release(uav);
    if (output) ID3D11Buffer_Release(output);
    if (shader) ID3D11ComputeShader_Release(shader);
    if (context) ID3D11DeviceContext_Release(context);
    if (device) ID3D11Device_Release(device);
    FreeLibrary(module);
}

static void test_d3d12_consumption(void)
{
    typedef HRESULT (WINAPI *create_device_fn)(IUnknown *, D3D_FEATURE_LEVEL,
            REFIID, void **);
    typedef HRESULT (WINAPI *serialize_root_signature_fn)(const D3D12_ROOT_SIGNATURE_DESC *,
            D3D_ROOT_SIGNATURE_VERSION, ID3DBlob **, ID3DBlob **);
    HMODULE module = LoadLibraryA("d3d12.dll");
    create_device_fn create_device;
    serialize_root_signature_fn serialize_root_signature;
    ID3D12Device *device = NULL;
    ID3D12RootSignature *root = NULL;
    ID3D12PipelineState *pipeline = NULL;
    ID3DBlob *signature = NULL, *errors = NULL, *shader = NULL;
    D3D12_ROOT_SIGNATURE_DESC root_desc;
    D3D12_COMPUTE_PIPELINE_STATE_DESC pipeline_desc;
    HRESULT hr;

    hr = D3DCompile(d3d12_cs_source, sizeof(d3d12_cs_source) - 1, "vkmt_d3d12.hlsl",
            NULL, NULL, "main", "cs_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL3, 0,
            &shader, &errors);
    if (errors) release_blob(&errors);
    if (FAILED(hr))
    {
        capability("d3d12", "DXBC_consumption", "SKIP", hr, "shader compile unavailable");
        return;
    }
    if (!module || !(create_device = (create_device_fn)GetProcAddress(module, "D3D12CreateDevice")) ||
            !(serialize_root_signature = (serialize_root_signature_fn)GetProcAddress(module,
            "D3D12SerializeRootSignature")))
    {
        capability("d3d12", "DXBC_consumption", "SKIP", S_FALSE, "D3D12 exports unavailable");
        if (module) FreeLibrary(module);
        release_blob(&shader);
        return;
    }
    hr = create_device(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device,
            (void **)&device);
    if (FAILED(hr))
    {
        capability("d3d12", "DXBC_consumption", "SKIP", hr, "device unavailable");
        release_blob(&shader);
        FreeLibrary(module);
        return;
    }
    memset(&root_desc, 0, sizeof(root_desc));
    hr = serialize_root_signature(&root_desc, D3D_ROOT_SIGNATURE_VERSION_1_0,
            &signature, &errors);
    if (FAILED(hr)) goto done;
    hr = ID3D12Device_CreateRootSignature(device, 0,
            ID3D10Blob_GetBufferPointer(signature), ID3D10Blob_GetBufferSize(signature),
            &IID_ID3D12RootSignature, (void **)&root);
    if (FAILED(hr)) goto done;
    memset(&pipeline_desc, 0, sizeof(pipeline_desc));
    pipeline_desc.pRootSignature = root;
    pipeline_desc.CS.pShaderBytecode = ID3D10Blob_GetBufferPointer(shader);
    pipeline_desc.CS.BytecodeLength = ID3D10Blob_GetBufferSize(shader);
    hr = ID3D12Device_CreateComputePipelineState(device, &pipeline_desc,
            &IID_ID3D12PipelineState, (void **)&pipeline);
done:
    capability("d3d12", "DXBC_compute_pipeline", SUCCEEDED(hr) ? "PASS" : "FAIL",
            hr, "generated cs_5_0");
    if (FAILED(hr)) ++failures;
    if (errors) release_blob(&errors);
    if (pipeline) ID3D12PipelineState_Release(pipeline);
    if (root) ID3D12RootSignature_Release(root);
    if (signature) release_blob(&signature);
    if (device) ID3D12Device_Release(device);
    release_blob(&shader);
    FreeLibrary(module);
}

typedef HRESULT (WINAPI *compile_fn)(const void *, SIZE_T, const char *,
        const D3D_SHADER_MACRO *, ID3DInclude *, const char *, const char *,
        UINT, UINT, ID3DBlob **, ID3DBlob **);
typedef HRESULT (WINAPI *compile2_fn)(const void *, SIZE_T, const char *,
        const D3D_SHADER_MACRO *, ID3DInclude *, const char *, const char *,
        UINT, UINT, UINT, const void *, SIZE_T, ID3DBlob **, ID3DBlob **);
typedef HRESULT (WINAPI *preprocess_fn)(const void *, SIZE_T, const char *,
        const D3D_SHADER_MACRO *, ID3DInclude *, ID3DBlob **, ID3DBlob **);
typedef HRESULT (WINAPI *disassemble_fn)(const void *, SIZE_T, UINT, const char *, ID3DBlob **);
typedef HRESULT (WINAPI *reflect_fn)(const void *, SIZE_T, REFIID, void **);
typedef HRESULT (WINAPI *file_compile_fn)(const WCHAR *, const D3D_SHADER_MACRO *,
        ID3DInclude *, const char *, const char *, UINT, UINT, ID3DBlob **, ID3DBlob **);
typedef HRESULT (WINAPI *read_file_fn)(const WCHAR *, ID3DBlob **);
typedef HRESULT (WINAPI *load_module_fn)(const void *, SIZE_T, ID3D11Module **);
typedef HRESULT (WINAPI *create_graph_fn)(UINT, ID3D11FunctionLinkingGraph **);
typedef HRESULT (WINAPI *create_linker_fn)(ID3D11Linker **);

static void test_version_dll(const char *version, ID3DBlob *shader_blob,
        WCHAR *shader_file)
{
    char name[32];
    HMODULE module;
    compile_fn compile;
    compile2_fn compile2;
    preprocess_fn preprocess;
    disassemble_fn disassemble;
    reflect_fn reflect;
    file_compile_fn file_compile;
    read_file_fn read_file;
    load_module_fn load_module;
    create_graph_fn create_graph;
    create_linker_fn create_linker;
    ID3DBlob *blob = NULL, *errors = NULL, *version_shader = NULL;
    ID3DBlob *consumer_blob = shader_blob;
    HRESULT hr;

    snprintf(name, sizeof(name), "d3dcompiler_%s.dll", version);
    module = LoadLibraryA(name);
    if (!module)
    {
        capability(name, "LoadLibrary", "FAIL", HRESULT_FROM_WIN32(GetLastError()), "required DLL missing");
        ++failures;
        return;
    }
    capability(name, "LoadLibrary", "PASS", S_OK, "builtin/runtime DLL loaded");

    compile = (compile_fn)GetProcAddress(module, "D3DCompile");
    if (compile)
    {
        hr = compile(cs_source, sizeof(cs_source) - 1, "vkmt_version.hlsl", NULL, NULL,
                "main", "cs_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &blob, &errors);
        capability(name, "D3DCompile", SUCCEEDED(hr) ? "PASS" : "FAIL", hr, "cs_5_0");
        if (FAILED(hr)) ++failures;
        release_blob(&blob); release_blob(&errors);

        /* Compile the legacy reflection fixture with the version being
         * tested.  d3dcompiler_43 intentionally rejects newer RDEF data,
         * so reflecting a blob emitted by 47 would test the wrong boundary. */
        if (!strcmp(version, "43"))
        {
            hr = compile(legacy_vs_source, sizeof(legacy_vs_source) - 1,
                    "vkmt_legacy_vs.hlsl", NULL, NULL, "main", "vs_4_0", 0, 0,
                    &version_shader, &errors);
            capability(name, "legacy_reflection_compile",
                    SUCCEEDED(hr) ? "PASS" : "FAIL", hr,
                    "version-local vs_4_0 DXBC");
            if (FAILED(hr)) ++failures;
            if (errors) release_blob(&errors);
            if (version_shader) consumer_blob = version_shader;
        }
    }
    else capability(name, "D3DCompile", "FAIL", E_NOINTERFACE, "export missing"), ++failures;

    compile2 = (compile2_fn)GetProcAddress(module, "D3DCompile2");
    if (compile2)
    {
        hr = compile2(cs_source, sizeof(cs_source) - 1, "vkmt_version.hlsl", NULL, NULL,
                "main", "cs_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, 0, NULL, 0,
                &blob, &errors);
        capability(name, "D3DCompile2", SUCCEEDED(hr) ? "PASS" : "FAIL", hr,
                "cs_5_0 no secondary data");
        if (FAILED(hr)) ++failures;
        release_blob(&blob); release_blob(&errors);
    }
    else capability(name, "D3DCompile2", "EXPECTED_MISSING", S_FALSE,
            "not exported by 43");

    preprocess = (preprocess_fn)GetProcAddress(module, "D3DPreprocess");
    if (preprocess)
    {
        hr = preprocess(cs_source, sizeof(cs_source) - 1, "vkmt_version.hlsl", NULL, NULL,
                &blob, &errors);
        capability(name, "D3DPreprocess", SUCCEEDED(hr) ? "PASS" : "FAIL", hr, "simple source");
        if (FAILED(hr)) ++failures;
        release_blob(&blob); release_blob(&errors);
    }
    else capability(name, "D3DPreprocess", "FAIL", E_NOINTERFACE, "export missing"), ++failures;

    disassemble = (disassemble_fn)GetProcAddress(module, "D3DDisassemble");
    if (disassemble)
    {
        hr = disassemble(ID3D10Blob_GetBufferPointer(consumer_blob), ID3D10Blob_GetBufferSize(consumer_blob),
                0, "version", &blob);
        capability(name, "D3DDisassemble", SUCCEEDED(hr) ? "PASS" : "FAIL", hr, "DXBC");
        if (FAILED(hr)) ++failures;
        release_blob(&blob);
    }
    else capability(name, "D3DDisassemble", "FAIL", E_NOINTERFACE, "export missing"), ++failures;

    reflect = (reflect_fn)GetProcAddress(module, "D3DReflect");
    if (reflect)
    {
        ID3D11ShaderReflection *reflection = NULL;
        hr = reflect(ID3D10Blob_GetBufferPointer(consumer_blob), ID3D10Blob_GetBufferSize(consumer_blob),
                &IID_ID3D11ShaderReflection, (void **)&reflection);
        if (SUCCEEDED(hr))
            capability(name, "D3DReflect", "PASS", hr, "DXBC metadata");
        else if (!strcmp(version, "43") && hr == E_NOINTERFACE)
            capability(name, "D3DReflect", "KNOWN_LIMITATION", hr,
                    "Wine d3dcompiler_43 rejects this reflection interface");
        else
        {
            capability(name, "D3DReflect", "FAIL", hr, "DXBC metadata");
            ++failures;
        }
        if (reflection) reflection->lpVtbl->Release(reflection);
    }
    else capability(name, "D3DReflect", "FAIL", E_NOINTERFACE, "export missing"), ++failures;

    file_compile = (file_compile_fn)GetProcAddress(module, "D3DCompileFromFile");
    if (file_compile)
    {
        hr = file_compile(shader_file, NULL, D3D_COMPILE_STANDARD_FILE_INCLUDE, "main",
                "cs_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &blob, &errors);
        capability(name, "D3DCompileFromFile", SUCCEEDED(hr) ? "PASS" : "FAIL", hr, "Unicode path");
        if (FAILED(hr)) ++failures;
        release_blob(&blob); release_blob(&errors);
    }
    else capability(name, "D3DCompileFromFile", "EXPECTED_MISSING", S_FALSE, "not exported by 43");

    read_file = (read_file_fn)GetProcAddress(module, "D3DReadFileToBlob");
    if (read_file)
    {
        hr = read_file(shader_file, &blob);
        capability(name, "D3DReadFileToBlob", SUCCEEDED(hr) ? "PASS" : "FAIL", hr,
                "Unicode path");
        if (FAILED(hr)) ++failures;
        release_blob(&blob);
    }
    else capability(name, "D3DReadFileToBlob", "EXPECTED_MISSING", S_FALSE,
            "not exported by 43");

    load_module = (load_module_fn)GetProcAddress(module, "D3DLoadModule");
    if (load_module)
    {
        ID3D11Module *module_object = NULL;
        hr = load_module(ID3D10Blob_GetBufferPointer(consumer_blob), ID3D10Blob_GetBufferSize(consumer_blob), &module_object);
        capability(name, "D3DLoadModule", hr == E_NOTIMPL ? "KNOWN_STUB" : "UNEXPECTED_HRESULT",
                hr, "Wine source documents E_NOTIMPL");
        if (module_object) IUnknown_Release((IUnknown *)module_object);
        if (hr != E_NOTIMPL) ++failures;
    }
    else capability(name, "D3DLoadModule", "EXPECTED_MISSING", S_FALSE, "not exported by this DLL");

    if (GetProcAddress(module, "D3DSetBlobPart"))
        capability(name, "D3DSetBlobPart", "KNOWN_STUB_NOT_CALLED", E_NOTIMPL,
                "Wine spec stub raises unimplemented-function exception");
    else
        capability(name, "D3DSetBlobPart", "EXPECTED_MISSING", S_FALSE, "not exported by 43");

    {
        static const char *const known_stubs[] =
        {
            "D3DCompressShaders", "D3DDecompressShaders", "D3DDisassemble10Effect",
            "D3DDisassemble11Trace", "D3DDisassembleRegion", "D3DGetTraceInstructionOffsets",
            "D3DReflectLibrary", "D3DReturnFailure1", "DebugSetMute",
        };
        unsigned int i;
        for (i = 0; i < ARRAY_SIZE(known_stubs); ++i)
        {
            if (GetProcAddress(module, known_stubs[i]))
                capability(name, known_stubs[i], "KNOWN_STUB_NOT_CALLED", E_NOTIMPL,
                        "Wine spec @stub; not called because it may abort the guest");
            else
                capability(name, known_stubs[i], "EXPECTED_MISSING", S_FALSE,
                        "export is not present in this version");
        }
    }

    create_graph = (create_graph_fn)GetProcAddress(module, "D3DCreateFunctionLinkingGraph");
    if (create_graph)
    {
        ID3D11FunctionLinkingGraph *graph = NULL;
        hr = create_graph(0, &graph);
        capability(name, "D3DCreateFunctionLinkingGraph", SUCCEEDED(hr) ? "PASS" : "FAIL",
                hr, "API availability");
        if (FAILED(hr)) ++failures;
        if (graph) graph->lpVtbl->Release(graph);
    }
    else capability(name, "D3DCreateFunctionLinkingGraph", "EXPECTED_MISSING", S_FALSE, "not exported by 46");

    create_linker = (create_linker_fn)GetProcAddress(module, "D3DCreateLinker");
    if (create_linker)
    {
        ID3D11Linker *linker = NULL;
        hr = create_linker(&linker);
        capability(name, "D3DCreateLinker", SUCCEEDED(hr) ? "PASS" : "FAIL", hr, "API availability");
        if (FAILED(hr)) ++failures;
        if (linker) linker->lpVtbl->Release(linker);
    }
    else capability(name, "D3DCreateLinker", "EXPECTED_MISSING", S_FALSE, "not exported by 46");

    release_blob(&version_shader);
    FreeLibrary(module);
}

int main(int argc, char **argv)
{
    ID3DBlob *vs_blob = NULL, *ps_blob = NULL, *cs_blob = NULL, *legacy_vs_blob = NULL;
    ID3DBlob *errors = NULL;
    WCHAR shader_file[] = L"C:\\vkmt_d3dcompiler_contract\\shader-\x03a9.hlsl";
    int run_d3d11 = argc > 1 && (!strcmp(argv[1], "--consumers") ||
            !strcmp(argv[1], "--d3d11"));
    int run_d3d12 = argc > 1 && (!strcmp(argv[1], "--consumers") ||
            !strcmp(argv[1], "--d3d12"));
    if (!CreateDirectoryW(L"C:\\vkmt_d3dcompiler_contract", NULL) &&
            GetLastError() != ERROR_ALREADY_EXISTS)
    {
        fprintf(stderr, "CreateDirectoryW failed error=%lu\n", GetLastError());
        return 2;
    }
    test_compile_and_frontend(&vs_blob, &ps_blob, &cs_blob, shader_file);
    if (!vs_blob || !ps_blob || !cs_blob)
    {
        fprintf(stderr, "required shader blobs missing\n");
        ++failures;
    }
    else
    {
        HRESULT legacy_hr = D3DCompile(legacy_vs_source, sizeof(legacy_vs_source) - 1,
                "vkmt_legacy_vs.hlsl", NULL, NULL, "main", "vs_4_0", 0, 0,
                &legacy_vs_blob, &errors);
        if (errors) release_blob(&errors);
        capability("d3dcompiler_47", "legacy_reflection_fixture",
                SUCCEEDED(legacy_hr) ? "PASS" : "FAIL", legacy_hr,
                "vs_4_0 fixture for d3dcompiler_43");
        if (FAILED(legacy_hr)) ++failures;
        test_reflection(vs_blob, cs_blob);
        if (run_d3d11) test_d3d11_consumption(cs_blob);
        else
        {
            capability("d3d11", "DXBC_consumption", "SKIP", S_FALSE,
                    "consumer lane disabled for this architecture");
        }
        if (run_d3d12) test_d3d12_consumption();
        else
        {
            capability("d3d12", "DXBC_consumption", "SKIP", S_FALSE,
                    "consumer lane disabled for this architecture");
        }
        test_version_dll("43", legacy_vs_blob ? legacy_vs_blob : cs_blob, shader_file);
        test_version_dll("46", cs_blob, shader_file);
        test_version_dll("47", cs_blob, shader_file);
    }
    release_blob(&vs_blob);
    release_blob(&ps_blob);
    release_blob(&cs_blob);
    release_blob(&legacy_vs_blob);
    DeleteFileW(shader_file);
    RemoveDirectoryW(L"C:\\vkmt_d3dcompiler_contract");

    if (failures)
    {
        fprintf(stderr, "D3DCOMPILER_CONTRACT_FAIL failures=%u\n", failures);
        return 1;
    }
    puts("D3DCOMPILER_CONTRACT_OK");
    return 0;
}
