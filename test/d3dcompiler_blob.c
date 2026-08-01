/* Produce deterministic DXBC without loading a D3D runtime. */
#define COBJMACROS
#include <windows.h>
#include <d3dcompiler.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    static const char source[] =
        "RWStructuredBuffer<uint> output : register(u0);"
        "[numthreads(1,1,1)] void main() { output[0] = 0x504b3656; }";
    ID3DBlob *bytecode = NULL, *errors = NULL;
    FILE *file;
    HRESULT hr;

    if (argc != 2) return 2;
    hr = D3DCompile(source, sizeof(source) - 1, "vkmt-p6", NULL, NULL,
            "main", "cs_5_0", D3DCOMPILE_OPTIMIZATION_LEVEL3, 0,
            &bytecode, &errors);
    if (FAILED(hr)) {
        if (errors) fprintf(stderr, "%.*s\n", (int)ID3D10Blob_GetBufferSize(errors),
                (const char *)ID3D10Blob_GetBufferPointer(errors));
        return 1;
    }
    file = fopen(argv[1], "wb");
    if (!file || fwrite(ID3D10Blob_GetBufferPointer(bytecode),
            ID3D10Blob_GetBufferSize(bytecode), 1, file) != 1) return 2;
    fclose(file);
    if (errors) ID3D10Blob_Release(errors);
    ID3D10Blob_Release(bytecode);
    puts("VKMT_P6_DXBC_COMPILE_OK");
    return 0;
}
