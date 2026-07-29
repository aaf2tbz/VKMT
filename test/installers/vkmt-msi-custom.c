#include <windows.h>
#include <msiquery.h>
#include <string.h>

static UINT touch(const char *path, const char *contents)
{
    DWORD written;
    HANDLE file;

    file = CreateFileA(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, 0, NULL);
    if (file == INVALID_HANDLE_VALUE) return ERROR_INSTALL_FAILURE;
    WriteFile(file, contents, (DWORD)strlen(contents), &written, NULL);
    CloseHandle(file);
    return ERROR_SUCCESS;
}

__declspec(dllexport) UINT __stdcall CommitMarker(MSIHANDLE install)
{
    (void)install;
    return touch("C:\\vkmt-msi-custom-action.txt", "commit");
}

__declspec(dllexport) UINT __stdcall RollbackMarker(MSIHANDLE install)
{
    (void)install;
    return touch("C:\\vkmt-msi-rollback-action.txt", "rollback");
}

__declspec(dllexport) UINT __stdcall DeliberateFailure(MSIHANDLE install)
{
    (void)install;
    return ERROR_INSTALL_FAILURE;
}
