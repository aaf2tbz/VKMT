#include <windows.h>

static SERVICE_STATUS_HANDLE status_handle;
static SERVICE_STATUS status;

static void WINAPI control(DWORD code)
{
    if (code == SERVICE_CONTROL_STOP || code == SERVICE_CONTROL_SHUTDOWN)
    {
        status.dwCurrentState = SERVICE_STOPPED;
        SetServiceStatus(status_handle, &status);
    }
}

static void WINAPI service_main(DWORD argc, char **argv)
{
    (void)argc;
    (void)argv;
    status_handle = RegisterServiceCtrlHandlerA("VKMTMsiProbe", control);
    if (!status_handle) return;
    status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    status.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN;
    status.dwCurrentState = SERVICE_RUNNING;
    SetServiceStatus(status_handle, &status);
    while (status.dwCurrentState == SERVICE_RUNNING) Sleep(50);
}

int main(void)
{
    SERVICE_TABLE_ENTRYA table[] = {
        {"VKMTMsiProbe", service_main},
        {NULL, NULL}
    };
    return StartServiceCtrlDispatcherA(table) ? 0 : 1;
}
