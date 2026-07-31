#include <windows.h>
#include <intrin.h>
#include <stdio.h>

static int probe_heap(const char *label)
{
    void *teb = (void *)__readgsqword(0x30);
    void *peb = (void *)__readgsqword(0x60);
    void *peb_heap = peb ? *(void **)((char *)peb + 0x30) : NULL;
    HANDLE api_heap = GetProcessHeap();
    void *block;

    printf("%s teb=%p peb=%p peb_heap=%p api_heap=%p\n",
           label, teb, peb, peb_heap, api_heap);
    if (!peb || !peb_heap || peb_heap != api_heap) return 10;
    if (!(block = HeapAlloc(api_heap, HEAP_ZERO_MEMORY, 96))) return 11;
    memset(block, 0x5a, 96);
    if (!HeapFree(api_heap, 0, block)) return 12;
    return 0;
}

int main(int argc, char **argv)
{
    WCHAR path[MAX_PATH], command[MAX_PATH + 32];
    PROCESS_INFORMATION process;
    STARTUPINFOW startup = { sizeof(startup) };
    DWORD exit_code;
    int ret;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc > 1)
    {
        ret = probe_heap("CHILD");
        printf("CHILD_RC=%d\n", ret);
        return ret;
    }

    if ((ret = probe_heap("PARENT"))) return ret;
    if (!GetModuleFileNameW(NULL, path, ARRAYSIZE(path))) return 20;
    swprintf(command, ARRAYSIZE(command), L"\"%s\" child", path);
    if (!CreateProcessW(NULL, command, NULL, NULL, FALSE, 0, NULL, NULL,
                        &startup, &process))
    {
        printf("CreateProcessW failed %lu\n", GetLastError());
        return 21;
    }
    WaitForSingleObject(process.hProcess, INFINITE);
    GetExitCodeProcess(process.hProcess, &exit_code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    printf("CHILD_EXIT=%lu\n", exit_code);
    return exit_code ? 22 : 0;
}
