/* i386 vkd3d-to-Wine Vulkan loader contract probe.
 *
 * vkd3d-proton's d3d12core.dll requires these exact operations before it can
 * create its Vulkan instance.  Keep this deliberately below instance creation
 * so a failure identifies the loader/export boundary, not a Vulkan feature.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

typedef void * (WINAPI *vk_get_instance_proc_addr_fn)(void *instance,
                                                        const char *name);

static int write_marker(const char *path, const char *text)
{
    HANDLE file;
    DWORD written;

    file = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                       FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return 1;
    if (!WriteFile(file, text, lstrlenA(text), &written, NULL) ||
        written != lstrlenA(text))
    {
        CloseHandle(file);
        return 1;
    }
    CloseHandle(file);
    return 0;
}

int main(int argc, char **argv)
{
    HMODULE module;
    vk_get_instance_proc_addr_fn get_instance_proc;

    if (argc != 2) return 20;
    module = LoadLibraryA("winevulkan.dll");
    if (!module)
    {
        write_marker(argv[1], "P5_I386_WINEVULKAN_LOAD_FAILED");
        return 10;
    }
    get_instance_proc = (void *)GetProcAddress(module, "vkGetInstanceProcAddr");
    if (!get_instance_proc)
    {
        write_marker(argv[1], "P5_I386_WINEVULKAN_GIPA_EXPORT_FAILED");
        return 11;
    }
    if (!get_instance_proc(NULL, "vkCreateInstance"))
    {
        write_marker(argv[1], "P5_I386_WINEVULKAN_CREATE_EXPORT_FAILED");
        return 12;
    }
    if (write_marker(argv[1], "P5_I386_WINEVULKAN_CONTRACT_OK")) return 13;
    return 0;
}
