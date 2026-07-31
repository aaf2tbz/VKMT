#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <winternl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define CV_ROUNDS 50000
#define SOCKET_COUNT 4
#define SOCKET_CHUNK 4096
#define SOCKET_ROUNDS 4096
#define SOCKET_BYTES ((LONG64)SOCKET_CHUNK * SOCKET_ROUNDS)

typedef NTSTATUS (WINAPI *rtl_wait_on_address_fn)(const void *, const void *, SIZE_T,
                                                  const LARGE_INTEGER *);
typedef void (WINAPI *rtl_wake_address_fn)(const void *);

struct address_test
{
    rtl_wait_on_address_fn wait_on_address;
    rtl_wake_address_fn wake_address;
    LONG sequence;
    LONG acknowledged;
    LONG failed;
};

struct cv_test
{
    CRITICAL_SECTION lock;
    CONDITION_VARIABLE producer_cv;
    CONDITION_VARIABLE consumer_cv;
    LONG sequence;
    LONG acknowledged;
    LONG failed;
};

static DWORD WINAPI address_producer(void *opaque)
{
    struct address_test *test = opaque;
    LONG i;

    for (i = 1; i <= CV_ROUNDS && !test->failed; ++i)
    {
        LONG expected = i - 1;
        while (*(volatile LONG *)&test->acknowledged != expected)
        {
            NTSTATUS status = test->wait_on_address(&test->acknowledged, &expected,
                                                    sizeof(expected), NULL);
            if (status)
            {
                fprintf(stderr, "STEAM_SCHED_FAIL phase=address producer_wait status=%08lx round=%ld\n",
                        (unsigned long)status, i);
                InterlockedExchange(&test->failed, 1);
                return 1;
            }
        }
        InterlockedExchange(&test->sequence, i);
        test->wake_address(&test->sequence);
    }
    return 0;
}

static DWORD WINAPI address_consumer(void *opaque)
{
    struct address_test *test = opaque;
    LONG i;

    for (i = 1; i <= CV_ROUNDS && !test->failed; ++i)
    {
        LONG expected = i - 1;
        while (*(volatile LONG *)&test->sequence != i)
        {
            NTSTATUS status = test->wait_on_address(&test->sequence, &expected,
                                                    sizeof(expected), NULL);
            if (status)
            {
                fprintf(stderr, "STEAM_SCHED_FAIL phase=address consumer_wait status=%08lx round=%ld\n",
                        (unsigned long)status, i);
                InterlockedExchange(&test->failed, 1);
                return 1;
            }
        }
        InterlockedExchange(&test->acknowledged, i);
        test->wake_address(&test->acknowledged);
    }
    return 0;
}

static int run_address_test(void)
{
    struct address_test test;
    HMODULE ntdll;
    HANDLE threads[2] = {0};
    DWORD wait;
    int ret = 1;

    memset(&test, 0, sizeof(test));
    ntdll = GetModuleHandleW(L"ntdll.dll");
    test.wait_on_address = (rtl_wait_on_address_fn)GetProcAddress(ntdll, "RtlWaitOnAddress");
    test.wake_address = (rtl_wake_address_fn)GetProcAddress(ntdll, "RtlWakeAddressSingle");
    if (!test.wait_on_address || !test.wake_address)
    {
        fprintf(stderr, "STEAM_SCHED_FAIL phase=address exports\n");
        return 1;
    }

    threads[0] = CreateThread(NULL, 0, address_producer, &test, 0, NULL);
    threads[1] = CreateThread(NULL, 0, address_consumer, &test, 0, NULL);
    if (!threads[0] || !threads[1])
    {
        fprintf(stderr, "STEAM_SCHED_FAIL phase=address create_thread winerr=%lu\n", GetLastError());
        goto done;
    }

    wait = WaitForMultipleObjects(2, threads, TRUE, 60000);
    if (wait != WAIT_OBJECT_0 || test.failed || test.acknowledged != CV_ROUNDS)
    {
        fprintf(stderr, "STEAM_SCHED_FAIL phase=address wait=%lu seq=%ld ack=%ld failed=%ld\n",
                wait, test.sequence, test.acknowledged, test.failed);
        goto done;
    }

    printf("STEAM_SCHED_ADDRESS_OK rounds=%d\n", CV_ROUNDS);
    ret = 0;

done:
    if (threads[0]) CloseHandle(threads[0]);
    if (threads[1]) CloseHandle(threads[1]);
    return ret;
}

struct socket_test;

struct sender
{
    struct socket_test *test;
    SOCKET socket;
    unsigned int index;
    LONG64 sent;
    LONG failed;
};

struct socket_test
{
    CRITICAL_SECTION lock;
    CONDITION_VARIABLE ready_cv;
    struct sender senders[SOCKET_COUNT];
    SOCKET receivers[SOCKET_COUNT];
    LONG epoch;
    LONG abort;
    LONG failed;
    LONG64 received;
    LONG64 checksum;
};

static DWORD WINAPI cv_producer(void *opaque)
{
    struct cv_test *test = opaque;
    LONG i;

    for (i = 1; i <= CV_ROUNDS && !test->failed; ++i)
    {
        EnterCriticalSection(&test->lock);
        while (test->acknowledged != i - 1 && !test->failed)
        {
            if (!SleepConditionVariableCS(&test->producer_cv, &test->lock, 5000) &&
                GetLastError() == ERROR_TIMEOUT)
            {
                fprintf(stderr, "STEAM_SCHED_FAIL phase=cv producer_timeout round=%ld seq=%ld ack=%ld\n",
                        i, test->sequence, test->acknowledged);
                InterlockedExchange(&test->failed, 1);
            }
        }
        if (!test->failed)
        {
            InterlockedExchange(&test->sequence, i);
            WakeConditionVariable(&test->consumer_cv);
        }
        LeaveCriticalSection(&test->lock);
    }
    return test->failed ? 1 : 0;
}

static DWORD WINAPI cv_consumer(void *opaque)
{
    struct cv_test *test = opaque;
    LONG i;

    for (i = 1; i <= CV_ROUNDS && !test->failed; ++i)
    {
        EnterCriticalSection(&test->lock);
        while (test->sequence != i && !test->failed)
        {
            if (!SleepConditionVariableCS(&test->consumer_cv, &test->lock, 5000) &&
                GetLastError() == ERROR_TIMEOUT)
            {
                fprintf(stderr, "STEAM_SCHED_FAIL phase=cv consumer_timeout round=%ld seq=%ld ack=%ld\n",
                        i, test->sequence, test->acknowledged);
                InterlockedExchange(&test->failed, 1);
            }
        }
        if (!test->failed)
        {
            InterlockedExchange(&test->acknowledged, i);
            WakeConditionVariable(&test->producer_cv);
        }
        LeaveCriticalSection(&test->lock);
    }
    return test->failed ? 1 : 0;
}

static int run_cv_test(void)
{
    struct cv_test test;
    HANDLE threads[2] = {0};
    DWORD wait;
    int ret = 1;

    memset(&test, 0, sizeof(test));
    InitializeCriticalSection(&test.lock);
    InitializeConditionVariable(&test.producer_cv);
    InitializeConditionVariable(&test.consumer_cv);

    threads[0] = CreateThread(NULL, 0, cv_producer, &test, 0, NULL);
    threads[1] = CreateThread(NULL, 0, cv_consumer, &test, 0, NULL);
    if (!threads[0] || !threads[1])
    {
        fprintf(stderr, "STEAM_SCHED_FAIL phase=cv create_thread winerr=%lu\n", GetLastError());
        goto done;
    }

    wait = WaitForMultipleObjects(2, threads, TRUE, 60000);
    if (wait != WAIT_OBJECT_0 || test.failed || test.acknowledged != CV_ROUNDS)
    {
        fprintf(stderr, "STEAM_SCHED_FAIL phase=cv wait=%lu seq=%ld ack=%ld failed=%ld\n",
                wait, test.sequence, test.acknowledged, test.failed);
        InterlockedExchange(&test.failed, 1);
        WakeAllConditionVariable(&test.producer_cv);
        WakeAllConditionVariable(&test.consumer_cv);
        goto done;
    }

    printf("STEAM_SCHED_CV_OK rounds=%d\n", CV_ROUNDS);
    ret = 0;

done:
    if (threads[0]) CloseHandle(threads[0]);
    if (threads[1]) CloseHandle(threads[1]);
    DeleteCriticalSection(&test.lock);
    return ret;
}

static DWORD WINAPI socket_sender(void *opaque)
{
    struct sender *sender = opaque;
    struct socket_test *test = sender->test;
    unsigned char buffer[SOCKET_CHUNK];
    unsigned int round;

    memset(buffer, sender->index + 1, sizeof(buffer));
    for (round = 0; round < SOCKET_ROUNDS && !test->abort; ++round)
    {
        int offset = 0;
        while (offset != sizeof(buffer) && !test->abort)
        {
            int written = send(sender->socket, (const char *)buffer + offset,
                               sizeof(buffer) - offset, 0);
            if (written == SOCKET_ERROR)
            {
                fprintf(stderr, "STEAM_SCHED_FAIL phase=socket send slot=%u round=%u wsa=%d\n",
                        sender->index, round, WSAGetLastError());
                InterlockedExchange(&sender->failed, 1);
                InterlockedExchange(&test->failed, 1);
                InterlockedExchange(&test->abort, 1);
                break;
            }
            offset += written;
            InterlockedAdd64(&sender->sent, written);
        }

        EnterCriticalSection(&test->lock);
        InterlockedIncrement(&test->epoch);
        WakeConditionVariable(&test->ready_cv);
        LeaveCriticalSection(&test->lock);

        if ((round & 31) == 31) Sleep(1);
    }
    shutdown(sender->socket, SD_SEND);
    EnterCriticalSection(&test->lock);
    InterlockedIncrement(&test->epoch);
    WakeConditionVariable(&test->ready_cv);
    LeaveCriticalSection(&test->lock);
    return sender->failed ? 1 : 0;
}

static int create_loopback_pair(SOCKET *sender, SOCKET *receiver)
{
    struct sockaddr_in address;
    int address_size = sizeof(address);
    SOCKET listener = INVALID_SOCKET;
    u_long nonblocking = 1;
    int ret = 1;

    *sender = INVALID_SOCKET;
    *receiver = INVALID_SOCKET;
    listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listener == INVALID_SOCKET) goto done;

    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) ||
        listen(listener, 1) ||
        getsockname(listener, (struct sockaddr *)&address, &address_size))
        goto done;

    *sender = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (*sender == INVALID_SOCKET ||
        connect(*sender, (struct sockaddr *)&address, sizeof(address)))
        goto done;

    *receiver = accept(listener, NULL, NULL);
    if (*receiver == INVALID_SOCKET ||
        ioctlsocket(*receiver, FIONBIO, &nonblocking))
        goto done;

    ret = 0;

done:
    if (listener != INVALID_SOCKET) closesocket(listener);
    if (ret)
    {
        if (*sender != INVALID_SOCKET) closesocket(*sender);
        if (*receiver != INVALID_SOCKET) closesocket(*receiver);
        *sender = INVALID_SOCKET;
        *receiver = INVALID_SOCKET;
    }
    return ret;
}

static DWORD WINAPI socket_consumer(void *opaque)
{
    struct socket_test *test = opaque;
    WSAPOLLFD pollfds[SOCKET_COUNT];
    unsigned char buffer[16384];
    const LONG64 target = SOCKET_BYTES * SOCKET_COUNT;
    LONG observed_epoch = 0;
    int timeouts = 0;
    unsigned int i;

    memset(pollfds, 0, sizeof(pollfds));
    for (i = 0; i < SOCKET_COUNT; ++i)
    {
        pollfds[i].fd = test->receivers[i];
        pollfds[i].events = POLLRDNORM;
    }

    while (test->received != target && !test->abort)
    {
        int ready = WSAPoll(pollfds, SOCKET_COUNT, 0);
        int progressed = 0;

        if (ready == SOCKET_ERROR)
        {
            fprintf(stderr, "STEAM_SCHED_FAIL phase=socket poll wsa=%d\n", WSAGetLastError());
            InterlockedExchange(&test->failed, 1);
            break;
        }

        if (ready)
        {
            for (i = 0; i < SOCKET_COUNT; ++i)
            {
                if (!(pollfds[i].revents & (POLLRDNORM | POLLHUP))) continue;
                for (;;)
                {
                    int count = recv(test->receivers[i], (char *)buffer, sizeof(buffer), 0);
                    int j;

                    if (count > 0)
                    {
                        LONG64 sum = 0;
                        for (j = 0; j < count; ++j) sum += buffer[j];
                        InterlockedAdd64(&test->received, count);
                        InterlockedAdd64(&test->checksum, sum);
                        progressed = 1;
                        continue;
                    }
                    if (!count) break;
                    if (WSAGetLastError() == WSAEWOULDBLOCK) break;
                    fprintf(stderr, "STEAM_SCHED_FAIL phase=socket recv slot=%u wsa=%d\n",
                            i, WSAGetLastError());
                    InterlockedExchange(&test->failed, 1);
                    InterlockedExchange(&test->abort, 1);
                    break;
                }
            }
        }

        if (!progressed && test->received != target && !test->abort)
        {
            EnterCriticalSection(&test->lock);
            if (observed_epoch == test->epoch)
            {
                if (!SleepConditionVariableCS(&test->ready_cv, &test->lock, 2000) &&
                    GetLastError() == ERROR_TIMEOUT)
                {
                    ++timeouts;
                    fprintf(stderr,
                            "STEAM_SCHED_DIAG phase=socket wake_timeout count=%d epoch=%ld received=%lld\n",
                            timeouts, test->epoch, (long long)test->received);
                    if (timeouts == 3)
                    {
                        InterlockedExchange(&test->failed, 1);
                        InterlockedExchange(&test->abort, 1);
                    }
                }
            }
            observed_epoch = test->epoch;
            LeaveCriticalSection(&test->lock);
        }
    }

    if (test->failed || test->received != target)
        return 1;
    return 0;
}

static int run_socket_test(void)
{
    struct socket_test test;
    HANDLE send_threads[SOCKET_COUNT] = {0};
    HANDLE consumer = NULL;
    WSADATA data;
    LONG64 expected_checksum = 0;
    DWORD wait;
    unsigned int i;
    int ret = 1;

    memset(&test, 0, sizeof(test));
    for (i = 0; i < SOCKET_COUNT; ++i)
        test.receivers[i] = test.senders[i].socket = INVALID_SOCKET;

    if (WSAStartup(MAKEWORD(2, 2), &data))
    {
        fprintf(stderr, "STEAM_SCHED_FAIL phase=socket startup wsa=%d\n", WSAGetLastError());
        return 1;
    }
    InitializeCriticalSection(&test.lock);
    InitializeConditionVariable(&test.ready_cv);

    for (i = 0; i < SOCKET_COUNT; ++i)
    {
        test.senders[i].test = &test;
        test.senders[i].index = i;
        if (create_loopback_pair(&test.senders[i].socket, &test.receivers[i]))
        {
            fprintf(stderr, "STEAM_SCHED_FAIL phase=socket pair slot=%u wsa=%d\n",
                    i, WSAGetLastError());
            goto done;
        }
        expected_checksum += SOCKET_BYTES * (i + 1);
    }

    consumer = CreateThread(NULL, 0, socket_consumer, &test, 0, NULL);
    if (!consumer) goto thread_failed;
    for (i = 0; i < SOCKET_COUNT; ++i)
    {
        send_threads[i] = CreateThread(NULL, 0, socket_sender, &test.senders[i], 0, NULL);
        if (!send_threads[i]) goto thread_failed;
    }

    wait = WaitForSingleObject(consumer, 90000);
    if (wait != WAIT_OBJECT_0)
    {
        fprintf(stderr, "STEAM_SCHED_FAIL phase=socket consumer_wait=%lu received=%lld epoch=%ld\n",
                wait, (long long)test.received, test.epoch);
        InterlockedExchange(&test.failed, 1);
        InterlockedExchange(&test.abort, 1);
        WakeAllConditionVariable(&test.ready_cv);
        goto done;
    }
    wait = WaitForMultipleObjects(SOCKET_COUNT, send_threads, TRUE, 30000);
    if (wait != WAIT_OBJECT_0 || test.failed ||
        test.received != SOCKET_BYTES * SOCKET_COUNT ||
        test.checksum != expected_checksum)
    {
        fprintf(stderr,
                "STEAM_SCHED_FAIL phase=socket sender_wait=%lu failed=%ld received=%lld checksum=%lld expected=%lld\n",
                wait, test.failed, (long long)test.received, (long long)test.checksum,
                (long long)expected_checksum);
        goto done;
    }

    printf("STEAM_SCHED_SOCKET_OK sockets=%d bytes=%lld epochs=%ld checksum=%lld\n",
           SOCKET_COUNT, (long long)test.received, test.epoch, (long long)test.checksum);
    ret = 0;
    goto done;

thread_failed:
    fprintf(stderr, "STEAM_SCHED_FAIL phase=socket create_thread winerr=%lu\n", GetLastError());
    InterlockedExchange(&test.failed, 1);
    InterlockedExchange(&test.abort, 1);
    WakeAllConditionVariable(&test.ready_cv);

done:
    for (i = 0; i < SOCKET_COUNT; ++i)
    {
        if (send_threads[i]) CloseHandle(send_threads[i]);
        if (test.senders[i].socket != INVALID_SOCKET) closesocket(test.senders[i].socket);
        if (test.receivers[i] != INVALID_SOCKET) closesocket(test.receivers[i]);
    }
    if (consumer) CloseHandle(consumer);
    DeleteCriticalSection(&test.lock);
    WSACleanup();
    return ret;
}

int main(void)
{
    if (run_address_test()) return 1;
    if (run_cv_test()) return 1;
    if (run_socket_test()) return 2;
    puts("STEAM_SCHEDULER_WAKEUP_OK");
    return 0;
}
