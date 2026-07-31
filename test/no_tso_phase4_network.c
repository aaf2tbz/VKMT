#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <windows.h>
#include <winhttp.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DOWNLOAD_COUNT 8
#define RANGE_BYTES (4u * 1024u * 1024u)
#define READ_BYTES 65536u
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

static const wchar_t package_host[] = L"client-update.steamstatic.com";
static const wchar_t package_path[] =
    L"/steamui_websrc_all.zip.vz.eafcb4aedb55ba1695abbdf9e0df6354a2ea1a92_26734899";
struct download_slot
{
    HINTERNET connection;
    HINTERNET request;
    HINTERNET previous_request;
    HANDLE done;
    HANDLE output;
    DWORD index;
    DWORD status_code;
    DWORD content_length;
    DWORD total;
    DWORD reads;
    DWORD segment_size;
    DWORD segment_received;
    DWORD callback_status;
    volatile LONG finished;
    volatile LONG error;
    unsigned char buffer[READ_BYTES];
};

static BOOL submit_range(struct download_slot *slot, DWORD first, DWORD last);

struct close_server
{
    SOCKET listener;
    volatile LONG error;
};

static DWORD WINAPI close_server_thread(void *opaque)
{
    struct close_server *server = opaque;
    static const char payload[] = "VKMT_IOCP_PEER_CLOSE";
    SOCKET peer = accept(server->listener, NULL, NULL);
    if (peer == INVALID_SOCKET)
    {
        server->error = WSAGetLastError();
        return 1;
    }
    Sleep(50); /* Ensure the client receive is pending when data arrives. */
    if (send(peer, payload, sizeof(payload), 0) != sizeof(payload))
        server->error = WSAGetLastError();
    Sleep(50); /* Ensure the follow-up receive is pending at peer close. */
    shutdown(peer, SD_BOTH);
    closesocket(peer);
    return server->error ? 1 : 0;
}

static int test_iocp_peer_close(void)
{
    struct close_server server;
    struct sockaddr_in address;
    int address_size = sizeof(address);
    HANDLE server_thread = NULL, port = NULL;
    SOCKET client = INVALID_SOCKET;
    DWORD total = 0;
    WSADATA data;
    int result = 0;

    memset(&server, 0, sizeof(server));
    if (WSAStartup(MAKEWORD(2, 2), &data)) return 1;
    server.listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (server.listener == INVALID_SOCKET) { result = 2; goto done; }
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(server.listener, (struct sockaddr *)&address, sizeof(address)) ||
        listen(server.listener, 1) ||
        getsockname(server.listener, (struct sockaddr *)&address, &address_size))
    {
        result = 3;
        goto done;
    }
    server_thread = CreateThread(NULL, 0, close_server_thread, &server, 0, NULL);
    if (!server_thread) { result = 4; goto done; }

    client = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, NULL, 0, WSA_FLAG_OVERLAPPED);
    if (client == INVALID_SOCKET ||
        connect(client, (struct sockaddr *)&address, sizeof(address)))
    {
        result = 5;
        goto done;
    }
    port = CreateIoCompletionPort((HANDLE)client, NULL, 0x564b4d54, 0);
    if (!port) { result = 6; goto done; }

    for (;;)
    {
        OVERLAPPED overlapped;
        WSABUF buffer;
        DWORD flags = 0, immediate = 0, transferred = 0;
        ULONG_PTR key = 0;
        OVERLAPPED *completed = NULL;
        char bytes[4096];
        int ret;

        memset(&overlapped, 0, sizeof(overlapped));
        buffer.buf = bytes;
        buffer.len = sizeof(bytes);
        ret = WSARecv(client, &buffer, 1, &immediate, &flags, &overlapped, NULL);
        if (ret == SOCKET_ERROR && WSAGetLastError() != WSA_IO_PENDING)
        {
            result = 7;
            goto done;
        }
        if (!GetQueuedCompletionStatus(port, &transferred, &key, &completed, 10000))
        {
            result = 8;
            goto done;
        }
        if (completed != &overlapped || key != 0x564b4d54)
        {
            result = 9;
            goto done;
        }
        fprintf(stderr, "NO_TSO_PHASE4_TRACE slot=8 transition=completion consumed "
                "status=IOCP bytes=%lu total=%lu error=0\n", transferred, total);
        if (!transferred) break;
        total += transferred;
    }
    if (total != sizeof("VKMT_IOCP_PEER_CLOSE")) result = 10;
    if (!result) puts("NO_TSO_PHASE4_IOCP_PEER_CLOSE_OK");

done:
    if (client != INVALID_SOCKET) closesocket(client);
    if (server.listener != INVALID_SOCKET) closesocket(server.listener);
    if (server_thread)
    {
        if (WaitForSingleObject(server_thread, 10000) != WAIT_OBJECT_0 && !result) result = 11;
        CloseHandle(server_thread);
    }
    if (port) CloseHandle(port);
    WSACleanup();
    if (server.error && !result) result = 12;
    return result;
}

static void trace_transition(const struct download_slot *slot, const char *transition,
                             DWORD amount)
{
    fprintf(stderr, "NO_TSO_PHASE4_TRACE slot=%lu transition=%s status=%#lx bytes=%lu "
            "total=%lu error=%ld\n", slot->index, transition, slot->callback_status,
            amount, slot->total, slot->error);
    fflush(stderr);
}

static void finish_slot(struct download_slot *slot, DWORD error)
{
    if (error) InterlockedCompareExchange(&slot->error, error, 0);
    if (!InterlockedExchange(&slot->finished, 1)) SetEvent(slot->done);
}

static void issue_available_query(struct download_slot *slot)
{
    if (!WinHttpQueryDataAvailable(slot->request, NULL))
        finish_slot(slot, GetLastError());
}

static void CALLBACK status_callback(HINTERNET handle, DWORD_PTR context, DWORD status,
                                     void *information, DWORD information_length)
{
    struct download_slot *slot = (struct download_slot *)context;
    DWORD size;

    (void)handle;
    if (!slot) return;
    slot->callback_status = status;
    trace_transition(slot, "completion queued", information_length);
    trace_transition(slot, "completion consumed", information_length);

    switch (status)
    {
        case WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE:
            if (!WinHttpReceiveResponse(slot->request, NULL))
                finish_slot(slot, GetLastError());
            break;

        case WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE:
            size = sizeof(slot->status_code);
            if (!WinHttpQueryHeaders(slot->request,
                                     WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                                     WINHTTP_HEADER_NAME_BY_INDEX, &slot->status_code, &size,
                                     WINHTTP_NO_HEADER_INDEX))
            {
                finish_slot(slot, GetLastError());
                break;
            }
            size = sizeof(slot->content_length);
            if (!WinHttpQueryHeaders(slot->request,
                                     WINHTTP_QUERY_CONTENT_LENGTH | WINHTTP_QUERY_FLAG_NUMBER,
                                     WINHTTP_HEADER_NAME_BY_INDEX, &slot->content_length, &size,
                                     WINHTTP_NO_HEADER_INDEX))
            {
                finish_slot(slot, GetLastError());
                break;
            }
            if (slot->status_code != HTTP_STATUS_PARTIAL_CONTENT ||
                slot->content_length != slot->segment_size)
            {
                finish_slot(slot, ERROR_INVALID_DATA);
                break;
            }
            trace_transition(slot, "socket readable", 0);
            issue_available_query(slot);
            break;

        case WINHTTP_CALLBACK_STATUS_DATA_AVAILABLE:
        {
            DWORD available = information_length == sizeof(DWORD) ? *(DWORD *)information : 0;
            DWORD requested;
            if (!available)
            {
                finish_slot(slot, slot->total == RANGE_BYTES ? 0 : ERROR_HANDLE_EOF);
                break;
            }
            requested = min(available, (DWORD)sizeof(slot->buffer));
            requested = min(requested, slot->segment_size - slot->segment_received);
            trace_transition(slot, "socket readable", available);
            if (!WinHttpReadData(slot->request, slot->buffer, requested, NULL))
                finish_slot(slot, GetLastError());
            break;
        }

        case WINHTTP_CALLBACK_STATUS_READ_COMPLETE:
            if (!information_length)
            {
                finish_slot(slot, slot->total == RANGE_BYTES ? 0 : ERROR_HANDLE_EOF);
                break;
            }
            else
            {
                DWORD written = 0;
                if (!WriteFile(slot->output, information, information_length, &written, NULL) ||
                    written != information_length)
                {
                    finish_slot(slot, GetLastError());
                    break;
                }
                slot->total += information_length;
                slot->segment_received += information_length;
                ++slot->reads;
                trace_transition(slot, "bytes received", information_length);
                if (slot->segment_received == slot->segment_size)
                {
                    trace_transition(slot, "package committed", slot->total);
                    if (slot->total == RANGE_BYTES)
                        finish_slot(slot, 0);
                    else if (!submit_range(slot, slot->total, RANGE_BYTES - 1))
                        finish_slot(slot, GetLastError());
                }
                else if (slot->segment_received > slot->segment_size || slot->total > RANGE_BYTES)
                    finish_slot(slot, ERROR_INVALID_DATA);
                else
                    issue_available_query(slot);
            }
            break;

        case WINHTTP_CALLBACK_STATUS_REQUEST_ERROR:
            if (information_length == sizeof(WINHTTP_ASYNC_RESULT))
                finish_slot(slot, ((WINHTTP_ASYNC_RESULT *)information)->dwError);
            else
                finish_slot(slot, ERROR_GEN_FAILURE);
            break;
    }
}

static BOOL submit_range(struct download_slot *slot, DWORD first, DWORD last)
{
    WCHAR header[64];
    HINTERNET request;

    if (last < first || last >= RANGE_BYTES)
    {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }
    swprintf(header, ARRAY_SIZE(header), L"Range: bytes=%lu-%lu\r\n", first, last);
    request = WinHttpOpenRequest(slot->connection, L"GET", package_path, NULL,
                                 WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                                 WINHTTP_FLAG_SECURE);
    if (!request ||
        !WinHttpAddRequestHeaders(request, header, (DWORD)-1,
                                  WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE))
    {
        if (request) WinHttpCloseHandle(request);
        return FALSE;
    }
    if (slot->request) slot->previous_request = slot->request;
    slot->request = request;
    slot->segment_size = last - first + 1;
    slot->segment_received = 0;
    trace_transition(slot, "request submitted", slot->segment_size);
    return WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                              WINHTTP_NO_REQUEST_DATA, 0, 0, (DWORD_PTR)slot);
}

int main(int argc, char **argv)
{
    struct download_slot slots[DOWNLOAD_COUNT];
    HANDLE done[DOWNLOAD_COUNT];
    wchar_t output_directory[MAX_PATH * 2];
    HINTERNET session = NULL, connection = NULL;
    DWORD wait;
    int i, created = 0;

    if (argc != 2 || !MultiByteToWideChar(CP_UTF8, 0, argv[1], -1, output_directory,
                                           ARRAY_SIZE(output_directory)))
        return 2;

    memset(slots, 0, sizeof(slots));
    session = WinHttpOpen(L"VKMT-NoTSO-Phase4/1.0", WINHTTP_ACCESS_TYPE_NO_PROXY,
                          WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS,
                          WINHTTP_FLAG_ASYNC);
    if (!session) return 3;
    WinHttpSetTimeouts(session, 10000, 10000, 30000, 30000);
    if (WinHttpSetStatusCallback(session, status_callback,
            WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE |
            WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE |
            WINHTTP_CALLBACK_STATUS_DATA_AVAILABLE |
            WINHTTP_CALLBACK_STATUS_READ_COMPLETE |
            WINHTTP_CALLBACK_STATUS_REQUEST_ERROR,
            0) == WINHTTP_INVALID_STATUS_CALLBACK)
        goto fail;
    connection = WinHttpConnect(session, package_host, INTERNET_DEFAULT_HTTPS_PORT, 0);
    if (!connection) goto fail;

    for (i = 0; i < DOWNLOAD_COUNT; ++i)
    {
        wchar_t output_path[MAX_PATH * 2];
        struct download_slot *slot = &slots[i];
        slot->index = i;
        slot->connection = connection;
        slot->done = CreateEventW(NULL, TRUE, FALSE, NULL);
        done[i] = slot->done;
        if (!slot->done) goto fail;
        swprintf(output_path, ARRAY_SIZE(output_path), L"%ls\\slot-%d.bin",
                 output_directory, i);
        slot->output = CreateFileW(output_path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                                   FILE_ATTRIBUTE_NORMAL, NULL);
        if (slot->output == INVALID_HANDLE_VALUE) goto fail;
        if (i == 0)
        {
            if (!submit_range(slot, 0, RANGE_BYTES / 2 - 1)) goto fail;
        }
        else if (!submit_range(slot, 0, RANGE_BYTES - 1))
            goto fail;
        ++created;
    }

    wait = WaitForMultipleObjects(DOWNLOAD_COUNT, done, TRUE, 180000);
    if (wait != WAIT_OBJECT_0)
    {
        fprintf(stderr, "NO_TSO_PHASE4_FAIL stage=wait value=%lu\n", wait);
        goto fail;
    }
    for (i = 0; i < DOWNLOAD_COUNT; ++i)
    {
        struct download_slot *slot = &slots[i];
        printf("NO_TSO_PHASE4_SLOT slot=%d status=%lu content_length=%lu bytes=%lu "
               "reads=%lu error=%ld\n", i, slot->status_code, slot->content_length,
               slot->total, slot->reads, slot->error);
        if (slot->error || slot->status_code != HTTP_STATUS_PARTIAL_CONTENT ||
            slot->content_length != slot->segment_size || slot->total != RANGE_BYTES)
            goto fail;
    }
    if ((i = test_iocp_peer_close()))
    {
        SetLastError(i);
        goto fail;
    }
    puts("NO_TSO_PHASE4_ASYNC_CDN_OK downloads=8 bytes_each=4194304");

    for (i = 0; i < DOWNLOAD_COUNT; ++i)
    {
        WinHttpCloseHandle(slots[i].request);
        if (slots[i].previous_request) WinHttpCloseHandle(slots[i].previous_request);
        CloseHandle(slots[i].output);
        CloseHandle(slots[i].done);
    }
    WinHttpCloseHandle(connection);
    WinHttpCloseHandle(session);
    return 0;

fail:
    fprintf(stderr, "NO_TSO_PHASE4_FAIL stage=cleanup winerr=%lu created=%d\n",
            GetLastError(), created);
    for (i = 0; i < DOWNLOAD_COUNT; ++i)
    {
        if (slots[i].request) WinHttpCloseHandle(slots[i].request);
        if (slots[i].previous_request) WinHttpCloseHandle(slots[i].previous_request);
        if (slots[i].output && slots[i].output != INVALID_HANDLE_VALUE) CloseHandle(slots[i].output);
        if (slots[i].done) CloseHandle(slots[i].done);
    }
    if (connection) WinHttpCloseHandle(connection);
    if (session) WinHttpCloseHandle(session);
    return 4;
}
