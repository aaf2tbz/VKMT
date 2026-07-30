#include <windows.h>
#include <stdint.h>
#include <stdio.h>

struct __attribute__((packed)) unaligned_values {
  uint8_t pad;
  volatile uint16_t value16;
  volatile uint32_t value32;
  volatile uint64_t value64;
};

static volatile LONG aligned32;
static volatile LONG64 aligned64 __attribute__((aligned(8)));
static struct unaligned_values unaligned;

int main(int argc, char **argv)
{
  FILE *marker;
  uint64_t checksum = 0;

  for (unsigned i = 1; i != 4096; ++i) {
    aligned32 = (LONG)i;
    aligned64 = (LONG64)i * 0x100000001ULL;
    unaligned.value16 = (uint16_t)(i ^ 0x55aaU);
    unaligned.value32 = i ^ 0xa5a55a5aU;
    unaligned.value64 = (uint64_t)i * 0x0101010101010101ULL;
    checksum ^= (uint32_t)aligned32;
    checksum ^= (uint64_t)aligned64;
    checksum ^= unaligned.value16;
    checksum ^= unaligned.value32;
    checksum ^= unaligned.value64;
  }

  if (InterlockedCompareExchange(&aligned32, 0x12345678, 4095) != 4095)
    return 10;
  if (InterlockedCompareExchange64(&aligned64, 0x1122334455667788LL,
                                   4095LL * 0x100000001LL) !=
      4095LL * 0x100000001LL)
    return 11;

  if (argc != 2)
    return 12;
  marker = fopen(argv[1], "wb");
  if (!marker)
    return 13;
  fprintf(marker, "JAVA_TSO_PREFLIGHT_OK checksum=%016llx aligned32=%08lx aligned64=%016llx\n",
          (unsigned long long)checksum, (unsigned long)aligned32,
          (unsigned long long)aligned64);
  return fclose(marker) == 0 ? 0 : 14;
}
