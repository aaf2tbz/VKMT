#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

typedef void *(__cdecl *create_interface_fn)(const char *, int *);

static const char *const required_exports[] =
{
    "Breakpad_SteamMiniDumpInit", "Breakpad_SteamSendMiniDump",
    "Breakpad_SteamSetAppID", "Breakpad_SteamSetSteamID",
    "Breakpad_SteamWriteMiniDumpSetComment",
    "Breakpad_SteamWriteMiniDumpUsingExceptionInfoWithBuildId",
    "CreateInterface", "Steam_BConnected", "Steam_BGetCallback",
    "Steam_BLoggedOn", "Steam_BReleaseSteamPipe", "Steam_ConnectToGlobalUser",
    "Steam_CreateGlobalUser", "Steam_CreateLocalUser", "Steam_CreateSteamPipe",
    "Steam_FreeLastCallback", "Steam_GSBLoggedOn", "Steam_GSBSecure",
    "Steam_GSGetSteam2GetEncryptionKeyToSendToNewClient", "Steam_GSGetSteamID",
    "Steam_GSLogOff", "Steam_GSLogOn", "Steam_GSRemoveUserConnect",
    "Steam_GSSendSteam2UserConnect", "Steam_GSSendSteam3UserConnect",
    "Steam_GSSendUserDisconnect", "Steam_GSSendUserStatusResponse",
    "Steam_GSSetServerType", "Steam_GSSetSpawnCount", "Steam_GSUpdateStatus",
    "Steam_GetAPICallResult", "Steam_GetGSHandle", "Steam_InitiateGameConnection",
    "Steam_IsKnownInterface", "Steam_LogOff", "Steam_LogOn",
    "Steam_NotifyMissingInterface", "Steam_ReleaseThreadLocalMemory",
    "Steam_ReleaseUser", "Steam_SetLocalIPBinding",
    "Steam_TerminateGameConnection"
};

int wmain(int argc, WCHAR **argv)
{
    WCHAR full[MAX_PATH * 4], *name;
    HMODULE module;
    create_interface_fn create_interface;
    unsigned int i;
    int return_code = -1;
    void *client, *invalid;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc != 2)
    {
        puts("usage: steamclient_probe.exe path-to-steamclient.dll");
        return 2;
    }
    if (!GetFullPathNameW(argv[1], ARRAY_SIZE(full), full, &name) || !name)
    {
        printf("GetFullPathNameW failed: %lu\n", GetLastError());
        return 3;
    }
    name[-1] = 0;
    if (!SetDllDirectoryW(full) || !SetCurrentDirectoryW(full))
    {
        printf("runtime directory setup failed: %lu\n", GetLastError());
        return 4;
    }
    name[-1] = L'\\';

    module = LoadLibraryExW(argv[1], NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!module)
    {
        printf("LoadLibraryExW failed: %lu\n", GetLastError());
        return 5;
    }
    printf("loaded=%p path=%ls\n", module, argv[1]);

    for (i = 0; i < ARRAY_SIZE(required_exports); ++i)
    {
        if (!GetProcAddress(module, required_exports[i]))
        {
            printf("missing export: %s\n", required_exports[i]);
            return 6;
        }
    }
    printf("exports=%u\n", (unsigned int)ARRAY_SIZE(required_exports));

    create_interface = (create_interface_fn)GetProcAddress(module, "CreateInterface");
    invalid = create_interface("VKMTDefinitelyInvalidInterface001", &return_code);
    printf("invalid-interface=%p rc=%d\n", invalid, return_code);
    if (invalid || return_code == 0) return 7;

    return_code = -1;
    client = create_interface("SteamClient023", &return_code);
    printf("SteamClient023=%p rc=%d\n", client, return_code);
    if (!client || return_code != 0) return 8;

    if (!FreeLibrary(module))
    {
        printf("FreeLibrary failed: %lu\n", GetLastError());
        return 9;
    }
    puts("STEAMCLIENT_LOAD_IMPORTS_EXPORTS_FACTORY_SAFE_INIT_OK");
    return 0;
}
