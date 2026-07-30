#include <jni.h>
#include <stdint.h>
#include <stdio.h>
#include <windows.h>

#define WORKER_COUNT 4

static JavaVM *java_vm;
static jclass probe_class;
static jmethodID callback_method;
static volatile LONG worker_ids[WORKER_COUNT];
static __thread LONG attached_tls;

struct attach_state {
    jint iteration;
    volatile LONG success;
};

struct apc_state {
    HANDLE ready;
    volatile LONG delivered;
};

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved)
{
    (void)reserved;
    java_vm = vm;
    return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL
Java_VkmtWindowsJavaLifecycleProbe_nativeRegisterWorker(
    JNIEnv *environment, jclass type, jint slot)
{
    (void)environment;
    (void)type;
    if (slot >= 0 && slot < WORKER_COUNT)
        InterlockedExchange(&worker_ids[slot], (LONG)GetCurrentThreadId());
}

JNIEXPORT jlong JNICALL
Java_VkmtWindowsJavaLifecycleProbe_nativeSuspendContextResume(
    JNIEnv *environment, jclass type, jint slot)
{
    HANDLE thread;
    CONTEXT context;
    DWORD previous, resumed;
    LONG thread_id;

    (void)environment;
    (void)type;
    if (slot < 0 || slot >= WORKER_COUNT) return 0;
    fprintf(stderr, "VKMT_J5_CONTEXT slot=%d phase=open\n", (int)slot);
    fflush(stderr);
    thread_id = InterlockedCompareExchange(&worker_ids[slot], 0, 0);
    if (!thread_id) return 0;
    thread = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT |
                        THREAD_SET_CONTEXT | THREAD_QUERY_INFORMATION,
                        FALSE, (DWORD)thread_id);
    if (!thread) return 0;
    previous = SuspendThread(thread);
    fprintf(stderr, "VKMT_J5_CONTEXT slot=%d phase=suspended result=%lu\n",
            (int)slot, (unsigned long)previous);
    fflush(stderr);
    if (previous == (DWORD)-1) {
        CloseHandle(thread);
        return 0;
    }
    ZeroMemory(&context, sizeof(context));
    context.ContextFlags = CONTEXT_FULL | CONTEXT_FLOATING_POINT |
                           CONTEXT_EXTENDED_REGISTERS;
    if (!GetThreadContext(thread, &context) || !context.Eip || !context.Esp ||
        !SetThreadContext(thread, &context)) {
        ResumeThread(thread);
        CloseHandle(thread);
        return 0;
    }
    fprintf(stderr, "VKMT_J5_CONTEXT slot=%d phase=context eip=%08lx\n",
            (int)slot, (unsigned long)context.Eip);
    fflush(stderr);
    resumed = ResumeThread(thread);
    fprintf(stderr, "VKMT_J5_CONTEXT slot=%d phase=resumed result=%lu\n",
            (int)slot, (unsigned long)resumed);
    fflush(stderr);
    CloseHandle(thread);
    if (resumed == (DWORD)-1) return 0;
    return ((jlong)(uint32_t)context.Eip << 32) | (uint32_t)context.Esp;
}

static DWORD WINAPI attach_thread(void *opaque)
{
    struct attach_state *state = opaque;
    JNIEnv *environment = NULL;

    attached_tls = (LONG)(0x4a350000U | (GetCurrentThreadId() & 0xffff));
    if ((*java_vm)->AttachCurrentThread(java_vm, (void **)&environment, NULL))
        return 1;
    (*environment)->CallStaticVoidMethod(environment, probe_class,
                                         callback_method, state->iteration,
                                         attached_tls);
    if (!(*environment)->ExceptionCheck(environment))
        InterlockedExchange(&state->success, 1);
    (*java_vm)->DetachCurrentThread(java_vm);
    return 0;
}

JNIEXPORT jint JNICALL
Java_VkmtWindowsJavaLifecycleProbe_nativeAttachCallback(
    JNIEnv *environment, jclass type, jint iteration)
{
    struct attach_state state = {iteration, 0};
    HANDLE thread;
    DWORD wait;

    if (!probe_class) {
        probe_class = (*environment)->NewGlobalRef(environment, type);
        if (!probe_class) return 0;
        callback_method = (*environment)->GetStaticMethodID(
            environment, probe_class, "nativeCallback", "(II)V");
        if (!callback_method) return 0;
    }
    thread = CreateThread(NULL, 0, attach_thread, &state, 0, NULL);
    if (!thread) return 0;
    wait = WaitForSingleObject(thread, 120000);
    CloseHandle(thread);
    return wait == WAIT_OBJECT_0 && state.success == 1;
}

static VOID CALLBACK apc_callback(ULONG_PTR opaque)
{
    struct apc_state *state = (struct apc_state *)opaque;
    InterlockedIncrement(&state->delivered);
}

static DWORD WINAPI apc_thread(void *opaque)
{
    struct apc_state *state = opaque;
    SetEvent(state->ready);
    SleepEx(120000, TRUE);
    return state->delivered == 1 ? 0 : 1;
}

JNIEXPORT jint JNICALL
Java_VkmtWindowsJavaLifecycleProbe_nativeApcRoundtrip(
    JNIEnv *environment, jclass type)
{
    struct apc_state state;
    HANDLE thread;
    DWORD wait;

    (void)environment;
    (void)type;
    state.ready = CreateEventW(NULL, TRUE, FALSE, NULL);
    state.delivered = 0;
    if (!state.ready) return 0;
    thread = CreateThread(NULL, 0, apc_thread, &state, 0, NULL);
    if (!thread) {
        CloseHandle(state.ready);
        return 0;
    }
    if (WaitForSingleObject(state.ready, 120000) != WAIT_OBJECT_0 ||
        !QueueUserAPC(apc_callback, thread, (ULONG_PTR)&state)) {
        CloseHandle(thread);
        CloseHandle(state.ready);
        return 0;
    }
    wait = WaitForSingleObject(thread, 120000);
    CloseHandle(thread);
    CloseHandle(state.ready);
    return wait == WAIT_OBJECT_0 && state.delivered == 1;
}

JNIEXPORT void JNICALL
Java_VkmtWindowsJavaLifecycleProbe_nativeClose(
    JNIEnv *environment, jclass type)
{
    (void)type;
    if (probe_class) {
        (*environment)->DeleteGlobalRef(environment, probe_class);
        probe_class = NULL;
        callback_method = NULL;
    }
}
