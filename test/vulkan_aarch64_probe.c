/* Native AArch64 Wine Vulkan dispatch boundary probe. */
#include <windows.h>
#include <vulkan/vulkan.h>
#include <stdio.h>

int main(void)
{
    HMODULE module = LoadLibraryA("winevulkan.dll");
    PFN_vkGetInstanceProcAddr get_instance_proc;
    PFN_vkCreateInstance create_instance;
    PFN_vkEnumeratePhysicalDevices enumerate_devices;
    PFN_vkDestroyInstance destroy_instance;
    VkInstance instance;
    VkInstanceCreateInfo info = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
    uint32_t count = 0;
    VkResult result;

    if (!module) return 10;
    get_instance_proc = (void *)GetProcAddress(module, "vkGetInstanceProcAddr");
    if (!get_instance_proc) return 11;
    create_instance = (void *)get_instance_proc(NULL, "vkCreateInstance");
    if (!create_instance) return 12;
    result = create_instance(&info, NULL, &instance);
    fprintf(stderr, "vkCreateInstance=%d\\n", result);
    if (result != VK_SUCCESS) return 13;
    enumerate_devices = (void *)get_instance_proc(instance, "vkEnumeratePhysicalDevices");
    destroy_instance = (void *)get_instance_proc(instance, "vkDestroyInstance");
    if (!enumerate_devices || !destroy_instance) return 14;
    result = enumerate_devices(instance, &count, NULL);
    fprintf(stderr, "vkEnumeratePhysicalDevices=%d count=%u\\n", result, count);
    destroy_instance(instance, NULL);
    return result == VK_SUCCESS && count ? 0 : 15;
}
