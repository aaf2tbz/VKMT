#include <windows.h>
#include <stdio.h>

int main(void)
{
    HMODULE rpcrt4;
    FARPROC ndr;
    IMAGE_NT_HEADERS *nt;
    SC_HANDLE manager;

    LoadLibraryW(L"sechost.dll");
    rpcrt4 = LoadLibraryW(L"rpcrt4.dll");
    if (!rpcrt4)
    {
        printf("FAIL LoadLibraryW(rpcrt4.dll) error=%lu\n", GetLastError());
        return 1;
    }

    nt = (IMAGE_NT_HEADERS *)((BYTE *)rpcrt4 +
                              ((IMAGE_DOS_HEADER *)rpcrt4)->e_lfanew);
    ndr = GetProcAddress(rpcrt4, "NdrClientCall2");
    printf("rpcrt4=%p machine=%04x NdrClientCall2=%p rva=%llx\n",
           rpcrt4, nt->FileHeader.Machine, ndr,
           (unsigned long long)((BYTE *)ndr - (BYTE *)rpcrt4));
    fflush(stdout);

    manager = OpenSCManagerW(NULL, NULL, SC_MANAGER_CONNECT);
    if (!manager)
    {
        printf("FAIL OpenSCManagerW error=%lu\n", GetLastError());
        return 2;
    }
    if (!CloseServiceHandle(manager))
    {
        printf("FAIL CloseServiceHandle error=%lu\n", GetLastError());
        return 3;
    }

    puts("PASS OpenSCManagerW/CloseServiceHandle");
    return 0;
}
