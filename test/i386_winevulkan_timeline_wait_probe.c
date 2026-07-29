/* Prove i386 winevulkan timeline waits on both the calling FEX thread and a
 * winpthreads worker. This is the exact shape used by vkd3d's fence worker. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <pthread.h>
#include <stdio.h>
#include <vulkan/vulkan.h>

static PFN_vkWaitSemaphores wait_semaphores;
static VkDevice device;
static VkSemaphore semaphore;
static VkSemaphoreWaitInfo wait_info;
static VkResult worker_result = VK_ERROR_UNKNOWN;

static void *worker(void *arg)
{
    (void)arg;
    worker_result = wait_semaphores(device, &wait_info, 1000000000ull);
    return NULL;
}

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

int main(int argc, char **argv)
{
    char failure[64];
    HMODULE module = LoadLibraryA("winevulkan.dll");
    PFN_vkGetInstanceProcAddr get_instance_proc;
    PFN_vkGetDeviceProcAddr get_device_proc;
    PFN_vkCreateInstance create_instance;
    PFN_vkDestroyInstance destroy_instance;
    PFN_vkEnumeratePhysicalDevices enumerate_devices;
    PFN_vkGetPhysicalDeviceFeatures2 get_features;
    PFN_vkGetPhysicalDeviceQueueFamilyProperties get_queue_families;
    PFN_vkCreateDevice create_device;
    PFN_vkDestroyDevice destroy_device;
    PFN_vkCreateSemaphore create_semaphore;
    PFN_vkDestroySemaphore destroy_semaphore;
    VkInstance instance;
    VkPhysicalDevice physical;
    VkApplicationInfo app = { VK_STRUCTURE_TYPE_APPLICATION_INFO };
    VkInstanceCreateInfo instance_info = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
    VkPhysicalDeviceTimelineSemaphoreFeatures timeline = {
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES };
    VkPhysicalDeviceFeatures2 features = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2 };
    VkDeviceQueueCreateInfo queue_info = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
    VkDeviceCreateInfo device_info = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
    VkSemaphoreTypeCreateInfo type_info = { VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO };
    VkSemaphoreCreateInfo semaphore_info = { VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    uint32_t count = 1, family_count = 0, family = 0;
    VkQueueFamilyProperties families[16];
    uint64_t value = 0;
    float priority = 1.0f;
    pthread_t thread;
    VkResult result;

#define FAIL(step) do { if (argc > 1) { snprintf(failure, sizeof(failure), "P5_I386_WINEVULKAN_TIMELINE_STEP_%d\\n", step); write_marker(argv[1], failure); } return step; } while (0)
    if (!module) FAIL(10);
    get_instance_proc = (void *)GetProcAddress(module, "vkGetInstanceProcAddr");
    if (!get_instance_proc) FAIL(11);
    create_instance = (void *)get_instance_proc(NULL, "vkCreateInstance");
    if (!create_instance) FAIL(12);
    app.pApplicationName = "i386-winevulkan-timeline";
    app.apiVersion = VK_API_VERSION_1_3;
    instance_info.pApplicationInfo = &app;
    instance_info.flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    {
        static const char *ext = VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME;
        instance_info.enabledExtensionCount = 1;
        instance_info.ppEnabledExtensionNames = &ext;
    }
    if ((result = create_instance(&instance_info, NULL, &instance)) != VK_SUCCESS) FAIL(13);
    enumerate_devices = (void *)get_instance_proc(instance, "vkEnumeratePhysicalDevices");
    get_features = (void *)get_instance_proc(instance, "vkGetPhysicalDeviceFeatures2");
    get_queue_families = (void *)get_instance_proc(instance, "vkGetPhysicalDeviceQueueFamilyProperties");
    create_device = (void *)get_instance_proc(instance, "vkCreateDevice");
    destroy_instance = (void *)get_instance_proc(instance, "vkDestroyInstance");
    if (!enumerate_devices || !get_features || !get_queue_families || !create_device || !destroy_instance) FAIL(14);
    if ((result = enumerate_devices(instance, &count, &physical)) != VK_SUCCESS || !count) FAIL(15);
    features.pNext = &timeline;
    get_features(physical, &features);
    if (!timeline.timelineSemaphore) FAIL(16);
    get_queue_families(physical, &family_count, NULL);
    if (!family_count || family_count > sizeof(families) / sizeof(families[0])) FAIL(17);
    get_queue_families(physical, &family_count, families);
    while (family < family_count && !(families[family].queueFlags & VK_QUEUE_GRAPHICS_BIT)) ++family;
    if (family == family_count) FAIL(18);
    queue_info.queueFamilyIndex = family;
    queue_info.queueCount = 1;
    queue_info.pQueuePriorities = &priority;
    device_info.pNext = &timeline;
    device_info.queueCreateInfoCount = 1;
    device_info.pQueueCreateInfos = &queue_info;
    timeline.timelineSemaphore = VK_TRUE;
    if ((result = create_device(physical, &device_info, NULL, &device)) != VK_SUCCESS) FAIL(19);
    get_device_proc = (void *)get_instance_proc(instance, "vkGetDeviceProcAddr");
    create_semaphore = (void *)get_device_proc(device, "vkCreateSemaphore");
    destroy_semaphore = (void *)get_device_proc(device, "vkDestroySemaphore");
    wait_semaphores = (void *)get_device_proc(device, "vkWaitSemaphores");
    destroy_device = (void *)get_device_proc(device, "vkDestroyDevice");
    if (!create_semaphore || !destroy_semaphore || !wait_semaphores || !destroy_device) FAIL(20);
    type_info.semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE;
    semaphore_info.pNext = &type_info;
    if ((result = create_semaphore(device, &semaphore_info, NULL, &semaphore)) != VK_SUCCESS) FAIL(21);
    wait_info.sType = VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO;
    wait_info.semaphoreCount = 1;
    wait_info.pSemaphores = &semaphore;
    wait_info.pValues = &value;
    result = wait_semaphores(device, &wait_info, 1000000000ull);
    fprintf(stderr, "P5 main timeline wait=%d\n", result);
    if (result == VK_SUCCESS && !pthread_create(&thread, NULL, worker, NULL)) pthread_join(thread, NULL);
    fprintf(stderr, "P5 worker timeline wait=%d\n", worker_result);
    destroy_semaphore(device, semaphore, NULL);
    destroy_device(device, NULL);
    destroy_instance(instance, NULL);
    if (result != VK_SUCCESS || worker_result != VK_SUCCESS) FAIL(22);
    if (argc > 1) write_marker(argv[1], "P5_I386_WINEVULKAN_TIMELINE_WAIT_OK\n");
#undef FAIL
    return 0;
}
