#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define MAX_ENTRIES 8192
#define BUFFER_SIZE (1024 * 1024)

struct entry {
    char path[PATH_MAX];
    uint64_t offset;
    uint64_t length;
    uint64_t size;
    int64_t mtime;
};

static uint64_t now_ns(void)
{
    struct timespec value;
    clock_gettime(CLOCK_MONOTONIC, &value);
    return (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
}

static int safe_relative(const char *path)
{
    return path[0] && path[0] != '/' && strcmp(path, "..") && strncmp(path, "../", 3) && !strstr(path, "/../");
}

static size_t load_manifest(const char *manifest, const char *root, const char *prefix,
                            struct entry *entries, uint64_t *bytes, unsigned *rejected)
{
    FILE *input = fopen(manifest, "r");
    if (!input) { perror(manifest); exit(1); }
    char line[PATH_MAX + 256];
    size_t count = 0;
    *bytes = 0;
    *rejected = 0;
    if (!fgets(line, sizeof(line), input)) { fclose(input); return 0; }
    while (count < MAX_ENTRIES && fgets(line, sizeof(line), input)) {
        char *scope = strtok(line, "\t");
        char *relative = strtok(NULL, "\t");
        char *offset = strtok(NULL, "\t");
        char *length = strtok(NULL, "\t");
        char *size = strtok(NULL, "\t");
        char *mtime = strtok(NULL, "\t\r\n");
        if (!scope || !relative || !offset || !length || !size || !mtime || !safe_relative(relative)) {
            ++*rejected;
            continue;
        }
        const char *base = !strcmp(scope, "VKMT") ? root : !strcmp(scope, "PREFIX") ? prefix : NULL;
        if (!base) { ++*rejected; continue; }
        struct entry item;
        if (snprintf(item.path, sizeof(item.path), "%s/%s", base, relative) >= (int)sizeof(item.path)) {
            ++*rejected; continue;
        }
        item.offset = strtoull(offset, NULL, 10);
        item.length = strtoull(length, NULL, 10);
        item.size = strtoull(size, NULL, 10);
        item.mtime = strtoll(mtime, NULL, 10);
        struct stat st;
        if (!item.length || stat(item.path, &st) || !S_ISREG(st.st_mode) ||
            (uint64_t)st.st_size != item.size || (int64_t)st.st_mtime != item.mtime ||
            item.offset >= item.size) {
            ++*rejected; continue;
        }
        if (item.length > item.size - item.offset) item.length = item.size - item.offset;
        entries[count++] = item;
        *bytes += item.length;
    }
    fclose(input);
    return count;
}

static int advise_entries(const struct entry *entries, size_t count, uint64_t *advised)
{
    *advised = 0;
    for (size_t i = 0; i < count; ++i) {
        int fd = open(entries[i].path, O_RDONLY | O_CLOEXEC);
        if (fd < 0) continue;
        (void)fcntl(fd, F_RDAHEAD, 1);
        uint64_t cursor = 0;
        while (cursor < entries[i].length) {
            uint64_t remaining = entries[i].length - cursor;
            int amount = remaining > INT_MAX ? INT_MAX : (int)remaining;
            struct radvisory advice = {(off_t)(entries[i].offset + cursor), amount};
            if (fcntl(fd, F_RDADVISE, &advice) == 0) *advised += (uint64_t)amount;
            cursor += (uint64_t)amount;
        }
        close(fd);
    }
    return 0;
}

static int copy_entries(const struct entry *entries, size_t count, const char *output, uint64_t *copied)
{
    int out = open(output, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0600);
    if (out < 0) { perror(output); return 1; }
    (void)fcntl(out, F_NOCACHE, 1);
    unsigned char *buffer = malloc(BUFFER_SIZE);
    if (!buffer) return 1;
    *copied = 0;
    for (size_t i = 0; i < count; ++i) {
        int in = open(entries[i].path, O_RDONLY | O_CLOEXEC);
        if (in < 0) continue;
        (void)fcntl(in, F_NOCACHE, 1);
        uint64_t cursor = 0;
        while (cursor < entries[i].length) {
            size_t wanted = entries[i].length - cursor > BUFFER_SIZE ? BUFFER_SIZE : (size_t)(entries[i].length - cursor);
            ssize_t got = pread(in, buffer, wanted, (off_t)(entries[i].offset + cursor));
            if (got <= 0) break;
            ssize_t done = 0;
            while (done < got) {
                ssize_t written = write(out, buffer + done, (size_t)(got - done));
                if (written <= 0) { close(in); close(out); free(buffer); return 1; }
                done += written;
            }
            cursor += (uint64_t)got;
            *copied += (uint64_t)got;
        }
        close(in);
    }
    fsync(out);
    close(out);
    free(buffer);
    return 0;
}

static int measure_pack(const char *path, const char *mode, unsigned lead_ms)
{
    int prefetch = !strcmp(mode, "prefetch");
    int physical = !strcmp(mode, "physical");
    if (!prefetch && !physical && strcmp(mode, "warm")) return 2;
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) { perror(path); return 1; }
    struct stat st;
    if (fstat(fd, &st)) return 1;
    uint64_t advice_ns = 0;
    if (prefetch) {
        uint64_t start = now_ns();
        (void)fcntl(fd, F_RDAHEAD, 1);
        uint64_t cursor = 0;
        while (cursor < (uint64_t)st.st_size) {
            uint64_t remaining = (uint64_t)st.st_size - cursor;
            int amount = remaining > INT_MAX ? INT_MAX : (int)remaining;
            struct radvisory advice = {(off_t)cursor, amount};
            if (fcntl(fd, F_RDADVISE, &advice)) { perror("F_RDADVISE"); return 1; }
            cursor += (uint64_t)amount;
        }
        advice_ns = now_ns() - start;
        struct timespec delay = {(time_t)(lead_ms / 1000), (long)(lead_ms % 1000) * 1000000L};
        nanosleep(&delay, NULL);
    } else if (physical) {
        (void)fcntl(fd, F_NOCACHE, 1);
    }
    unsigned char *buffer = malloc(BUFFER_SIZE);
    if (!buffer) return 1;
    uint64_t bytes = 0;
    uint64_t start = now_ns();
    for (;;) {
        ssize_t got = read(fd, buffer, BUFFER_SIZE);
        if (got < 0) { perror("read"); return 1; }
        if (!got) break;
        bytes += (uint64_t)got;
    }
    uint64_t stall_ns = now_ns() - start;
    free(buffer);
    close(fd);
    double gbps = stall_ns ? (double)bytes / (double)stall_ns : 0.0;
    printf("VKMT_HOTSET_MEASURE_OK mode=%s bytes=%llu advice_ns=%llu lead_ms=%u stall_ns=%llu gbps=%.6f\n",
           mode, (unsigned long long)bytes,
           (unsigned long long)advice_ns, lead_ms, (unsigned long long)stall_ns, gbps);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc >= 4 && !strcmp(argv[1], "--measure-pack")) {
        unsigned lead = argc >= 5 ? (unsigned)strtoul(argv[4], NULL, 10) : 0;
        return measure_pack(argv[2], argv[3], lead);
    }
    if (argc != 5 && argc != 6) {
        fprintf(stderr, "usage: %s MANIFEST VKMT_ROOT PREFIX --advice\n", argv[0]);
        fprintf(stderr, "       %s MANIFEST VKMT_ROOT PREFIX --pack OUTPUT\n", argv[0]);
        fprintf(stderr, "       %s --measure-pack FILE physical|prefetch|warm [LEAD_MS]\n", argv[0]);
        return 2;
    }
    struct entry *entries = calloc(MAX_ENTRIES, sizeof(*entries));
    if (!entries) return 1;
    uint64_t manifest_bytes;
    unsigned rejected;
    size_t count = load_manifest(argv[1], argv[2], argv[3], entries, &manifest_bytes, &rejected);
    if (!count) { fprintf(stderr, "No valid hot-set entries\n"); return 1; }
    if (!strcmp(argv[4], "--advice") && argc == 5) {
        uint64_t advised;
        uint64_t start = now_ns();
        advise_entries(entries, count, &advised);
        uint64_t elapsed = now_ns() - start;
        printf("VKMT_HOTSET_PREFETCH_OK entries=%zu bytes=%llu advised=%llu rejected=%u elapsed_ns=%llu\n",
               count, (unsigned long long)manifest_bytes, (unsigned long long)advised, rejected,
               (unsigned long long)elapsed);
        return advised ? 0 : 1;
    }
    if (!strcmp(argv[4], "--pack") && argc == 6) {
        uint64_t copied;
        int result = copy_entries(entries, count, argv[5], &copied);
        if (!result) printf("VKMT_HOTSET_PACK_OK entries=%zu bytes=%llu rejected=%u\n",
                            count, (unsigned long long)copied, rejected);
        return result;
    }
    return 2;
}
