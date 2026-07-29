#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static void write_line(HANDLE file, const char *line)
{
    DWORD written;
    WriteFile(file, line, lstrlenA(line), &written, NULL);
    WriteFile(file, "\r\n", 2, &written, NULL);
    FlushFileBuffers(file);
}

static void write_error(HANDLE file, DWORD error)
{
    static const char hex[] = "0123456789abcdef";
    char line[] = "OPENGL32_ERROR_0x00000000";
    unsigned int i;

    for (i = 0; i < 8; i++)
        line[sizeof(line) - 2 - i] = hex[(error >> (i * 4)) & 15];
    write_line(file, line);
}

int main(int argc, char **argv)
{
    static const char *const dependencies[] = {
        "win32u.dll", "gdi32.dll", "user32.dll", "opengl32.dll", "glu32.dll"
    };
    HMODULE module, opengl32 = NULL;
    HANDLE marker;
    unsigned int i;

    if (argc != 2) return 2;
    marker = CreateFileA(argv[1], GENERIC_WRITE, FILE_SHARE_READ, NULL,
                         CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (marker == INVALID_HANDLE_VALUE) return 3;
    write_line(marker, "OPENGL_PROBE_PROCESS_STARTED");
    for (i = 0; i < sizeof(dependencies) / sizeof(dependencies[0]); i++)
    {
        module = LoadLibraryA(dependencies[i]);
        if (!module)
        {
            write_line(marker, dependencies[i]);
            write_line(marker, "OPENGL_DEPENDENCY_LOAD_FAILED");
            write_error(marker, GetLastError());
            if (GetEnvironmentVariableA("VKMT_OPENGL_PROBE_PAUSE", NULL, 0)) Sleep(30000);
            return 4;
        }
        if (!lstrcmpiA(dependencies[i], "opengl32.dll")) opengl32 = module;
        write_line(marker, dependencies[i]);
        write_line(marker, "OPENGL_DEPENDENCY_LOAD_OK");
    }
    write_line(marker, "OPENGL32_LOAD_OK");
    if (!GetProcAddress(opengl32, "wglCreateContext") ||
        !GetProcAddress(opengl32, "glReadPixels"))
    {
        write_line(marker, "OPENGL32_EXPORTS_FAILED");
        return 5;
    }
    write_line(marker, "OPENGL32_EXPORTS_OK");
    FreeLibrary(opengl32);
    CloseHandle(marker);
    return 0;
}
