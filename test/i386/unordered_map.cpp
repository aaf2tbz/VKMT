#include <windows.h>
#include <stdio.h>
#include <unordered_map>

int main()
{
    std::unordered_map<unsigned int, unsigned int> map;
    for (unsigned int i = 0; i != 8192; ++i) map.emplace(i, i ^ 0x5a5a5a5aU);
    for (unsigned int i = 0; i != 8192; ++i)
        if (map.at(i) != (i ^ 0x5a5a5a5aU)) return 10;
    printf("P5_I386_UNORDERED_MAP_OK buckets=%lu\n", (unsigned long)map.bucket_count());
    return 0;
}
