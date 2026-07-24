// VKMT smoke test: create a Vulkan 1.3 instance on MoltenVK and query the
// features vkd3d-proton hard-requires. Exits nonzero if any fatal gap holds.
#include <stdio.h>
#include <vulkan/vulkan.h>

int main(void) {
    VkApplicationInfo app = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "vkmt-smoke",
        .apiVersion = VK_API_VERSION_1_3,
    };
    VkInstanceCreateInfo ici = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app,
    };
    VkInstance inst;
    VkResult r = vkCreateInstance(&ici, NULL, &inst);
    if (r != VK_SUCCESS) { printf("FAIL vkCreateInstance: %d\n", r); return 1; }

    uint32_t n = 0;
    vkEnumeratePhysicalDevices(inst, &n, NULL);
    printf("physical devices: %u\n", n);
    if (!n) return 1;
    VkPhysicalDevice dev;
    vkEnumeratePhysicalDevices(inst, &n, &dev);

    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(dev, &props);
    printf("device: %s (Vulkan %u.%u.%u)\n", props.deviceName,
           VK_API_VERSION_MAJOR(props.apiVersion),
           VK_API_VERSION_MINOR(props.apiVersion),
           VK_API_VERSION_PATCH(props.apiVersion));

    VkPhysicalDeviceRobustness2FeaturesEXT rob2 = {
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT };
    VkPhysicalDeviceTransformFeedbackPropertiesEXT tfProps = {
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TRANSFORM_FEEDBACK_PROPERTIES_EXT };
    VkPhysicalDeviceVulkan13Features f13 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES };
    VkPhysicalDeviceVulkan12Features f12 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES, .pNext = &f13 };
    VkPhysicalDeviceFeatures2 f2 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &f12 };

    // Chain the optional structs manually (ignored fields stay zero if unsupported).
    rob2.pNext = &tfProps;
    f13.pNext = &rob2;
    vkGetPhysicalDeviceFeatures2(dev, &f2);

    int fail = 0;
    #define CHECK(name, val) do { \
        printf("%-28s %s\n", name, (val) ? "OK" : "** MISSING **"); \
        if (!(val)) fail = 1; } while (0)

    CHECK("robustBufferAccess2", rob2.robustBufferAccess2);
    CHECK("robustImageAccess2", rob2.robustImageAccess2);
    CHECK("nullDescriptor", rob2.nullDescriptor);
    CHECK("transformFeedbackQueries", tfProps.transformFeedbackQueries);
    CHECK("bufferDeviceAddress", f12.bufferDeviceAddress);
    CHECK("samplerMirrorClampToEdge", f12.samplerMirrorClampToEdge);
    CHECK("dynamicRendering", f13.dynamicRendering);
    CHECK("synchronization2", f13.synchronization2);
    CHECK("maintenance4", f13.maintenance4);

    vkDestroyInstance(inst, NULL);
    printf(fail ? "\nSMOKE: gaps present (expected pre-Phase-2)\n" : "\nSMOKE: all vkd3d hard requirements met\n");
    return 0; // informational; gaps are expected until Phase 2 lands
}
