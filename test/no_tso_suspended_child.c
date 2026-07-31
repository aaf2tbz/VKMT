#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

static int child_main(int iteration)
{
    printf("SUSPENDED_CHILD_ENTER iteration=%d pid=%lu tid=%lu\n", iteration,
           (unsigned long)GetCurrentProcessId(), (unsigned long)GetCurrentThreadId());
    fflush(stdout);
    return 73;
}

int wmain(int argc, WCHAR **argv)
{
    WCHAR image[MAX_PATH], command[2 * MAX_PATH];
    int iterations = 256;

    if (argc == 3 && !wcscmp(argv[1], L"--child"))
        return child_main(_wtoi(argv[2]));
    if (argc == 2) iterations = _wtoi(argv[1]);
    if (iterations < 1) return 2;
    if (!GetModuleFileNameW(NULL, image, MAX_PATH)) return 3;

    for (int i = 0; i < iterations; ++i)
    {
        PROCESS_INFORMATION process;
        STARTUPINFOW startup = { .cb = sizeof(startup) };
        DWORD wait, exit_code = 0;

        swprintf(command, sizeof(command) / sizeof(command[0]),
                 L"\"%ls\" --child %d", image, i);
        if (!CreateProcessW(image, command, NULL, NULL, TRUE, CREATE_SUSPENDED,
                            NULL, NULL, &startup, &process))
        {
            fprintf(stderr, "SUSPENDED_CHILD_CREATE_FAIL iteration=%d error=%lu\n",
                    i, (unsigned long)GetLastError());
            return 10;
        }
        if ((i & 3) == 1) Sleep(1);
        else if ((i & 3) == 2) Sleep(10);
        if (ResumeThread(process.hThread) != 1)
        {
            fprintf(stderr, "SUSPENDED_CHILD_RESUME_FAIL iteration=%d error=%lu\n",
                    i, (unsigned long)GetLastError());
            TerminateProcess(process.hProcess, 11);
            return 11;
        }
        wait = WaitForSingleObject(process.hProcess, 15000);
        if (wait != WAIT_OBJECT_0 || !GetExitCodeProcess(process.hProcess, &exit_code) || exit_code != 73)
        {
            fprintf(stderr, "SUSPENDED_CHILD_WAIT_FAIL iteration=%d wait=%lu exit=%lu error=%lu\n",
                    i, (unsigned long)wait, (unsigned long)exit_code,
                    (unsigned long)GetLastError());
            TerminateProcess(process.hProcess, 12);
            return 12;
        }
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
    }
    printf("NO_TSO_SUSPENDED_CHILD_RESUME_OK iterations=%d\n", iterations);
    return 0;
}
