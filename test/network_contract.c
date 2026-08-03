/* VKMT WinSock contract: deterministic loopback, readiness, async I/O, and
 * close-race coverage.  It deliberately uses no external DNS or network. */
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__arm64ec__) || defined(_M_ARM64EC)
# define VKMT_ARCH "arm64ec"
#elif defined(__aarch64__) || defined(_M_ARM64)
# define VKMT_ARCH "arm64"
#elif defined(__i386__) || defined(_M_IX86)
# define VKMT_ARCH "i386"
#elif defined(__x86_64__) || defined(_M_X64)
# define VKMT_ARCH "x86_64"
#else
# define VKMT_ARCH "unknown"
#endif

#ifndef SIO_ADDRESS_LIST_SORT
# define SIO_ADDRESS_LIST_SORT _WSAIORW(IOC_WS2, 25)
#endif

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define PARALLEL_THREADS 8
#define PARALLEL_ROUNDS 4

static unsigned int failures;

static void cap(const char *api, const char *status, int error, const char *detail)
{
    printf("NETWORK_CAP\t%s\t%s\t%s\t%d\t%s\n", VKMT_ARCH, api, status,
           error, detail ? detail : "-");
}

static void fail(const char *api, int error, const char *detail)
{
    ++failures;
    cap(api, "FAIL", error, detail);
}

static int make_listener(int family, SOCKET *listener, struct sockaddr_storage *address,
        int *address_size)
{
    SOCKET socket_handle;
    int one = 1;

    socket_handle = socket(family, SOCK_STREAM, IPPROTO_TCP);
    if (socket_handle == INVALID_SOCKET) return WSAGetLastError();
    setsockopt(socket_handle, SOL_SOCKET, SO_REUSEADDR, (const char *)&one, sizeof(one));
    memset(address, 0, sizeof(*address));
    if (family == AF_INET)
    {
        struct sockaddr_in *v4 = (struct sockaddr_in *)address;
        v4->sin_family = AF_INET;
        v4->sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        *address_size = sizeof(*v4);
    }
    else
    {
        struct sockaddr_in6 *v6 = (struct sockaddr_in6 *)address;
        v6->sin6_family = AF_INET6;
        v6->sin6_addr = in6addr_loopback;
        *address_size = sizeof(*v6);
    }
    if (bind(socket_handle, (const struct sockaddr *)address, *address_size) ||
        listen(socket_handle, 64) ||
        getsockname(socket_handle, (struct sockaddr *)address, address_size))
    {
        int error = WSAGetLastError();
        closesocket(socket_handle);
        return error;
    }
    *listener = socket_handle;
    return 0;
}

static int make_connection(int family, SOCKET *listener, SOCKET *client, SOCKET *server,
        struct sockaddr_storage *address, int *address_size)
{
    int error;

    *listener = *client = *server = INVALID_SOCKET;
    error = make_listener(family, listener, address, address_size);
    if (error) return error;
    *client = socket(family, SOCK_STREAM, IPPROTO_TCP);
    if (*client == INVALID_SOCKET) return WSAGetLastError();
    if (connect(*client, (const struct sockaddr *)address, *address_size))
        return WSAGetLastError();
    *server = accept(*listener, NULL, NULL);
    if (*server == INVALID_SOCKET) return WSAGetLastError();
    return 0;
}

static void close_triplet(SOCKET listener, SOCKET client, SOCKET server)
{
    if (server != INVALID_SOCKET) closesocket(server);
    if (client != INVALID_SOCKET) closesocket(client);
    if (listener != INVALID_SOCKET) closesocket(listener);
}

/* Keep the contract fixture bounded even when a provider loses a connection
 * during the stress case.  A blocking accept here used to make an all-arch
 * run wait forever after the first failed client. */
static int wait_socket_readable(SOCKET socket_handle, DWORD timeout_ms)
{
    fd_set read_set;
    struct timeval timeout;

    timeout.tv_sec = timeout_ms / 1000;
    timeout.tv_usec = (timeout_ms % 1000) * 1000;
    FD_ZERO(&read_set);
    FD_SET(socket_handle, &read_set);
    return select(0, &read_set, NULL, NULL, &timeout) == 1;
}

static void test_loopback_family(int family, const char *api)
{
    SOCKET listener, client, server;
    struct sockaddr_storage address;
    int address_size, error, sent, received;
    char send_byte = 'V', receive_byte = 0;

    error = make_connection(family, &listener, &client, &server, &address, &address_size);
    if (error)
    {
        if (family == AF_INET6 &&
            (error == WSAEAFNOSUPPORT || error == WSAEINVAL || error == WSAEPROTONOSUPPORT))
            cap(api, "SKIP", error, "IPv6 unavailable on this host");
        else
            fail(api, error, "loopback setup");
        close_triplet(listener, client, server);
        return;
    }
    sent = send(client, &send_byte, 1, 0);
    received = recv(server, &receive_byte, 1, 0);
    if (sent != 1 || received != 1 || receive_byte != send_byte)
        fail(api, WSAGetLastError(), "loopback payload");
    else
        cap(api, "PASS", 0, "loopback send/recv");
    close_triplet(listener, client, server);
}

static void test_address_order(void)
{
    ADDRINFOW hints, *result = NULL, *entry;
    int families[8], count = 0, status;
    struct
    {
        SOCKET_ADDRESS_LIST list;
        SOCKET_ADDRESS extra;
    } addresses;
    struct sockaddr_in ipv4;
    struct sockaddr_in6 ipv6;
    SOCKET socket_handle;
    DWORD bytes = 0;
    int ret;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    status = GetAddrInfoW(L"localhost", NULL, &hints, &result);
    if (status)
    {
        fail("dns_localhost", status, "GetAddrInfoW");
        return;
    }
    for (entry = result; entry && count < (int)ARRAY_SIZE(families); entry = entry->ai_next)
        families[count++] = entry->ai_family;
    FreeAddrInfoW(result);
    if (!count)
        fail("dns_localhost", WSAHOST_NOT_FOUND, "no localhost result");
    else
        cap("dns_localhost", "PASS", 0, "offline localhost address enumeration");

    socket_handle = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP);
    if (socket_handle == INVALID_SOCKET)
    {
        cap("SIO_ADDRESS_LIST_SORT", "SKIP", WSAGetLastError(), "IPv6 socket unavailable");
        return;
    }
    memset(&addresses, 0, sizeof(addresses));
    memset(&ipv4, 0, sizeof(ipv4));
    memset(&ipv6, 0, sizeof(ipv6));
    ipv4.sin_family = AF_INET;
    ipv6.sin6_family = AF_INET6;
    addresses.list.iAddressCount = 2;
    addresses.list.Address[0].lpSockaddr = (SOCKADDR *)&ipv6;
    addresses.list.Address[0].iSockaddrLength = sizeof(ipv6);
    addresses.list.Address[1].lpSockaddr = (SOCKADDR *)&ipv4;
    addresses.list.Address[1].iSockaddrLength = sizeof(ipv4);
    ret = WSAIoctl(socket_handle, SIO_ADDRESS_LIST_SORT, &addresses, sizeof(addresses),
                   &addresses, sizeof(addresses), &bytes, NULL, NULL);
    if (ret && (WSAGetLastError() == WSAEOPNOTSUPP || WSAGetLastError() == WSAEINVAL))
        cap("SIO_ADDRESS_LIST_SORT", "UNSUPPORTED", WSAGetLastError(),
            "provider does not expose address-list sorting");
    else if (ret || addresses.list.Address[0].lpSockaddr->sa_family != AF_INET ||
             addresses.list.Address[1].lpSockaddr->sa_family != AF_INET6)
        fail("SIO_ADDRESS_LIST_SORT", WSAGetLastError(), "IPv4 before IPv6 ordering");
    else
        cap("SIO_ADDRESS_LIST_SORT", "PASS", 0, "IPv4 before IPv6");
    closesocket(socket_handle);
}

static void test_nonblocking_connect(void)
{
    SOCKET listener = INVALID_SOCKET, client = INVALID_SOCKET, server = INVALID_SOCKET;
    struct sockaddr_storage address;
    int address_size, error, nonblocking = 1, result, socket_error = 0;
    fd_set write_set;
    struct timeval timeout = {5, 0};

    error = make_listener(AF_INET, &listener, &address, &address_size);
    if (error) { fail("nonblocking_connect", error, "listener"); return; }
    client = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (client == INVALID_SOCKET || ioctlsocket(client, FIONBIO, (u_long *)&nonblocking))
    {
        fail("nonblocking_connect", WSAGetLastError(), "FIONBIO");
        close_triplet(listener, client, server);
        return;
    }
    result = connect(client, (const struct sockaddr *)&address, address_size);
    error = result ? WSAGetLastError() : 0;
    if (result && error != WSAEWOULDBLOCK && error != WSAEINPROGRESS && error != WSAEALREADY)
    {
        fail("nonblocking_connect", error, "connect result");
        close_triplet(listener, client, server);
        return;
    }
    server = accept(listener, NULL, NULL);
    FD_ZERO(&write_set);
    FD_SET(client, &write_set);
    if (select(0, NULL, &write_set, NULL, &timeout) <= 0 ||
        getsockopt(client, SOL_SOCKET, SO_ERROR, (char *)&socket_error, &(int){sizeof(socket_error)}) ||
        socket_error)
        fail("nonblocking_connect", socket_error ? socket_error : WSAGetLastError(),
             "select/SO_ERROR completion");
    else
        cap("nonblocking_connect", "PASS", 0, "FIONBIO plus writable completion");
    close_triplet(listener, client, server);
}

static int make_data_connection(SOCKET *client, SOCKET *server, SOCKET *listener)
{
    struct sockaddr_storage address;
    int address_size;
    return make_connection(AF_INET, listener, client, server, &address, &address_size);
}

static void test_select_poll(void)
{
    SOCKET client, server, listener;
    char byte = 'S', received = 0;
    fd_set read_set;
    struct timeval timeout = {5, 0};
    WSAPOLLFD pollfd;
    int result;

    if (make_data_connection(&client, &server, &listener))
    {
        fail("select", WSAGetLastError(), "connection");
        return;
    }
    send(client, &byte, 1, 0);
    FD_ZERO(&read_set); FD_SET(server, &read_set);
    result = select(0, &read_set, NULL, NULL, &timeout);
    if (result != 1 || recv(server, &received, 1, 0) != 1 || received != byte)
        fail("select", WSAGetLastError(), "read readiness");
    else
        cap("select", "PASS", 0, "read readiness");
    close_triplet(listener, client, server);

    if (make_data_connection(&client, &server, &listener))
    {
        fail("WSAPoll", WSAGetLastError(), "connection");
        return;
    }
    send(client, &byte, 1, 0);
    memset(&pollfd, 0, sizeof(pollfd));
    pollfd.fd = server; pollfd.events = POLLRDNORM;
    result = WSAPoll(&pollfd, 1, 5000);
    if (result != 1 || !(pollfd.revents & POLLRDNORM) || recv(server, &received, 1, 0) != 1)
        fail("WSAPoll", WSAGetLastError(), "read readiness");
    else
        cap("WSAPoll", "PASS", 0, "read readiness");
    close_triplet(listener, client, server);
}

static void test_event_select_rearm(void)
{
    SOCKET client = INVALID_SOCKET, server = INVALID_SOCKET, listener = INVALID_SOCKET;
    WSAEVENT event = WSA_INVALID_EVENT;
    WSANETWORKEVENTS network_events;
    char byte = 'E', received = 0;
    DWORD wait_result;

    if (make_data_connection(&client, &server, &listener))
    {
        fail("WSAEventSelect", WSAGetLastError(), "connection");
        return;
    }
    event = WSACreateEvent();
    if (event == WSA_INVALID_EVENT || WSAEventSelect(server, event, FD_READ | FD_CLOSE))
    {
        fail("WSAEventSelect", WSAGetLastError(), "event registration");
        goto done;
    }
    if (send(client, &byte, 1, 0) != 1 ||
        (wait_result = WSAWaitForMultipleEvents(1, &event, FALSE, 5000, FALSE)) != WSA_WAIT_EVENT_0 ||
        WSAEnumNetworkEvents(server, event, &network_events) ||
        !(network_events.lNetworkEvents & FD_READ) || recv(server, &received, 1, 0) != 1)
    {
        fail("WSAEventSelect", WSAGetLastError(), "first notification");
        goto done;
    }
    /* Re-register after consuming the first notification; a lost rearm is a
     * common source of Chromium socket stalls. */
    if (WSAEventSelect(server, event, FD_READ | FD_CLOSE) || send(client, &byte, 1, 0) != 1 ||
        WSAWaitForMultipleEvents(1, &event, FALSE, 5000, FALSE) != WSA_WAIT_EVENT_0 ||
        WSAEnumNetworkEvents(server, event, &network_events) ||
        !(network_events.lNetworkEvents & FD_READ) || recv(server, &received, 1, 0) != 1)
        fail("WSAEventSelect_rearm", WSAGetLastError(), "second notification");
    else
        cap("WSAEventSelect_rearm", "PASS", 0, "event notification and rearm");
done:
    if (event != WSA_INVALID_EVENT) WSACloseEvent(event);
    close_triplet(listener, client, server);
}

static void test_overlapped_iocp(void)
{
    SOCKET listener = INVALID_SOCKET, client = INVALID_SOCKET, server = INVALID_SOCKET;
    struct sockaddr_storage address;
    int address_size, error;
    HANDLE port = NULL;
    OVERLAPPED overlapped;
    WSABUF buffer;
    char bytes[32] = {0};
    const char payload[] = "VKMT_IOCP";
    DWORD immediate = 0, transferred = 0;
    DWORD flags = 0;
    ULONG_PTR key = 0;
    OVERLAPPED *completed = NULL;

    error = make_listener(AF_INET, &listener, &address, &address_size);
    if (error) { fail("overlapped_iocp", error, "listener"); return; }
    client = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, NULL, 0, WSA_FLAG_OVERLAPPED);
    if (client == INVALID_SOCKET || connect(client, (const struct sockaddr *)&address, address_size))
    {
        fail("overlapped_iocp", WSAGetLastError(), "overlapped connect");
        close_triplet(listener, client, server);
        return;
    }
    server = accept(listener, NULL, NULL);
    port = CreateIoCompletionPort((HANDLE)client, NULL, 0x564b4d54, 0);
    memset(&overlapped, 0, sizeof(overlapped));
    buffer.buf = bytes; buffer.len = sizeof(bytes);
    error = WSARecv(client, &buffer, 1, &immediate, &flags, &overlapped, NULL);
    if (error == SOCKET_ERROR && WSAGetLastError() != WSA_IO_PENDING)
    {
        fail("overlapped_iocp", WSAGetLastError(), "WSARecv");
        goto done;
    }
    send(server, payload, sizeof(payload) - 1, 0);
    if (!port || !GetQueuedCompletionStatus(port, &transferred, &key, &completed, 5000) ||
        completed != &overlapped || key != 0x564b4d54 ||
        transferred != sizeof(payload) - 1 || memcmp(bytes, payload, transferred))
        fail("overlapped_iocp", GetLastError(), "completion lifetime/payload");
    else
        cap("overlapped_iocp", "PASS", 0, "WSARecv completion port");
done:
    if (port) CloseHandle(port);
    close_triplet(listener, client, server);
}

struct parallel_state
{
    struct sockaddr_storage address;
    int address_size;
    volatile LONG errors;
};

static DWORD WINAPI parallel_client(void *opaque)
{
    struct parallel_state *state = opaque;
    int round;
    for (round = 0; round < PARALLEL_ROUNDS; ++round)
    {
        SOCKET socket_handle = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        char byte = (char)round;
        if (socket_handle == INVALID_SOCKET ||
            connect(socket_handle, (const struct sockaddr *)&state->address, state->address_size) ||
            send(socket_handle, &byte, 1, 0) != 1)
            InterlockedIncrement(&state->errors);
        if (socket_handle != INVALID_SOCKET)
        {
            shutdown(socket_handle, SD_BOTH);
            closesocket(socket_handle);
        }
    }
    return 0;
}

static void test_parallel_close(void)
{
    struct parallel_state state;
    SOCKET listener = INVALID_SOCKET;
    HANDLE threads[PARALLEL_THREADS] = {0};
    int i, accepted = 0;
    int error;
    DWORD deadline;

    memset(&state, 0, sizeof(state));
    error = make_listener(AF_INET, &listener, &state.address, &state.address_size);
    if (error) { fail("parallel_close", error, "listener"); return; }
    {
        u_long nonblocking = 1;
        if (ioctlsocket(listener, FIONBIO, &nonblocking))
        {
            fail("parallel_close", WSAGetLastError(), "nonblocking listener");
            closesocket(listener);
            return;
        }
    }
    for (i = 0; i < PARALLEL_THREADS; ++i)
        threads[i] = CreateThread(NULL, 0, parallel_client, &state, 0, NULL);
    deadline = GetTickCount() + 15000;
    while (accepted < PARALLEL_THREADS * PARALLEL_ROUNDS &&
           (LONG)(GetTickCount() - deadline) < 0)
    {
        DWORD now = GetTickCount(), remaining = deadline - now;
        SOCKET peer;
        char byte;
        if (!wait_socket_readable(listener, remaining > 1000 ? 1000 : remaining))
            continue;
        peer = accept(listener, NULL, NULL);
        if (peer == INVALID_SOCKET)
        {
            if (WSAGetLastError() == WSAEWOULDBLOCK) continue;
            InterlockedIncrement(&state.errors);
            break;
        }
        if (!wait_socket_readable(peer, 1000) || recv(peer, &byte, 1, 0) != 1)
            InterlockedIncrement(&state.errors);
        closesocket(peer);
        ++accepted;
    }
    for (i = 0; i < PARALLEL_THREADS; ++i)
    {
        if (threads[i])
        {
            WaitForSingleObject(threads[i], 10000);
            CloseHandle(threads[i]);
        }
    }
    closesocket(listener);
    if (state.errors || accepted != PARALLEL_THREADS * PARALLEL_ROUNDS)
        fail("parallel_close", state.errors, "parallel connect/send/close");
    else
        cap("parallel_close", "PASS", 0, "parallel connections and close races");
}

int main(void)
{
    WSADATA data;

    if (WSAStartup(MAKEWORD(2, 2), &data))
    {
        fail("WSAStartup", WSAGetLastError(), "Winsock startup");
        return 1;
    }
    test_loopback_family(AF_INET, "ipv4_loopback");
    test_loopback_family(AF_INET6, "ipv6_loopback");
    test_address_order();
    test_nonblocking_connect();
    test_select_poll();
    test_event_select_rearm();
    test_overlapped_iocp();
    test_parallel_close();
    WSACleanup();
    if (failures)
    {
        fprintf(stderr, "NETWORK_CONTRACT_FAIL failures=%u\n", failures);
        return 1;
    }
    puts("NETWORK_CONTRACT_OK");
    return 0;
}
