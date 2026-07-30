#include <jni.h>
#include <stdint.h>
#include <windows.h>

static JavaVM *java_vm;
static uintptr_t address_anchor;

struct callback_thread {
    jobject callback;
    jmethodID method;
    jlong result;
    jint status;
};

static DWORD WINAPI callback_thread_main(void *opaque)
{
    struct callback_thread *call = opaque;
    JNIEnv *env = NULL;

    call->status = (*java_vm)->AttachCurrentThread(java_vm,
                                                   (void **)&env, NULL);
    if (call->status != JNI_OK) return 1;

    call->result = (*env)->CallLongMethod(env, call->callback, call->method);
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionClear(env);
        call->status = JNI_ERR;
    }
    if ((*java_vm)->DetachCurrentThread(java_vm) != JNI_OK)
        call->status = JNI_ERR;
    return call->status == JNI_OK ? 0 : 1;
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved)
{
    (void)reserved;
    java_vm = vm;
    return JNI_VERSION_1_6;
}

JNIEXPORT jint JNICALL
Java_VkmtWindowsJavaServiceProbe_nativePointerBits(JNIEnv *env, jclass cls)
{
    (void)env;
    (void)cls;
    return (jint)(sizeof(void *) * 8);
}

JNIEXPORT jlong JNICALL
Java_VkmtWindowsJavaServiceProbe_nativeAddress(JNIEnv *env, jclass cls)
{
    (void)env;
    (void)cls;
    return (jlong)(uintptr_t)&address_anchor;
}

JNIEXPORT jlong JNICALL
Java_VkmtWindowsJavaServiceProbe_nativeRoundTrip(JNIEnv *env, jclass cls,
                                                  jlong value)
{
    (void)env;
    (void)cls;
    return value ^ INT64_C(0x13579bdf2468ace0);
}

JNIEXPORT jlong JNICALL
Java_VkmtWindowsJavaServiceProbe_nativeCallback(JNIEnv *env, jclass cls,
                                                 jobject callback)
{
    jclass callback_class;
    jmethodID method;
    (void)cls;

    callback_class = (*env)->GetObjectClass(env, callback);
    if (!callback_class) return 0;
    method = (*env)->GetMethodID(env, callback_class, "call", "()J");
    if (!method) return 0;
    return (*env)->CallLongMethod(env, callback, method);
}

JNIEXPORT jboolean JNICALL
Java_VkmtWindowsJavaServiceProbe_nativeCallbackException(JNIEnv *env,
                                                          jclass cls,
                                                          jobject callback)
{
    jclass callback_class;
    jmethodID method;
    (void)cls;

    callback_class = (*env)->GetObjectClass(env, callback);
    if (!callback_class) return JNI_FALSE;
    method = (*env)->GetMethodID(env, callback_class, "call", "()J");
    if (!method) return JNI_FALSE;
    (void)(*env)->CallLongMethod(env, callback, method);
    if (!(*env)->ExceptionCheck(env)) return JNI_FALSE;
    (*env)->ExceptionClear(env);
    return JNI_TRUE;
}

JNIEXPORT jlong JNICALL
Java_VkmtWindowsJavaServiceProbe_nativeSecondThread(JNIEnv *env, jclass cls,
                                                     jobject callback)
{
    struct callback_thread call = {0};
    jclass callback_class;
    HANDLE thread;
    DWORD thread_result;
    (void)cls;

    callback_class = (*env)->GetObjectClass(env, callback);
    if (!callback_class) return 0;
    call.method = (*env)->GetMethodID(env, callback_class, "call", "()J");
    if (!call.method) return 0;
    call.callback = (*env)->NewGlobalRef(env, callback);
    if (!call.callback) return 0;

    thread = CreateThread(NULL, 0, callback_thread_main, &call, 0, NULL);
    if (!thread) {
        (*env)->DeleteGlobalRef(env, call.callback);
        return 0;
    }
    if (WaitForSingleObject(thread, 30000) != WAIT_OBJECT_0 ||
        !GetExitCodeThread(thread, &thread_result) ||
        thread_result != 0 || call.status != JNI_OK)
        call.result = 0;
    CloseHandle(thread);
    (*env)->DeleteGlobalRef(env, call.callback);
    return call.result;
}

JNIEXPORT jlong JNICALL
Java_VkmtWindowsJavaServiceProbe_nativeQpcSleepMicros(JNIEnv *env, jclass cls,
                                                       jint milliseconds)
{
    LARGE_INTEGER frequency;
    LARGE_INTEGER before;
    LARGE_INTEGER after;
    (void)env;
    (void)cls;

    if (!QueryPerformanceFrequency(&frequency) ||
        !QueryPerformanceCounter(&before))
        return -1;
    Sleep((DWORD)milliseconds);
    if (!QueryPerformanceCounter(&after)) return -1;
    return (jlong)(((after.QuadPart - before.QuadPart) * INT64_C(1000000)) /
                   frequency.QuadPart);
}
