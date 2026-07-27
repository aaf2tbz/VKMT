/* VKMT D3D11/DXGI acceptance: device -> offscreen clear -> staging readback. */
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_4.h>
#include <stdio.h>

int main(void)
{
    const float clear[4] = { 0.125f, 0.25f, 0.75f, 1.0f };
    D3D_FEATURE_LEVEL feature_level = 0;
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    ID3D11Texture2D *target = NULL, *staging = NULL;
    ID3D11RenderTargetView *rtv = NULL;
    D3D11_TEXTURE2D_DESC desc = {0};
    D3D11_MAPPED_SUBRESOURCE mapped = {0};
    HRESULT hr;

    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
            D3D11_SDK_VERSION, &device, &feature_level, &context);
    fprintf(stderr, "VKMT_D3D11: D3D11CreateDevice hr=%#lx feature=%#x\n",
            (unsigned long)hr, feature_level);
    if (FAILED(hr)) return 1;

    desc.Width = 16;
    desc.Height = 16;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET;
    hr = device->lpVtbl->CreateTexture2D(device, &desc, NULL, &target);
    if (SUCCEEDED(hr)) hr = device->lpVtbl->CreateRenderTargetView(device, (ID3D11Resource *)target, NULL, &rtv);
    if (SUCCEEDED(hr)) {
        context->lpVtbl->ClearRenderTargetView(context, rtv, clear);
        desc.Usage = D3D11_USAGE_STAGING;
        desc.BindFlags = 0;
        desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        hr = device->lpVtbl->CreateTexture2D(device, &desc, NULL, &staging);
    }
    if (SUCCEEDED(hr)) {
        context->lpVtbl->CopyResource(context, (ID3D11Resource *)staging, (ID3D11Resource *)target);
        context->lpVtbl->Flush(context);
        hr = context->lpVtbl->Map(context, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &mapped);
    }
    if (SUCCEEDED(hr)) {
        const BYTE *pixel = mapped.pData;
        /* UNORM conversion permits one LSB of rounding. */
        if (pixel[0] < 30 || pixel[0] > 34 || pixel[1] < 62 || pixel[1] > 66 ||
                pixel[2] < 190 || pixel[2] > 193 || pixel[3] != 255)
            hr = E_FAIL;
        context->lpVtbl->Unmap(context, (ID3D11Resource *)staging, 0);
    }
    fprintf(stderr, "VKMT_D3D11: clear/copy/readback hr=%#lx\n", (unsigned long)hr);
    if (staging) staging->lpVtbl->Release(staging);
    if (rtv) rtv->lpVtbl->Release(rtv);
    if (target) target->lpVtbl->Release(target);
    if (context) context->lpVtbl->Release(context);
    if (device) device->lpVtbl->Release(device);
    if (FAILED(hr)) return 1;
    puts("VKMT_D3D11_PROBE_OK");
    return 0;
}
