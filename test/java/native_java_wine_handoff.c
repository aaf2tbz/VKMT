#include <windows.h>

typedef LONG (WINAPI *wine_unix_spawnvp_t)(char * const argv[], int wait);

static char java_path[4096];
static char jar_path[4096];
static char jni_path[4096];
static char tls_url[1024];
static char jni_option[4128];
static char tls_option[1056];

static int read_environment(const char *name, char *buffer, DWORD size)
{
    DWORD length = GetEnvironmentVariableA(name, buffer, size);
    return length && length < size;
}

static void write_marker(const char *marker)
{
    DWORD written;
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), marker, lstrlenA(marker), &written, NULL);
}

int main(void)
{
    HMODULE ntdll;
    wine_unix_spawnvp_t spawn;
    char *argv[7];
    LONG status;

    if (!read_environment("VKMT_NATIVE_JAVA", java_path, sizeof(java_path)) ||
        !read_environment("VKMT_NATIVE_JAVA_JAR", jar_path, sizeof(jar_path)) ||
        !read_environment("VKMT_NATIVE_JAVA_JNI", jni_path, sizeof(jni_path)) ||
        !read_environment("VKMT_NATIVE_JAVA_TLS_URL", tls_url, sizeof(tls_url)))
    {
        write_marker("VKMT_NATIVE_JAVA_HANDOFF_ENVIRONMENT_MISSING\n");
        return 2;
    }

    lstrcpyA(jni_option, "-Dvkmt.jni=");
    lstrcatA(jni_option, jni_path);
    lstrcpyA(tls_option, "-Dvkmt.tls.url=");
    lstrcatA(tls_option, tls_url);

    ntdll = GetModuleHandleW(L"ntdll.dll");
    spawn = (wine_unix_spawnvp_t)GetProcAddress(ntdll, "__wine_unix_spawnvp");
    if (!spawn)
    {
        write_marker("VKMT_NATIVE_JAVA_HANDOFF_EXPORT_MISSING\n");
        return 3;
    }

    argv[0] = java_path;
    argv[1] = "-server";
    argv[2] = jni_option;
    argv[3] = tls_option;
    argv[4] = "-jar";
    argv[5] = jar_path;
    argv[6] = NULL;
    status = spawn(argv, TRUE);
    if (status)
    {
        write_marker("VKMT_NATIVE_JAVA_HANDOFF_CHILD_FAILED\n");
        return 4;
    }

    write_marker("VKMT_NATIVE_JAVA_WINE_PREFIX_HANDOFF_OK\n");
    return 0;
}
