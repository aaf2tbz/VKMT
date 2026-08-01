#include <windows.h>
#include <stdio.h>

int main(void)
{
    static const char *const modules[] = {
        "user32.dll", "gdi32.dll", "comctl32.dll", "ole32.dll", "shell32.dll",
        "winhttp.dll", "wininet.dll", "ws2_32.dll", "bcrypt.dll", "crypt32.dll",
        "dxgi.dll", "d3d11.dll", "d3d12.dll", "opengl32.dll", "xaudio2_9.dll"
    };
    unsigned loaded = 0;
    for (unsigned i = 0; i < sizeof(modules) / sizeof(modules[0]); ++i) {
        HMODULE module = LoadLibraryA(modules[i]);
        if (module) ++loaded;
    }
    printf("VKMT_P8_HOTSET_READY loaded=%u\n", loaded);
    fflush(stdout);
    Sleep(6000);
    puts("VKMT_P8_HOTSET_OK");
    return loaded >= 12 ? 0 : 3;
}
