#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <windows.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

static int fail(const char *stage, const char *detail, DWORD value)
{
    fprintf(stderr, "NO_TSO_PHASE5_FAIL stage=%s detail=%s value=%lu winerr=%lu\n",
            stage, detail, value, GetLastError());
    return 1;
}

static BOOL environment_is_zero(const char *name)
{
    char value[4];
    return GetEnvironmentVariableA(name, value, sizeof(value)) == 1 && value[0] == '0';
}

static int validate_inherited_state(const char *stage)
{
    char value[64];
    HANDLE event;
    SOCKET socket_handle;
    DWORD flags, type_size = sizeof(int);
    int socket_type = 0;
    int socket_error;
    WSADATA data;

    if (GetEnvironmentVariableA("VKMT_HANDOFF_SENTINEL", value, sizeof(value)) != 16 ||
        strcmp(value, "phase5-no-tso-ok"))
        return fail(stage, "environment", 0);
    if (!environment_is_zero("FEX_TSOENABLED") ||
        !environment_is_zero("FEX_VECTORTSOENABLED") ||
        !environment_is_zero("FEX_MEMCPYSETTSOENABLED"))
        return fail(stage, "TSO environment", 0);
    if (GetFileAttributesW(L"handoff.cwd") == INVALID_FILE_ATTRIBUTES)
        return fail(stage, "current directory", 0);
    if (GetFileType(GetStdHandle(STD_OUTPUT_HANDLE)) != FILE_TYPE_PIPE ||
        GetFileType(GetStdHandle(STD_ERROR_HANDLE)) != FILE_TYPE_PIPE)
        return fail(stage, "standard handles", 0);

    if (!GetEnvironmentVariableA("VKMT_HANDOFF_EVENT", value, sizeof(value)))
        return fail(stage, "event environment", 0);
    event = (HANDLE)(uintptr_t)_strtoui64(value, NULL, 0);
    if (!GetHandleInformation(event, &flags)) return fail(stage, "event handle", 0);

    if (!GetEnvironmentVariableA("VKMT_HANDOFF_SOCKET", value, sizeof(value)))
        return fail(stage, "socket environment", 0);
    socket_handle = (SOCKET)(uintptr_t)_strtoui64(value, NULL, 0);
    if (!GetHandleInformation((HANDLE)socket_handle, &flags))
        return fail(stage, "socket handle", 0);
    if (WSAStartup(MAKEWORD(2, 2), &data)) return fail(stage, "WSAStartup", 0);
    /* Windows inherits the underlying kernel handle, but Winsock deliberately
     * does not adopt it into another process's socket table. Cross-process
     * socket use requires WSADuplicateSocket()/WSASocket(); accepting this raw
     * handle as a socket would be a Wine incompatibility. */
    if (!getsockopt(socket_handle, SOL_SOCKET, SO_TYPE, (char *)&socket_type,
                    (int *)&type_size))
    {
        WSACleanup();
        return fail(stage, "raw inherited socket unexpectedly adopted", socket_type);
    }
    socket_error = WSAGetLastError();
    if (socket_error != WSAENOTSOCK)
    {
        WSACleanup();
        return fail(stage, "raw inherited socket error", socket_error);
    }
    WSACleanup();
    printf("NO_TSO_PHASE5_%s_STATE_OK\n", stage);
    fflush(stdout);
    return 0;
}

static int launch_and_wait(const WCHAR *application, const WCHAR *arguments)
{
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    WCHAR command[32768];
    DWORD exit_code;

    memset(&startup, 0, sizeof(startup));
    memset(&process, 0, sizeof(process));
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    if (swprintf(command, sizeof(command) / sizeof(command[0]), L"\"%ls\" %ls",
                 application, arguments) < 0)
        return 20;
    if (!CreateProcessW(application, command, NULL, NULL, TRUE, CREATE_NO_WINDOW,
                        NULL, NULL, &startup, &process))
        return 21;
    CloseHandle(process.hThread);
    if (WaitForSingleObject(process.hProcess, 30000) != WAIT_OBJECT_0)
    {
        CloseHandle(process.hProcess);
        return 22;
    }
    if (!GetExitCodeProcess(process.hProcess, &exit_code)) exit_code = 23;
    CloseHandle(process.hProcess);
    return (int)exit_code;
}

static int run_service(const WCHAR *x64_executable)
{
    WCHAR arguments[32768];
    int ret;
    if ((ret = validate_inherited_state("SERVICE"))) return ret;
    swprintf(arguments, sizeof(arguments) / sizeof(arguments[0]),
             L"--client \"%ls\"", x64_executable);
    if ((ret = launch_and_wait(x64_executable, arguments)))
        return fail("SERVICE", "launch x64 client", ret);
    puts("NO_TSO_PHASE5_SERVICE_EXIT_OK");
    return 0;
}

static int run_client(const WCHAR *x64_executable)
{
    int ret;
    if ((ret = validate_inherited_state("X64_CLIENT"))) return ret;
    if ((ret = launch_and_wait(x64_executable, L"--webhelper")))
        return fail("X64_CLIENT", "launch webhelper", ret);
    puts("NO_TSO_PHASE5_X64_CLIENT_EXIT_OK");
    return 0;
}

static int run_webhelper(void)
{
    char value[64];
    HANDLE event;
    int ret;
    if ((ret = validate_inherited_state("X64_WEBHELPER"))) return ret;
    if (!GetEnvironmentVariableA("VKMT_HANDOFF_EVENT", value, sizeof(value)))
        return fail("X64_WEBHELPER", "event environment", 0);
    event = (HANDLE)(uintptr_t)_strtoui64(value, NULL, 0);
    if (!SetEvent(event)) return fail("X64_WEBHELPER", "SetEvent", 0);
    puts("NO_TSO_PHASE5_X64_WEBHELPER_EXIT_OK");
    return 0;
}

static int run_root(const WCHAR *service_executable, const WCHAR *x64_executable,
                    const WCHAR *working_directory)
{
    SECURITY_ATTRIBUTES security = { sizeof(security), NULL, TRUE };
    HANDLE event = NULL, read_pipe = NULL, write_pipe = NULL, marker = INVALID_HANDLE_VALUE;
    HANDLE old_stdout = GetStdHandle(STD_OUTPUT_HANDLE);
    HANDLE old_stderr = GetStdHandle(STD_ERROR_HANDLE);
    SOCKET socket_handle = INVALID_SOCKET;
    SOCKET raw_socket = INVALID_SOCKET;
    WCHAR arguments[32768];
    char handle_value[64], output[16384];
    DWORD bytes, total = 0;
    WSADATA data;
    int ret = 1;

    if (!SetCurrentDirectoryW(working_directory)) return fail("ROOT", "SetCurrentDirectory", 0);
    marker = CreateFileW(L"handoff.cwd", GENERIC_WRITE, FILE_SHARE_READ, NULL,
                         CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (marker == INVALID_HANDLE_VALUE) return fail("ROOT", "cwd marker", 0);
    CloseHandle(marker);
    marker = INVALID_HANDLE_VALUE;

    event = CreateEventW(&security, TRUE, FALSE, NULL);
    if (!event || !CreatePipe(&read_pipe, &write_pipe, &security, 0) ||
        !SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0))
        goto done;
    if (WSAStartup(MAKEWORD(2, 2), &data)) goto done;
    raw_socket = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, NULL, 0, 0);
    if (raw_socket == INVALID_SOCKET ||
        !DuplicateHandle(GetCurrentProcess(), (HANDLE)raw_socket, GetCurrentProcess(),
                         (HANDLE *)&socket_handle, 0, TRUE, DUPLICATE_SAME_ACCESS))
        goto done;
    closesocket(raw_socket);
    raw_socket = INVALID_SOCKET;

    SetEnvironmentVariableA("VKMT_HANDOFF_SENTINEL", "phase5-no-tso-ok");
    _snprintf(handle_value, sizeof(handle_value), "%llu",
              (unsigned long long)(uintptr_t)event);
    SetEnvironmentVariableA("VKMT_HANDOFF_EVENT", handle_value);
    _snprintf(handle_value, sizeof(handle_value), "%llu",
              (unsigned long long)(uintptr_t)socket_handle);
    SetEnvironmentVariableA("VKMT_HANDOFF_SOCKET", handle_value);

    SetStdHandle(STD_OUTPUT_HANDLE, write_pipe);
    SetStdHandle(STD_ERROR_HANDLE, write_pipe);
    swprintf(arguments, sizeof(arguments) / sizeof(arguments[0]),
             L"--service \"%ls\"", x64_executable);
    ret = launch_and_wait(service_executable, arguments);
    SetStdHandle(STD_OUTPUT_HANDLE, old_stdout);
    SetStdHandle(STD_ERROR_HANDLE, old_stderr);
    CloseHandle(write_pipe);
    write_pipe = NULL;
    while (ReadFile(read_pipe, output + total, sizeof(output) - total - 1, &bytes, NULL) && bytes)
        total += bytes;
    output[total] = 0;
    fprintf(stderr, "%s", output);

    if (ret) { ret = fail("ROOT", "service chain exit", ret); goto done; }
    if (WaitForSingleObject(event, 0) != WAIT_OBJECT_0)
    {
        ret = fail("ROOT", "webhelper event", 0);
        goto done;
    }
    if (!strstr(output, "NO_TSO_PHASE5_SERVICE_STATE_OK") ||
        !strstr(output, "NO_TSO_PHASE5_X64_CLIENT_STATE_OK") ||
        !strstr(output, "NO_TSO_PHASE5_X64_WEBHELPER_STATE_OK") ||
        !strstr(output, "NO_TSO_PHASE5_SERVICE_EXIT_OK") ||
        !strstr(output, "NO_TSO_PHASE5_X64_CLIENT_EXIT_OK") ||
        !strstr(output, "NO_TSO_PHASE5_X64_WEBHELPER_EXIT_OK"))
    {
        ret = fail("ROOT", "child markers", total);
        goto done;
    }
    puts("NO_TSO_PHASE5_HANDOFF_CHAIN_OK");
    ret = 0;

done:
    if (write_pipe) CloseHandle(write_pipe);
    if (read_pipe) CloseHandle(read_pipe);
    if (event) CloseHandle(event);
    if (socket_handle != INVALID_SOCKET) closesocket(socket_handle);
    if (raw_socket != INVALID_SOCKET) closesocket(raw_socket);
    WSACleanup();
    return ret;
}

int wmain(int argc, WCHAR **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    if (argc == 5 && !wcscmp(argv[1], L"--root"))
        return run_root(argv[2], argv[3], argv[4]);
    if (argc == 3 && !wcscmp(argv[1], L"--service"))
        return run_service(argv[2]);
    if (argc == 3 && !wcscmp(argv[1], L"--client"))
        return run_client(argv[2]);
    if (argc == 2 && !wcscmp(argv[1], L"--webhelper"))
        return run_webhelper();
    return 2;
}
