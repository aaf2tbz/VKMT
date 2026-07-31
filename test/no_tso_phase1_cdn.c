#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winhttp.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DOWNLOAD_COUNT 8
#define RANGE_BYTES (4u * 1024u * 1024u)

static const wchar_t package_host[] = L"client-update.steamstatic.com";
static const wchar_t package_path[] =
    L"/steamui_websrc_all.zip.vz.eafcb4aedb55ba1695abbdf9e0df6354a2ea1a92_26734899";
static const wchar_t range_header[] = L"Range: bytes=0-4194303\r\n";

struct download_slot
{
    const wchar_t *output_directory;
    DWORD index;
    DWORD status_code;
    DWORD content_length;
    DWORD total;
    DWORD reads;
    DWORD error;
};

static void slot_trace(const struct download_slot *slot, const char *stage)
{
    fprintf(stderr, "NO_TSO_CDN_TRACE slot=%lu stage=%s bytes=%lu error=%lu\n",
            slot->index, stage, slot->total, slot->error);
    fflush(stderr);
}

static void slot_fail(struct download_slot *slot, DWORD error)
{
    if (!slot->error) slot->error = error ? error : ERROR_GEN_FAILURE;
}

static DWORD WINAPI download_thread(void *opaque)
{
    struct download_slot *slot = opaque;
    HINTERNET session = NULL, connection = NULL, request = NULL;
    HANDLE output = INVALID_HANDLE_VALUE;
    wchar_t output_path[MAX_PATH * 2];
    unsigned char buffer[65536];
    DWORD size;

    swprintf(output_path, sizeof(output_path) / sizeof(output_path[0]),
             L"%ls\\slot-%lu.bin", slot->output_directory, slot->index);
    slot_trace(slot, "thread-start");
    output = CreateFileW(output_path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                         FILE_ATTRIBUTE_NORMAL, NULL);
    if (output == INVALID_HANDLE_VALUE)
    {
        slot_fail(slot, GetLastError());
        goto done;
    }
    slot_trace(slot, "output-open");

    session = WinHttpOpen(L"VKMT-NoTSO-Phase1/1.0",
                          WINHTTP_ACCESS_TYPE_NO_PROXY,
                          WINHTTP_NO_PROXY_NAME,
                          WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session)
    {
        slot_fail(slot, GetLastError());
        goto done;
    }
    slot_trace(slot, "session-open");
    WinHttpSetTimeouts(session, 10000, 10000, 30000, 30000);
    connection = WinHttpConnect(session, package_host, INTERNET_DEFAULT_HTTPS_PORT, 0);
    if (!connection)
    {
        slot_fail(slot, GetLastError());
        goto done;
    }
    slot_trace(slot, "connection-open");
    request = WinHttpOpenRequest(connection, L"GET", package_path, NULL,
                                 WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                                 WINHTTP_FLAG_SECURE);
    if (!request)
    {
        slot_fail(slot, GetLastError());
        goto done;
    }
    slot_trace(slot, "request-open");
    if (!WinHttpAddRequestHeaders(request, range_header, (DWORD)-1,
                                  WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE))
    {
        slot_fail(slot, GetLastError());
        goto done;
    }
    slot_trace(slot, "range-added");
    if (!WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                            WINHTTP_NO_REQUEST_DATA, 0, 0, 0))
    {
        slot_fail(slot, GetLastError());
        goto done;
    }
    slot_trace(slot, "request-sent");
    if (!WinHttpReceiveResponse(request, NULL))
    {
        slot_fail(slot, GetLastError());
        goto done;
    }
    slot_trace(slot, "response-received");

    size = sizeof(slot->status_code);
    if (!WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX, &slot->status_code, &size,
                             WINHTTP_NO_HEADER_INDEX))
    {
        slot_fail(slot, GetLastError());
        goto done;
    }
    size = sizeof(slot->content_length);
    if (!WinHttpQueryHeaders(request, WINHTTP_QUERY_CONTENT_LENGTH | WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX, &slot->content_length, &size,
                             WINHTTP_NO_HEADER_INDEX))
    {
        slot_fail(slot, GetLastError());
        goto done;
    }
    if (slot->status_code != HTTP_STATUS_PARTIAL_CONTENT ||
        slot->content_length != RANGE_BYTES)
    {
        slot_fail(slot, ERROR_INVALID_DATA);
        goto done;
    }
    slot_trace(slot, "headers-validated");

    while (slot->total < RANGE_BYTES)
    {
        DWORD available = 0, requested, received = 0, written = 0;
        if (!WinHttpQueryDataAvailable(request, &available))
        {
            slot_fail(slot, GetLastError());
            break;
        }
        if (!available)
        {
            slot_fail(slot, ERROR_HANDLE_EOF);
            break;
        }
        requested = available < sizeof(buffer) ? available : sizeof(buffer);
        if (requested > RANGE_BYTES - slot->total) requested = RANGE_BYTES - slot->total;
        if (!WinHttpReadData(request, buffer, requested, &received) || !received)
        {
            slot_fail(slot, GetLastError());
            break;
        }
        if (!WriteFile(output, buffer, received, &written, NULL) || written != received)
        {
            slot_fail(slot, GetLastError());
            break;
        }
        slot->total += received;
        ++slot->reads;
    }
    if (!slot->error) slot_trace(slot, "payload-complete");

done:
    if (output != INVALID_HANDLE_VALUE) CloseHandle(output);
    if (request) WinHttpCloseHandle(request);
    if (connection) WinHttpCloseHandle(connection);
    if (session) WinHttpCloseHandle(session);
    slot_trace(slot, "thread-exit");
    return slot->error ? 1 : 0;
}

int main(int argc, char **argv)
{
    struct download_slot slots[DOWNLOAD_COUNT];
    HANDLE threads[DOWNLOAD_COUNT];
    wchar_t output_directory[MAX_PATH * 2];
    DWORD wait;
    int i, download_count = DOWNLOAD_COUNT;

    if (argc != 2 && argc != 3)
    {
        fprintf(stderr, "usage: no_tso_phase1_cdn.exe OUTPUT_DIRECTORY\n");
        return 2;
    }
    if (argc == 3)
    {
        download_count = atoi(argv[2]);
        if (download_count < 1 || download_count > DOWNLOAD_COUNT) return 2;
    }
    if (!MultiByteToWideChar(CP_UTF8, 0, argv[1], -1, output_directory,
                             sizeof(output_directory) / sizeof(output_directory[0])))
        return 3;

    memset(slots, 0, sizeof(slots));
    memset(threads, 0, sizeof(threads));
    for (i = 0; i < download_count; ++i)
    {
        slots[i].output_directory = output_directory;
        slots[i].index = i;
        threads[i] = CreateThread(NULL, 0, download_thread, &slots[i], 0, NULL);
        if (!threads[i])
        {
            fprintf(stderr, "NO_TSO_CDN_FAIL slot=%d create_thread winerr=%lu\n",
                    i, GetLastError());
            return 4;
        }
    }
    wait = WaitForMultipleObjects(download_count, threads, TRUE, 180000);
    if (wait != WAIT_OBJECT_0)
    {
        fprintf(stderr, "NO_TSO_CDN_FAIL wait=%lu\n", wait);
        return 5;
    }

    for (i = 0; i < download_count; ++i)
    {
        CloseHandle(threads[i]);
        printf("NO_TSO_CDN_SLOT slot=%d status=%lu content_length=%lu bytes=%lu reads=%lu error=%lu\n",
               i, slots[i].status_code, slots[i].content_length, slots[i].total,
               slots[i].reads, slots[i].error);
        if (slots[i].error || slots[i].status_code != HTTP_STATUS_PARTIAL_CONTENT ||
            slots[i].content_length != RANGE_BYTES || slots[i].total != RANGE_BYTES)
            return 6;
    }
    printf("NO_TSO_CDN_OK downloads=%d bytes_each=%u aggregate=%u\n",
           download_count, RANGE_BYTES, download_count * RANGE_BYTES);
    return 0;
}
