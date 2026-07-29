/* A timeline semaphore starts at zero, so waiting for zero must complete
 * immediately. vkd3d-proton relies on this for a D3D12 queue Signal issued
 * before the first command-list submission. */
#include <stdio.h>
#include <vulkan/vulkan.h>

int main(void)
{
    const char *extensions[] = { VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME };
    VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                              .pApplicationName = "vkmt-timeline-zero",
                              .apiVersion = VK_API_VERSION_1_3 };
    VkInstanceCreateInfo instance_info = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                                           .pApplicationInfo = &app,
                                           .enabledExtensionCount = 1,
                                           .ppEnabledExtensionNames = extensions,
                                           .flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR };
    VkPhysicalDeviceVulkan12Features supported = {
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES };
    VkPhysicalDeviceFeatures2 features = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
                                            .pNext = &supported };
    VkDeviceQueueCreateInfo queue_info;
    VkDeviceCreateInfo device_info;
    VkSemaphoreTypeCreateInfo type_info;
    VkSemaphoreCreateInfo semaphore_info;
    VkSemaphoreWaitInfo wait_info;
    VkInstance instance;
    VkPhysicalDevice physical;
    VkDevice device;
    VkSemaphore semaphore;
    uint32_t count = 1, family = 0;
    uint64_t value = 0;
    float priority = 1.0f;
    VkResult result;

    if ((result = vkCreateInstance(&instance_info, NULL, &instance)) != VK_SUCCESS) return 10;
    if ((result = vkEnumeratePhysicalDevices(instance, &count, &physical)) != VK_SUCCESS || !count) return 11;
    vkGetPhysicalDeviceFeatures2(physical, &features);
    if (!supported.timelineSemaphore) return 12;

    queue_info = (VkDeviceQueueCreateInfo){ .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                                             .queueFamilyIndex = family, .queueCount = 1,
                                             .pQueuePriorities = &priority };
    device_info = (VkDeviceCreateInfo){ .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                                        .pNext = &supported, .queueCreateInfoCount = 1,
                                        .pQueueCreateInfos = &queue_info };
    supported.timelineSemaphore = VK_TRUE;
    if ((result = vkCreateDevice(physical, &device_info, NULL, &device)) != VK_SUCCESS) return 13;

    type_info = (VkSemaphoreTypeCreateInfo){ .sType = VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO,
                                              .semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE,
                                              .initialValue = 0 };
    semaphore_info = (VkSemaphoreCreateInfo){ .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
                                               .pNext = &type_info };
    if ((result = vkCreateSemaphore(device, &semaphore_info, NULL, &semaphore)) != VK_SUCCESS) return 14;
    wait_info = (VkSemaphoreWaitInfo){ .sType = VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,
                                       .semaphoreCount = 1, .pSemaphores = &semaphore, .pValues = &value };
    result = vkWaitSemaphores(device, &wait_info, 1000000000ull);
    printf("VKMT_TIMELINE_ZERO_WAIT result=%d\n", result);
    vkDestroySemaphore(device, semaphore, NULL);
    vkDestroyDevice(device, NULL);
    vkDestroyInstance(instance, NULL);
    return result == VK_SUCCESS ? 0 : 15;
}
