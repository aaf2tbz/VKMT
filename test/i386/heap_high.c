/* Verifies that ordinary i386 heap allocations remain writable when Wine
 * places them in the high half of the guest address space. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    HANDLE heap = GetProcessHeap();
    unsigned char *block;
    unsigned char *crt_block;
    unsigned char *aligned_block;
    SIZE_T size = 0x4000;

    block = HeapAlloc(heap, HEAP_ZERO_MEMORY, size);
    if (!block) return 10;
    memset(block, 0x5a, size);
    if (block[0] != 0x5a || block[size - 1] != 0x5a) return 11;
    printf("P5_I386_HEAP_WRITABLE ptr=%08lx\n", (unsigned long)(ULONG_PTR)block);
    if (!HeapFree(heap, 0, block)) return 12;

    crt_block = malloc(size);
    if (!crt_block) return 20;
    memset(crt_block, 0xa5, size);
    if (crt_block[0] != 0xa5 || crt_block[size - 1] != 0xa5) return 21;
    printf("P5_I386_CRT_MALLOC_WRITABLE ptr=%08lx\n", (unsigned long)(ULONG_PTR)crt_block);
    free(crt_block);

    aligned_block = _aligned_malloc(size, 64);
    if (!aligned_block || ((ULONG_PTR)aligned_block & 63)) return 30;
    memset(aligned_block, 0x3c, size);
    if (aligned_block[0] != 0x3c || aligned_block[size - 1] != 0x3c) return 31;
    printf("P5_I386_ALIGNED_MALLOC_WRITABLE ptr=%08lx\n", (unsigned long)(ULONG_PTR)aligned_block);
    _aligned_free(aligned_block);
    return 0;
}
