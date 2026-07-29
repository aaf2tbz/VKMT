/* Exercise the same i386 winpthreads condition-variable handoff used by
 * vkd3d-proton's D3D12 fence worker. */
#include <windows.h>
#include <pthread.h>
#include <stdio.h>

static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
static int worker_ready, release_worker;

static void write_marker(const char *path, const char *text)
{
    HANDLE file = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    DWORD written;
    if (file != INVALID_HANDLE_VALUE)
    {
        WriteFile(file, text, (DWORD)strlen(text), &written, NULL);
        CloseHandle(file);
    }
}

static void *worker(void *arg)
{
    (void)arg;
    pthread_mutex_lock(&mutex);
    worker_ready = 1;
    pthread_cond_signal(&cond);
    while (!release_worker) pthread_cond_wait(&cond, &mutex);
    pthread_mutex_unlock(&mutex);
    return NULL;
}

int main(int argc, char **argv)
{
    pthread_t thread;
    const char *marker = argc > 1 ? argv[1] : NULL;

    if (pthread_create(&thread, NULL, worker, NULL)) return 10;
    pthread_mutex_lock(&mutex);
    while (!worker_ready) pthread_cond_wait(&cond, &mutex);
    release_worker = 1;
    pthread_cond_signal(&cond);
    pthread_mutex_unlock(&mutex);
    if (pthread_join(thread, NULL)) return 11;
    if (marker) write_marker(marker, "P5_I386_PTHREAD_COND_OK\n");
    puts("P5_I386_PTHREAD_COND_OK");
    return 0;
}
