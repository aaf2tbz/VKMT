/* DXVK shader-cache acceptance: compile DXBC and create one cached CS object. */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
    static const char source[] =
        "RWStructuredBuffer<uint> output : register(u0);"
        "[numthreads(1,1,1)] void main() { output[0] = 0x504b3656; }";
    ID3DBlob *bytecode = NULL, *errors = NULL;
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    ID3D11ComputeShader *shader = NULL;
    ID3D11Buffer *output = NULL, *staging = NULL;
    ID3D11UnorderedAccessView *uav = NULL;
    D3D11_BUFFER_DESC buffer_desc = {0};
    D3D11_UNORDERED_ACCESS_VIEW_DESC uav_desc = {0};
    D3D11_MAPPED_SUBRESOURCE mapped = {0};
    D3D_FEATURE_LEVEL feature_level = 0;
    LARGE_INTEGER perf_frequency = {0}, pipeline_start = {0}, pipeline_end = {0};
    LARGE_INTEGER shader_start = {0}, shader_end = {0};
    void *shader_data = NULL;
    size_t shader_size = 0;
    HRESULT hr;

    if (argc == 3 && strcmp(argv[1], "--compile") == 0) {
        FILE *file;
        hr = D3DCompile(source, sizeof(source) - 1, "vkmt-p6", NULL, NULL,
                "main", "cs_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL3, 0,
                &bytecode, &errors);
        if (FAILED(hr)) {
            if (errors) fprintf(stderr, "%.*s\n", (int)ID3D10Blob_GetBufferSize(errors),
                    (const char *)ID3D10Blob_GetBufferPointer(errors));
            return 1;
        }
        file = fopen(argv[2], "wb");
        if (!file || fwrite(ID3D10Blob_GetBufferPointer(bytecode),
                ID3D10Blob_GetBufferSize(bytecode), 1, file) != 1) return 2;
        fclose(file);
        ID3D10Blob_Release(bytecode);
        if (errors) ID3D10Blob_Release(errors);
        puts("VKMT_P6_DXBC_COMPILE_OK");
        return 0;
    }
    if (argc != 3 || strcmp(argv[1], "--load") != 0) return 2;

    {
        FILE *file = fopen(argv[2], "rb");
        if (!file || fseek(file, 0, SEEK_END) || (shader_size = (size_t)ftell(file)) == 0 ||
                fseek(file, 0, SEEK_SET)) return 2;
        shader_data = malloc(shader_size);
        if (!shader_data || fread(shader_data, shader_size, 1, file) != 1) return 2;
        fclose(file);
    }

    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
            D3D11_SDK_VERSION, &device, &feature_level, &context);
    QueryPerformanceFrequency(&perf_frequency);
    QueryPerformanceCounter(&pipeline_start);
    QueryPerformanceCounter(&shader_start);
    if (SUCCEEDED(hr))
        hr = ID3D11Device_CreateComputeShader(device,
                shader_data, shader_size,
                NULL, &shader);
    QueryPerformanceCounter(&shader_end);
    if (SUCCEEDED(hr)) {
        buffer_desc.ByteWidth = sizeof(unsigned int);
        buffer_desc.Usage = D3D11_USAGE_DEFAULT;
        buffer_desc.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
        buffer_desc.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
        buffer_desc.StructureByteStride = sizeof(unsigned int);
        hr = ID3D11Device_CreateBuffer(device, &buffer_desc, NULL, &output);
    }
    if (SUCCEEDED(hr)) {
        uav_desc.Format = DXGI_FORMAT_UNKNOWN;
        uav_desc.ViewDimension = D3D11_UAV_DIMENSION_BUFFER;
        uav_desc.Buffer.NumElements = 1;
        hr = ID3D11Device_CreateUnorderedAccessView(device,
                (ID3D11Resource *)output, &uav_desc, &uav);
    }
    if (SUCCEEDED(hr)) {
        ID3D11DeviceContext_CSSetShader(context, shader, NULL, 0);
        ID3D11DeviceContext_CSSetUnorderedAccessViews(context, 0, 1, &uav, NULL);
        ID3D11DeviceContext_Dispatch(context, 1, 1, 1);
        buffer_desc.Usage = D3D11_USAGE_STAGING;
        buffer_desc.BindFlags = 0;
        buffer_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        buffer_desc.MiscFlags = 0;
        buffer_desc.StructureByteStride = 0;
        hr = ID3D11Device_CreateBuffer(device, &buffer_desc, NULL, &staging);
    }
    if (SUCCEEDED(hr)) {
        ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)staging,
                (ID3D11Resource *)output);
        hr = ID3D11DeviceContext_Map(context, (ID3D11Resource *)staging, 0,
                D3D11_MAP_READ, 0, &mapped);
    }
    if (SUCCEEDED(hr)) {
        if (*(const unsigned int *)mapped.pData != 0x504b3656u) hr = E_FAIL;
        ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)staging, 0);
    }
    QueryPerformanceCounter(&pipeline_end);

    if (uav) ID3D11UnorderedAccessView_Release(uav);
    if (staging) ID3D11Buffer_Release(staging);
    if (output) ID3D11Buffer_Release(output);
    if (shader) ID3D11ComputeShader_Release(shader);
    if (context) ID3D11DeviceContext_Release(context);
    if (device) ID3D11Device_Release(device);
    free(shader_data);
    if (FAILED(hr)) return 1;
    if (perf_frequency.QuadPart > 0)
        printf("VKMT_P6_SHADER_CREATE_NS=%llu\n", (unsigned long long)
                ((shader_end.QuadPart - shader_start.QuadPart) * 1000000000ull /
                perf_frequency.QuadPart));
    if (perf_frequency.QuadPart > 0)
        printf("VKMT_P6_PIPELINE_NS=%llu\n", (unsigned long long)
                ((pipeline_end.QuadPart - pipeline_start.QuadPart) * 1000000000ull /
                perf_frequency.QuadPart));
    puts("VKMT_P6_DXVK_SHADER_CACHE_PROBE_OK");
    return 0;
}
