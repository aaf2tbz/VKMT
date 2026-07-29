#define UNICODE
#define _UNICODE
#include <windows.h>
#include <stdio.h>

static int require_export(HMODULE module, const char *name)
{
    if (!GetProcAddress(module, name))
    {
        fprintf(stderr, "missing CEF export: %s (error=%lu)\n",
                name, (unsigned long)GetLastError());
        return 0;
    }
    printf("CEF_EXPORT_%s_OK\n", name);
    return 1;
}

int wmain(int argc, wchar_t **argv)
{
    static const char *const exports[] =
    {
        "cef_version_info",
        "cef_execute_process",
        "cef_initialize",
        "cef_browser_host_create_browser",
        "cef_shutdown"
    };
    HMODULE module;
    unsigned int i;

    if (argc != 2)
    {
        fwprintf(stderr, L"usage: %ls <libcef.dll>\n", argv[0]);
        return 2;
    }

    module = LoadLibraryExW(argv[1], NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!module)
    {
        fwprintf(stderr, L"LoadLibraryExW failed for %ls (error=%lu)\n",
                 argv[1], (unsigned long)GetLastError());
        return 3;
    }
    for (i = 0; i < sizeof(exports) / sizeof(exports[0]); ++i)
    {
        if (!require_export(module, exports[i]))
        {
            FreeLibrary(module);
            return 4;
        }
    }
    FreeLibrary(module);
    puts("CEF_LIBCEF_EXPORTS_OK");
    return 0;
}
