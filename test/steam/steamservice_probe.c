#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

static SERVICE_STATUS_HANDLE service_handle;
static volatile LONG service_main_called;
static volatile LONG exception_seen;

static LONG CALLBACK probe_exception_handler(EXCEPTION_POINTERS *exception)
{
    if (exception->ExceptionRecord->ExceptionCode != 0xE0424242)
        return EXCEPTION_CONTINUE_SEARCH;
    InterlockedIncrement(&exception_seen);
    return EXCEPTION_CONTINUE_EXECUTION;
}

static void WINAPI probe_service_main(DWORD argc, WCHAR **argv)
{
    SERVICE_STATUS status = {0};
    (void)argc;
    (void)argv;
    InterlockedIncrement(&service_main_called);
    service_handle = RegisterServiceCtrlHandlerW(L"VKMTSteamServiceProbe", NULL);
    if (service_handle)
    {
        status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
        status.dwCurrentState = SERVICE_STOPPED;
        SetServiceStatus(service_handle, &status);
    }
}

int wmain(int argc, WCHAR **argv)
{
    static const char *const exports[] =
    {
        "CreateInterface", "SteamService_RunMainLoop", "SteamService_Shutdown",
        "SteamService_StartThread", "SteamService_Stop", "g_dwDllEntryThreadId"
    };
    SERVICE_TABLE_ENTRYW table[] =
    {
        { L"VKMTSteamServiceProbe", probe_service_main },
        { NULL, NULL }
    };
    HMODULE module;
    DWORD dispatch_error;
    unsigned int i;
    PVOID exception_handler;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc != 2)
    {
        puts("usage: steamservice_probe.exe path-to-SteamService.dll");
        return 2;
    }

    module = LoadLibraryExW(argv[1], NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!module)
    {
        printf("LoadLibraryExW failed: %lu\n", GetLastError());
        return 3;
    }
    printf("loaded=%p\n", module);
    for (i = 0; i < sizeof(exports) / sizeof(exports[0]); ++i)
    {
        if (!GetProcAddress(module, exports[i]))
        {
            printf("missing export: %s\n", exports[i]);
            return 4;
        }
    }
    printf("exports=%u TLS/DllMain=executed\n", i);

    exception_handler = AddVectoredExceptionHandler(1, probe_exception_handler);
    if (!exception_handler) return 5;
    RaiseException(0xE0424242, 0, 0, NULL);
    RemoveVectoredExceptionHandler(exception_handler);
    if (exception_seen != 1)
    {
        puts("SEH fixture did not execute");
        return 5;
    }

    SetLastError(ERROR_SUCCESS);
    if (StartServiceCtrlDispatcherW(table))
    {
        puts("unexpected SCM connection");
        return 6;
    }
    dispatch_error = GetLastError();
    printf("service-dispatch error=%lu main-called=%ld\n",
           dispatch_error, service_main_called);
    if (dispatch_error != ERROR_FAILED_SERVICE_CONTROLLER_CONNECT ||
        service_main_called != 0)
        return 7;

    if (!FreeLibrary(module)) return 8;
    puts("STEAMSERVICE_I386_IMPORT_TLS_SEH_NONPERSISTENT_DISPATCH_OK");
    return 0;
}
