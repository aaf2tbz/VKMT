#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <mswsock.h>
#include <stdio.h>

int main(void)
{
    WSAQUERYSETW query = {0};
    unsigned char buffer[1024];
    WSAQUERYSETW *result = (WSAQUERYSETW *)buffer;
    HANDLE lookup = NULL;
    DWORD len = sizeof(buffer);
    WSADATA data;
    int ret;

    if (WSAStartup(MAKEWORD(2, 2), &data))
    {
        puts("FAIL WSAStartup");
        return 1;
    }
    query.dwSize = sizeof(query);
    query.dwNameSpace = NS_NLA;
    ret = WSALookupServiceBeginW(&query, LUP_RETURN_ALL | LUP_DEEP, &lookup);
    printf("BEGIN ret=%d error=%d handle=%p\n", ret, WSAGetLastError(), lookup);
    if (ret) return 2;
    ret = WSALookupServiceNextW(lookup, 0, &len, result);
    printf("NEXT ret=%d error=%d len=%lu namespace=%lu blob=%p\n",
           ret, WSAGetLastError(), (unsigned long)len,
           (unsigned long)result->dwNameSpace, result->lpBlob);
    if (ret || !result->lpBlob) return 3;
    ret = WSALookupServiceEnd(lookup);
    printf("END ret=%d error=%d\n", ret, WSAGetLastError());
    WSACleanup();
    return ret ? 4 : 0;
}
