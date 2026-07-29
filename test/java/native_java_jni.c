#include <stdint.h>

#if defined(__aarch64__)
#define VKMT_JNI_EXPORT __attribute__((visibility("default")))
#else
#error This JNI fixture must be built for native ARM64
#endif

VKMT_JNI_EXPORT int64_t Java_VkmtNativeJavaProbe_nativeToken(void *env, void *class_object)
{
    (void)env;
    (void)class_object;
    return INT64_C(0x564b4d544a4e4901);
}
