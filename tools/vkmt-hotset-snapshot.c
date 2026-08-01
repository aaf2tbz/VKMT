#include <errno.h>
#include <libproc.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define MAX_PIDS 4096
#define MAX_REGIONS 32768

struct region {
    char path[PROC_PIDPATHINFO_MAXSIZE];
    uint64_t offset;
    uint64_t mapped;
    uint64_t resident;
    unsigned samples;
};

static struct region regions[MAX_REGIONS];
static size_t region_count;
static long page_size;

static int seen_pid(const pid_t *pids, size_t count, pid_t pid)
{
    for (size_t i = 0; i < count; ++i) if (pids[i] == pid) return 1;
    return 0;
}

static size_t collect_tree(pid_t root, pid_t *pids)
{
    size_t count = 1;
    pids[0] = root;
    for (size_t cursor = 0; cursor < count && count < MAX_PIDS; ++cursor) {
        pid_t children[512];
        int bytes = proc_listchildpids(pids[cursor], children, sizeof(children));
        if (bytes <= 0) continue;
        size_t child_count = (size_t)bytes / sizeof(children[0]);
        for (size_t i = 0; i < child_count && count < MAX_PIDS; ++i) {
            if (children[i] > 0 && !seen_pid(pids, count, children[i])) pids[count++] = children[i];
        }
    }
    return count;
}

static void record_region(const char *path, uint64_t offset, uint64_t mapped, uint64_t resident)
{
    if (!path[0] || !resident) return;
    for (size_t i = 0; i < region_count; ++i) {
        if (regions[i].offset == offset && regions[i].mapped == mapped && !strcmp(regions[i].path, path)) {
            if (resident > regions[i].resident) regions[i].resident = resident;
            ++regions[i].samples;
            return;
        }
    }
    if (region_count == MAX_REGIONS) return;
    struct region *entry = &regions[region_count++];
    snprintf(entry->path, sizeof(entry->path), "%s", path);
    entry->offset = offset;
    entry->mapped = mapped;
    entry->resident = resident;
    entry->samples = 1;
}

static void sample_pid(pid_t pid)
{
    uint64_t address = 0;
    for (;;) {
        struct proc_regionwithpathinfo info;
        int bytes = proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &info, sizeof(info));
        if (bytes != (int)sizeof(info)) break;
        const struct proc_regioninfo *vm = &info.prp_prinfo;
        uint64_t next = vm->pri_address + vm->pri_size;
        if (next <= address) break;
        if (info.prp_vip.vip_path[0]) {
            uint64_t resident = (uint64_t)vm->pri_pages_resident * (uint64_t)page_size;
            record_region(info.prp_vip.vip_path, vm->pri_offset, vm->pri_size, resident);
        }
        address = next;
    }

    struct proc_fdinfo fds[4096];
    int fd_bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, sizeof(fds));
    if (fd_bytes <= 0) return;
    size_t fd_count = (size_t)fd_bytes / sizeof(fds[0]);
    for (size_t i = 0; i < fd_count; ++i) {
        if (fds[i].proc_fdtype != PROX_FDTYPE_VNODE) continue;
        struct vnode_fdinfowithpath vnode;
        int got = proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDVNODEPATHINFO, &vnode, sizeof(vnode));
        if (got != (int)sizeof(vnode) || !vnode.pvip.vip_path[0]) continue;
        uint64_t size = (uint64_t)vnode.pvip.vip_vi.vi_stat.vst_size;
        if (!size) continue;
        if (size > UINT64_C(1048576)) size = UINT64_C(1048576);
        record_region(vnode.pvip.vip_path, 0, size, (uint64_t)page_size);
    }
}

static uint64_t monotonic_ns(void)
{
    struct timespec value;
    clock_gettime(CLOCK_MONOTONIC, &value);
    return (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
}

int main(int argc, char **argv)
{
    if (argc < 4) {
        fprintf(stderr, "usage: %s OUTPUT.tsv SECONDS COMMAND [ARG ...]\n", argv[0]);
        return 2;
    }
    char *end = NULL;
    double seconds = strtod(argv[2], &end);
    if (!end || *end || seconds <= 0.0 || seconds > 30.0) return 2;
    page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) return 2;

    pid_t child = fork();
    if (child < 0) { perror("fork"); return 1; }
    if (!child) {
        setpgid(0, 0);
        execvp(argv[3], &argv[3]);
        perror("execvp");
        _exit(127);
    }
    setpgid(child, child);

    uint64_t deadline = monotonic_ns() + (uint64_t)(seconds * 1000000000.0);
    int child_status = 0;
    int exited = 0;
    unsigned sample_count = 0;
    do {
        pid_t pids[MAX_PIDS];
        size_t count = collect_tree(child, pids);
        for (size_t i = 0; i < count; ++i) sample_pid(pids[i]);
        ++sample_count;
        pid_t result = waitpid(child, &child_status, WNOHANG);
        if (result == child) { exited = 1; break; }
        struct timespec pause = {0, 50000000};
        nanosleep(&pause, NULL);
    } while (monotonic_ns() < deadline);

    if (!exited) {
        if (waitpid(child, &child_status, 0) < 0) { perror("waitpid"); return 1; }
    }

    FILE *output = fopen(argv[1], "w");
    if (!output) { perror(argv[1]); return 1; }
    fprintf(output, "path\toffset\tmapped_bytes\tresident_bytes\tsamples\n");
    for (size_t i = 0; i < region_count; ++i) {
        for (char *p = regions[i].path; *p; ++p) if (*p == '\t' || *p == '\n') *p = '_';
        fprintf(output, "%s\t%llu\t%llu\t%llu\t%u\n", regions[i].path,
                (unsigned long long)regions[i].offset, (unsigned long long)regions[i].mapped,
                (unsigned long long)regions[i].resident, regions[i].samples);
    }
    fclose(output);
    fprintf(stderr, "VKMT_HOTSET_SNAPSHOT_OK samples=%u regions=%zu\n", sample_count, region_count);
    if (WIFEXITED(child_status)) return WEXITSTATUS(child_status);
    if (WIFSIGNALED(child_status)) return 128 + WTERMSIG(child_status);
    return 1;
}
