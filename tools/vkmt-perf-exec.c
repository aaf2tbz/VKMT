/* SPDX-License-Identifier: MIT */
/* Execute one benchmark child and append precise macOS process metrics. */
#include <errno.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static unsigned long long monotonic_ns(void)
{
    static mach_timebase_info_data_t timebase;
    const unsigned long long ticks = mach_continuous_time();

    if (!timebase.denom) mach_timebase_info(&timebase);
    return ticks * timebase.numer / timebase.denom;
}

static void append_line(const char *path, const char *header, const char *line)
{
    int fd = open(path, O_CREAT | O_WRONLY | O_APPEND, 0644);
    size_t length = strlen(line);
    off_t size;

    if (fd == -1)
    {
        perror(path);
        exit(125);
    }
    if (flock(fd, LOCK_EX) == -1)
    {
        perror("write benchmark record");
        close(fd);
        exit(125);
    }
    size = lseek(fd, 0, SEEK_END);
    if ((size == 0 && header && write(fd, header, strlen(header)) != (ssize_t)strlen(header)) ||
        write(fd, line, length) != (ssize_t)length)
    {
        perror("write benchmark record");
        close(fd);
        exit(125);
    }
    flock(fd, LOCK_UN);
    close(fd);
}

int main(int argc, char **argv)
{
    struct rusage usage;
    unsigned long long start, end;
    const char *output, *trace, *session, *state, *run_id;
    char line[2048];
    pid_t child;
    int status;

    if (argc < 8)
    {
        fprintf(stderr, "usage: %s OUTPUT TRACE SESSION STATE RUN RUN_ID COMMAND [ARG ...]\n", argv[0]);
        return 2;
    }
    output = argv[1];
    trace = argv[2];
    session = argv[3];
    state = argv[4];
    run_id = argv[6];

    start = monotonic_ns();
    snprintf(line, sizeof(line), "VKMT_PERF_V1\t%llu\t%u\t%u\t%s\tvkmt-launcher\t%s\tlaunch_request\t\n",
             start, getpid(), getpid(), run_id, argv[7]);
    append_line(trace, "schema\tmonotonic_ns\tpid\ttid\trun_id\tcomponent\texecutable\tevent\tdetail\n", line);
    child = fork();
    if (child == -1)
    {
        perror("fork");
        return 125;
    }
    if (!child)
    {
        execvp(argv[7], &argv[7]);
        perror(argv[7]);
        _exit(127);
    }
    snprintf(line, sizeof(line), "VKMT_PERF_V1\t%llu\t%u\t%u\t%s\tvkmt-launcher\t%s\twine_spawn\tchild=%d\n",
             monotonic_ns(), getpid(), getpid(), run_id, argv[7], child);
    append_line(trace, NULL, line);
    if (wait4(child, &status, 0, &usage) == -1)
    {
        perror("wait4");
        return 125;
    }
    end = monotonic_ns();

    if (WIFEXITED(status)) status = WEXITSTATUS(status);
    else if (WIFSIGNALED(status)) status = 128 + WTERMSIG(status);
    else status = 125;

    snprintf(line, sizeof(line), "VKMT_PERF_V1\t%llu\t%u\t%u\t%s\tvkmt-launcher\t%s\tprocess_exit\trc=%d\n",
             end, getpid(), getpid(), run_id, argv[7], status);
    append_line(trace, NULL, line);

    snprintf(line, sizeof(line),
             "%s\t%s\t%s\t%s\t%d\t%.3f\t%.6f\t%.6f\t%ld\t%ld\t%ld\t%ld\t%ld\t%ld\t%ld\n",
             session, state, argv[5], run_id, status, (end - start) / 1000000.0,
             usage.ru_utime.tv_sec + usage.ru_utime.tv_usec / 1000000.0,
             usage.ru_stime.tv_sec + usage.ru_stime.tv_usec / 1000000.0,
             usage.ru_maxrss, usage.ru_minflt, usage.ru_majflt, usage.ru_inblock,
             usage.ru_oublock, usage.ru_nvcsw, usage.ru_nivcsw);
    append_line(output, NULL, line);
    return status;
}
