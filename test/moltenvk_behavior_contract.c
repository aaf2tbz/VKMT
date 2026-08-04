/*
 * Direct native MoltenVK behavior contract.
 *
 * Feature queries are recorded separately from behavior.  A feature bit is
 * never accepted as proof by this fixture.  The transform-feedback and
 * indirect-count lanes deliberately fail if the implementation advertises a
 * path that this contract cannot observe as correct; that makes the policy
 * decision (implement it or stop advertising it) explicit.
 */

#include <vulkan/vulkan.h>

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int has_device_extension(VkPhysicalDevice device, const char *name)
{
    uint32_t count = 0, i;
    VkExtensionProperties *props;

    if (vkEnumerateDeviceExtensionProperties(device, NULL, &count, NULL) != VK_SUCCESS)
        return 0;
    props = calloc(count ? count : 1, sizeof(*props));
    if (!props) return 0;
    if (vkEnumerateDeviceExtensionProperties(device, NULL, &count, props) != VK_SUCCESS)
    {
        free(props);
        return 0;
    }
    for (i = 0; i < count; ++i)
        if (!strcmp(props[i].extensionName, name))
        {
            free(props);
            return 1;
        }
    free(props);
    return 0;
}

static uint32_t find_memory_type(VkPhysicalDevice device, uint32_t bits, VkMemoryPropertyFlags wanted)
{
    VkPhysicalDeviceMemoryProperties props;
    uint32_t i;

    vkGetPhysicalDeviceMemoryProperties(device, &props);
    for (i = 0; i < props.memoryTypeCount; ++i)
        if ((bits & (1u << i)) &&
            (props.memoryTypes[i].propertyFlags & wanted) == wanted)
            return i;
    return UINT32_MAX;
}

static VkResult create_host_buffer(VkPhysicalDevice device, VkDevice vk_device,
                                   VkDeviceSize size, VkBufferUsageFlags usage,
                                   VkBuffer *buffer, VkDeviceMemory *memory)
{
    VkBufferCreateInfo buffer_info = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO };
    VkMemoryRequirements requirements;
    VkMemoryAllocateInfo allocate_info = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    uint32_t type;
    VkResult result;

    buffer_info.size = size;
    buffer_info.usage = usage;
    buffer_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    if ((result = vkCreateBuffer(vk_device, &buffer_info, NULL, buffer)) != VK_SUCCESS)
        return result;
    vkGetBufferMemoryRequirements(vk_device, *buffer, &requirements);
    type = find_memory_type(device, requirements.memoryTypeBits,
                            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                            VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (type == UINT32_MAX)
    {
        vkDestroyBuffer(vk_device, *buffer, NULL);
        *buffer = VK_NULL_HANDLE;
        return VK_ERROR_MEMORY_MAP_FAILED;
    }
    allocate_info.allocationSize = requirements.size;
    allocate_info.memoryTypeIndex = type;
    if ((result = vkAllocateMemory(vk_device, &allocate_info, NULL, memory)) != VK_SUCCESS)
    {
        vkDestroyBuffer(vk_device, *buffer, NULL);
        *buffer = VK_NULL_HANDLE;
        return result;
    }
    if ((result = vkBindBufferMemory(vk_device, *buffer, *memory, 0)) != VK_SUCCESS)
    {
        vkFreeMemory(vk_device, *memory, NULL);
        vkDestroyBuffer(vk_device, *buffer, NULL);
        *memory = VK_NULL_HANDLE;
        *buffer = VK_NULL_HANDLE;
    }
    return result;
}

static int load_spirv(const char *path, uint32_t **words, size_t *word_count)
{
    FILE *file;
    long size;
    size_t read_size;

    file = fopen(path, "rb");
    if (!file) return -1;
    if (fseek(file, 0, SEEK_END) || (size = ftell(file)) <= 0 ||
        (size % (long)sizeof(uint32_t)) || fseek(file, 0, SEEK_SET))
    {
        fclose(file);
        return -1;
    }
    *words = malloc((size_t)size);
    if (!*words)
    {
        fclose(file);
        return -1;
    }
    read_size = fread(*words, 1, (size_t)size, file);
    fclose(file);
    if (read_size != (size_t)size)
    {
        free(*words);
        *words = NULL;
        return -1;
    }
    *word_count = (size_t)size / sizeof(uint32_t);
    return 0;
}

static int run_storage_read(VkPhysicalDevice physical, VkDevice device, VkQueue queue,
                            uint32_t queue_family, const uint32_t *shader_words,
                            size_t shader_word_count, int null_descriptor, uint32_t index)
{
    VkResult result;
    VkBuffer input = VK_NULL_HANDLE, output = VK_NULL_HANDLE;
    VkDeviceMemory input_memory = VK_NULL_HANDLE, output_memory = VK_NULL_HANDLE;
    VkDescriptorSetLayout layout = VK_NULL_HANDLE;
    VkDescriptorPool pool = VK_NULL_HANDLE;
    VkDescriptorSet set = VK_NULL_HANDLE;
    VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
    VkShaderModule shader = VK_NULL_HANDLE;
    VkPipeline pipeline = VK_NULL_HANDLE;
    VkCommandPool command_pool = VK_NULL_HANDLE;
    VkCommandBuffer command = VK_NULL_HANDLE;
    uint32_t *mapped = NULL;
    VkDescriptorSetLayoutBinding bindings[2] = {
        { 0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, NULL },
        { 1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, NULL },
    };
    VkDescriptorSetLayoutCreateInfo layout_info = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO };
    VkDescriptorPoolSize pool_size = { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 2 };
    VkDescriptorPoolCreateInfo pool_info = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO };
    VkDescriptorSetAllocateInfo set_info = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO };
    VkDescriptorBufferInfo input_info = { null_descriptor ? VK_NULL_HANDLE : input, 0, 4 };
    VkDescriptorBufferInfo output_info;
    VkWriteDescriptorSet writes[2] = {
        { VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, NULL, VK_NULL_HANDLE, 0, 0,
          1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, NULL, &input_info, NULL },
        { VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, NULL, VK_NULL_HANDLE, 1, 0,
          1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, NULL, NULL, NULL },
    };
    VkPushConstantRange push_range = { VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(uint32_t) };
    VkPipelineLayoutCreateInfo pipeline_layout_info = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO };
    VkShaderModuleCreateInfo shader_info = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO };
    VkComputePipelineCreateInfo pipeline_info = { .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO };
    VkCommandPoolCreateInfo command_pool_info = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO };
    VkCommandBufferAllocateInfo command_info = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO };
    VkCommandBufferBeginInfo begin_info = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
    VkSubmitInfo submit_info = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO };
    VkBufferMemoryBarrier barrier = { .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER };
    uint32_t expected = 0;
    int ret = -1;

    result = create_host_buffer(physical, device, 4, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                                &input, &input_memory);
    if (result != VK_SUCCESS) goto done;
    if (!null_descriptor) input_info.buffer = input;
    result = create_host_buffer(physical, device, 4, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                                &output, &output_memory);
    if (result != VK_SUCCESS) goto done;
    if (vkMapMemory(device, input_memory, 0, 4, 0, (void **)&mapped) != VK_SUCCESS) goto done;
    *mapped = 0x12345678u;
    vkUnmapMemory(device, input_memory);
    if (vkMapMemory(device, output_memory, 0, 4, 0, (void **)&mapped) != VK_SUCCESS) goto done;
    *mapped = 0xffffffffu;
    vkUnmapMemory(device, output_memory);

    layout_info.bindingCount = 2;
    layout_info.pBindings = bindings;
    if ((result = vkCreateDescriptorSetLayout(device, &layout_info, NULL, &layout)) != VK_SUCCESS) goto done;
    pool_info.maxSets = 1;
    pool_info.poolSizeCount = 1;
    pool_info.pPoolSizes = &pool_size;
    if ((result = vkCreateDescriptorPool(device, &pool_info, NULL, &pool)) != VK_SUCCESS) goto done;
    set_info.descriptorPool = pool;
    set_info.descriptorSetCount = 1;
    set_info.pSetLayouts = &layout;
    if ((result = vkAllocateDescriptorSets(device, &set_info, &set)) != VK_SUCCESS) goto done;
    output_info.buffer = output;
    output_info.offset = 0;
    output_info.range = 4;
    writes[0].dstSet = set;
    writes[1].dstSet = set;
    writes[1].pBufferInfo = &output_info;
    vkUpdateDescriptorSets(device, 2, writes, 0, NULL);

    pipeline_layout_info.setLayoutCount = 1;
    pipeline_layout_info.pSetLayouts = &layout;
    pipeline_layout_info.pushConstantRangeCount = 1;
    pipeline_layout_info.pPushConstantRanges = &push_range;
    if ((result = vkCreatePipelineLayout(device, &pipeline_layout_info, NULL, &pipeline_layout)) != VK_SUCCESS) goto done;
    shader_info.codeSize = shader_word_count * sizeof(uint32_t);
    shader_info.pCode = shader_words;
    if ((result = vkCreateShaderModule(device, &shader_info, NULL, &shader)) != VK_SUCCESS) goto done;
    pipeline_info.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pipeline_info.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pipeline_info.stage.module = shader;
    pipeline_info.stage.pName = "main";
    pipeline_info.layout = pipeline_layout;
    if ((result = vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &pipeline_info,
                                           NULL, &pipeline)) != VK_SUCCESS) goto done;

    command_pool_info.queueFamilyIndex = queue_family;
    if ((result = vkCreateCommandPool(device, &command_pool_info, NULL, &command_pool)) != VK_SUCCESS) goto done;
    command_info.commandPool = command_pool;
    command_info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    command_info.commandBufferCount = 1;
    if ((result = vkAllocateCommandBuffers(device, &command_info, &command)) != VK_SUCCESS) goto done;
    if ((result = vkBeginCommandBuffer(command, &begin_info)) != VK_SUCCESS) goto done;
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_layout, 0, 1, &set, 0, NULL);
    vkCmdPushConstants(command, pipeline_layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(index), &index);
    vkCmdDispatch(command, 1, 1, 1);
    barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.buffer = output;
    barrier.offset = 0;
    barrier.size = 4;
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT,
                         0, 0, NULL, 1, &barrier, 0, NULL);
    if ((result = vkEndCommandBuffer(command)) != VK_SUCCESS) goto done;
    submit_info.commandBufferCount = 1;
    submit_info.pCommandBuffers = &command;
    if ((result = vkQueueSubmit(queue, 1, &submit_info, VK_NULL_HANDLE)) != VK_SUCCESS) goto done;
    if ((result = vkQueueWaitIdle(queue)) != VK_SUCCESS) goto done;
    if (vkMapMemory(device, output_memory, 0, 4, 0, (void **)&mapped) != VK_SUCCESS) goto done;
    expected = *mapped;
    vkUnmapMemory(device, output_memory);
    ret = expected == 0 ? 0 : 1;

done:
    if (result != VK_SUCCESS)
        fprintf(stderr, "compute behavior operation failed: VkResult=%d\n", result);
    if (command_pool) vkDestroyCommandPool(device, command_pool, NULL);
    if (pipeline) vkDestroyPipeline(device, pipeline, NULL);
    if (shader) vkDestroyShaderModule(device, shader, NULL);
    if (pipeline_layout) vkDestroyPipelineLayout(device, pipeline_layout, NULL);
    if (pool) vkDestroyDescriptorPool(device, pool, NULL);
    if (layout) vkDestroyDescriptorSetLayout(device, layout, NULL);
    if (output_memory) vkFreeMemory(device, output_memory, NULL);
    if (output) vkDestroyBuffer(device, output, NULL);
    if (input_memory) vkFreeMemory(device, input_memory, NULL);
    if (input) vkDestroyBuffer(device, input, NULL);
    return ret;
}

static VkResult create_image(VkPhysicalDevice physical, VkDevice device,
                             VkImage *image, VkDeviceMemory *memory)
{
    VkImageCreateInfo image_info = { .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO };
    VkMemoryRequirements requirements;
    VkMemoryAllocateInfo allocate_info = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    uint32_t type;
    VkResult result;

    image_info.imageType = VK_IMAGE_TYPE_2D;
    image_info.format = VK_FORMAT_R8G8B8A8_UNORM;
    image_info.extent.width = 1;
    image_info.extent.height = 1;
    image_info.extent.depth = 1;
    image_info.mipLevels = 1;
    image_info.arrayLayers = 1;
    image_info.samples = VK_SAMPLE_COUNT_1_BIT;
    image_info.tiling = VK_IMAGE_TILING_OPTIMAL;
    image_info.usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    image_info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    if ((result = vkCreateImage(device, &image_info, NULL, image)) != VK_SUCCESS)
        return result;
    vkGetImageMemoryRequirements(device, *image, &requirements);
    type = find_memory_type(physical, requirements.memoryTypeBits,
                            VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (type == UINT32_MAX)
        type = find_memory_type(physical, requirements.memoryTypeBits, 0);
    if (type == UINT32_MAX)
    {
        vkDestroyImage(device, *image, NULL);
        *image = VK_NULL_HANDLE;
        return VK_ERROR_MEMORY_MAP_FAILED;
    }
    allocate_info.allocationSize = requirements.size;
    allocate_info.memoryTypeIndex = type;
    if ((result = vkAllocateMemory(device, &allocate_info, NULL, memory)) != VK_SUCCESS)
    {
        vkDestroyImage(device, *image, NULL);
        *image = VK_NULL_HANDLE;
        return result;
    }
    if ((result = vkBindImageMemory(device, *image, *memory, 0)) != VK_SUCCESS)
    {
        vkFreeMemory(device, *memory, NULL);
        vkDestroyImage(device, *image, NULL);
        *memory = VK_NULL_HANDLE;
        *image = VK_NULL_HANDLE;
    }
    return result;
}

static int run_image_read(VkPhysicalDevice physical, VkDevice device, VkQueue queue,
                          uint32_t queue_family, const uint32_t *shader_words,
                          size_t shader_word_count)
{
    VkResult result;
    VkImage image = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
    VkDeviceMemory image_memory = VK_NULL_HANDLE;
    VkBuffer output = VK_NULL_HANDLE;
    VkDeviceMemory output_memory = VK_NULL_HANDLE;
    VkDescriptorSetLayout layout = VK_NULL_HANDLE;
    VkDescriptorPool pool = VK_NULL_HANDLE;
    VkDescriptorSet set = VK_NULL_HANDLE;
    VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
    VkShaderModule shader = VK_NULL_HANDLE;
    VkPipeline pipeline = VK_NULL_HANDLE;
    VkCommandPool command_pool = VK_NULL_HANDLE;
    VkCommandBuffer command = VK_NULL_HANDLE;
    uint32_t *mapped = NULL;
    VkDescriptorSetLayoutBinding bindings[2] = {
        { 0, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, VK_SHADER_STAGE_COMPUTE_BIT, NULL },
        { 1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, NULL },
    };
    VkDescriptorSetLayoutCreateInfo layout_info = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO };
    VkDescriptorPoolSize pool_sizes[2] = {
        { VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1 },
        { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1 },
    };
    VkDescriptorPoolCreateInfo pool_info = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO };
    VkDescriptorSetAllocateInfo set_info = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO };
    VkDescriptorImageInfo image_info = { VK_NULL_HANDLE, VK_NULL_HANDLE, VK_IMAGE_LAYOUT_GENERAL };
    VkDescriptorBufferInfo output_info;
    VkWriteDescriptorSet writes[2] = {
        { .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstBinding = 0,
          .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
          .pImageInfo = &image_info },
        { .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstBinding = 1,
          .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER },
    };
    VkPipelineLayoutCreateInfo pipeline_layout_info = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO };
    VkShaderModuleCreateInfo shader_info = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO };
    VkComputePipelineCreateInfo pipeline_info = { .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO };
    VkCommandPoolCreateInfo command_pool_info = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO };
    VkCommandBufferAllocateInfo command_info = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO };
    VkCommandBufferBeginInfo begin_info = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
    VkSubmitInfo submit_info = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO };
    VkImageMemoryBarrier image_barrier = { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER };
    VkBufferMemoryBarrier buffer_barrier = { .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER };
    int ret = -1;

    result = create_image(physical, device, &image, &image_memory);
    if (result != VK_SUCCESS) goto done;
    result = create_host_buffer(physical, device, 4, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                                &output, &output_memory);
    if (result != VK_SUCCESS) goto done;
    if (vkMapMemory(device, output_memory, 0, 4, 0, (void **)&mapped) != VK_SUCCESS) goto done;
    *mapped = 0xffffffffu;
    vkUnmapMemory(device, output_memory);

    {
        VkImageViewCreateInfo view_info = { .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO };
        view_info.image = image;
        view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
        view_info.format = VK_FORMAT_R8G8B8A8_UNORM;
        view_info.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        view_info.subresourceRange.levelCount = 1;
        view_info.subresourceRange.layerCount = 1;
        if ((result = vkCreateImageView(device, &view_info, NULL, &view)) != VK_SUCCESS) goto done;
    }
    layout_info.bindingCount = 2;
    layout_info.pBindings = bindings;
    if ((result = vkCreateDescriptorSetLayout(device, &layout_info, NULL, &layout)) != VK_SUCCESS) goto done;
    pool_info.maxSets = 1;
    pool_info.poolSizeCount = 2;
    pool_info.pPoolSizes = pool_sizes;
    if ((result = vkCreateDescriptorPool(device, &pool_info, NULL, &pool)) != VK_SUCCESS) goto done;
    set_info.descriptorPool = pool;
    set_info.descriptorSetCount = 1;
    set_info.pSetLayouts = &layout;
    if ((result = vkAllocateDescriptorSets(device, &set_info, &set)) != VK_SUCCESS) goto done;
    output_info.buffer = output;
    output_info.offset = 0;
    output_info.range = 4;
    image_info.imageView = view;
    writes[0].dstSet = set;
    writes[1].dstSet = set;
    writes[1].pBufferInfo = &output_info;
    vkUpdateDescriptorSets(device, 2, writes, 0, NULL);
    pipeline_layout_info.setLayoutCount = 1;
    pipeline_layout_info.pSetLayouts = &layout;
    if ((result = vkCreatePipelineLayout(device, &pipeline_layout_info, NULL, &pipeline_layout)) != VK_SUCCESS) goto done;
    shader_info.codeSize = shader_word_count * sizeof(uint32_t);
    shader_info.pCode = shader_words;
    if ((result = vkCreateShaderModule(device, &shader_info, NULL, &shader)) != VK_SUCCESS) goto done;
    pipeline_info.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pipeline_info.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pipeline_info.stage.module = shader;
    pipeline_info.stage.pName = "main";
    pipeline_info.layout = pipeline_layout;
    if ((result = vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &pipeline_info,
                                           NULL, &pipeline)) != VK_SUCCESS) goto done;
    command_pool_info.queueFamilyIndex = queue_family;
    if ((result = vkCreateCommandPool(device, &command_pool_info, NULL, &command_pool)) != VK_SUCCESS) goto done;
    command_info.commandPool = command_pool;
    command_info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    command_info.commandBufferCount = 1;
    if ((result = vkAllocateCommandBuffers(device, &command_info, &command)) != VK_SUCCESS) goto done;
    if ((result = vkBeginCommandBuffer(command, &begin_info)) != VK_SUCCESS) goto done;
    image_barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    image_barrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
    image_barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    image_barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    image_barrier.image = image;
    image_barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    image_barrier.subresourceRange.levelCount = 1;
    image_barrier.subresourceRange.layerCount = 1;
    image_barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                         VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, NULL, 0, NULL,
                         1, &image_barrier);
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_layout,
                            0, 1, &set, 0, NULL);
    vkCmdDispatch(command, 1, 1, 1);
    buffer_barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    buffer_barrier.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
    buffer_barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    buffer_barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    buffer_barrier.buffer = output;
    buffer_barrier.size = 4;
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT,
                         0, 0, NULL, 1, &buffer_barrier, 0, NULL);
    if ((result = vkEndCommandBuffer(command)) != VK_SUCCESS) goto done;
    submit_info.commandBufferCount = 1;
    submit_info.pCommandBuffers = &command;
    if ((result = vkQueueSubmit(queue, 1, &submit_info, VK_NULL_HANDLE)) != VK_SUCCESS) goto done;
    if ((result = vkQueueWaitIdle(queue)) != VK_SUCCESS) goto done;
    if (vkMapMemory(device, output_memory, 0, 4, 0, (void **)&mapped) != VK_SUCCESS) goto done;
    ret = *mapped == 0 ? 0 : 1;
    vkUnmapMemory(device, output_memory);

done:
    if (result != VK_SUCCESS)
        fprintf(stderr, "image behavior operation failed: VkResult=%d\n", result);
    if (command_pool) vkDestroyCommandPool(device, command_pool, NULL);
    if (pipeline) vkDestroyPipeline(device, pipeline, NULL);
    if (shader) vkDestroyShaderModule(device, shader, NULL);
    if (pipeline_layout) vkDestroyPipelineLayout(device, pipeline_layout, NULL);
    if (pool) vkDestroyDescriptorPool(device, pool, NULL);
    if (layout) vkDestroyDescriptorSetLayout(device, layout, NULL);
    if (view) vkDestroyImageView(device, view, NULL);
    if (image_memory) vkFreeMemory(device, image_memory, NULL);
    if (image) vkDestroyImage(device, image, NULL);
    if (output_memory) vkFreeMemory(device, output_memory, NULL);
    if (output) vkDestroyBuffer(device, output, NULL);
    return ret;
}

int main(int argc, char **argv)
{
    const char *shader_path, *image_shader_path;
    const char *instance_extensions[] = { VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME };
    VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO };
    VkInstanceCreateInfo instance_info = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkPhysicalDeviceProperties properties;
    VkPhysicalDeviceFeatures2 features = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2 };
    VkPhysicalDeviceVulkan12Features vulkan12 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES };
    VkPhysicalDeviceVulkan13Features vulkan13 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES };
    VkPhysicalDeviceRobustness2FeaturesEXT robustness = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT };
    VkPhysicalDeviceTransformFeedbackFeaturesEXT transform_feedback = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TRANSFORM_FEEDBACK_FEATURES_EXT };
    VkPhysicalDeviceTexelBufferAlignmentFeaturesEXT texel = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TEXEL_BUFFER_ALIGNMENT_FEATURES_EXT };
    VkPhysicalDeviceProperties2 properties2 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2 };
    VkPhysicalDeviceRobustness2PropertiesEXT robustness_properties = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_PROPERTIES_EXT };
    VkPhysicalDeviceTransformFeedbackPropertiesEXT transform_feedback_properties = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TRANSFORM_FEEDBACK_PROPERTIES_EXT };
    VkPhysicalDeviceTexelBufferAlignmentPropertiesEXT texel_properties = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TEXEL_BUFFER_ALIGNMENT_PROPERTIES_EXT };
    VkQueueFamilyProperties *queues = NULL;
    uint32_t queue_count = 0, device_count = 0, queue_family = UINT32_MAX;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue queue = VK_NULL_HANDLE;
    VkDeviceQueueCreateInfo queue_info = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
    VkDeviceCreateInfo device_info = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
    float priority = 1.0f;
    const char *device_extensions[2];
    uint32_t device_extension_count = 0;
    uint32_t *shader_words = NULL;
    size_t shader_word_count = 0;
    int fail = 0;
    int has_robustness, has_xfb, has_texel_alignment, has_draw_indirect_count;

    if (argc != 3)
    {
        fprintf(stderr, "usage: %s STORAGE_SHADER.spv IMAGE_SHADER.spv\n", argv[0]);
        return 2;
    }
    shader_path = argv[1];
    image_shader_path = argv[2];
    if (load_spirv(shader_path, &shader_words, &shader_word_count)) return 2;

    app.pApplicationName = "VKMT MoltenVK behavior contract";
    app.applicationVersion = 1;
    app.pEngineName = "VKMT";
    app.engineVersion = 1;
    app.apiVersion = VK_API_VERSION_1_3;
    instance_info.pApplicationInfo = &app;
    instance_info.enabledExtensionCount = 1;
    instance_info.ppEnabledExtensionNames = instance_extensions;
    instance_info.flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    if (vkCreateInstance(&instance_info, NULL, &instance) != VK_SUCCESS)
    {
        free(shader_words);
        return 3;
    }
    if (vkEnumeratePhysicalDevices(instance, &device_count, NULL) != VK_SUCCESS || !device_count)
        goto fail_instance;
    if (vkEnumeratePhysicalDevices(instance, &device_count, &physical) != VK_SUCCESS)
        goto fail_instance;
    vkGetPhysicalDeviceProperties(physical, &properties);
    printf("MOLTENVK_DEVICE %s API_%u.%u.%u\n", properties.deviceName,
           VK_API_VERSION_MAJOR(properties.apiVersion),
           VK_API_VERSION_MINOR(properties.apiVersion),
           VK_API_VERSION_PATCH(properties.apiVersion));
    has_robustness = has_device_extension(physical, VK_EXT_ROBUSTNESS_2_EXTENSION_NAME);
    has_xfb = has_device_extension(physical, VK_EXT_TRANSFORM_FEEDBACK_EXTENSION_NAME);
    has_texel_alignment = has_device_extension(physical, VK_EXT_TEXEL_BUFFER_ALIGNMENT_EXTENSION_NAME);
    has_draw_indirect_count = has_device_extension(physical, VK_KHR_DRAW_INDIRECT_COUNT_EXTENSION_NAME);
    printf("MOLTENVK_CAP robustness2=%d transform_feedback=%d texel_alignment=%d draw_indirect_count_ext=%d\n",
           has_robustness, has_xfb, has_texel_alignment, has_draw_indirect_count);

    vulkan12.pNext = &vulkan13;
    vulkan13.pNext = &robustness;
    robustness.pNext = &transform_feedback;
    transform_feedback.pNext = &texel;
    features.pNext = &vulkan12;
    vkGetPhysicalDeviceFeatures2(physical, &features);
    if (has_robustness)
    {
        printf("MOLTENVK_FEATURE robustness_buffer=%u robustness_image=%u null_descriptor=%u\n",
               robustness.robustBufferAccess2, robustness.robustImageAccess2,
               robustness.nullDescriptor);
    }
    printf("MOLTENVK_FEATURE draw_indirect_count=%u\n", vulkan12.drawIndirectCount);
    if (has_xfb)
    {
        printf("MOLTENVK_FEATURE transform_feedback=%u geometry_streams=%u\n",
               transform_feedback.transformFeedback, transform_feedback.geometryStreams);
        printf("MOLTENVK_TRANSFORM_FEEDBACK_ADVERTISED_UNVERIFIED\n");
        fail = 1;
    }
    else printf("MOLTENVK_TRANSFORM_FEEDBACK_NOT_ADVERTISED_OK\n");
    if (has_draw_indirect_count || vulkan12.drawIndirectCount)
    {
        printf("MOLTENVK_DRAW_INDIRECT_COUNT_ADVERTISED_UNVERIFIED\n");
        fail = 1;
    }
    else printf("MOLTENVK_DRAW_INDIRECT_COUNT_NOT_ADVERTISED_OK\n");

    properties2.pNext = &robustness_properties;
    robustness_properties.pNext = &transform_feedback_properties;
    transform_feedback_properties.pNext = &texel_properties;
    vkGetPhysicalDeviceProperties2(physical, &properties2);
    if (has_xfb)
        printf("MOLTENVK_XFB_PROPERTIES queries=%u draw=%u\n",
               transform_feedback_properties.transformFeedbackQueries,
               transform_feedback_properties.transformFeedbackDraw);
    printf("MOLTENVK_TYPED_BUFFER_ALIGNMENT storage=%llu uniform=%llu storage_single=%u uniform_single=%u\n",
           (unsigned long long)texel_properties.storageTexelBufferOffsetAlignmentBytes,
           (unsigned long long)texel_properties.uniformTexelBufferOffsetAlignmentBytes,
           texel_properties.storageTexelBufferOffsetSingleTexelAlignment,
           texel_properties.uniformTexelBufferOffsetSingleTexelAlignment);
    if (texel_properties.storageTexelBufferOffsetAlignmentBytes &&
        texel_properties.uniformTexelBufferOffsetAlignmentBytes)
        printf("MOLTENVK_TYPED_BUFFER_ALIGNMENT_QUERY_OK\n");
    else
    {
        printf("MOLTENVK_TYPED_BUFFER_ALIGNMENT_QUERY_UNAVAILABLE\n");
        fail = 1;
    }

    vkGetPhysicalDeviceQueueFamilyProperties(physical, &queue_count, NULL);
    queues = calloc(queue_count ? queue_count : 1, sizeof(*queues));
    if (!queues) goto fail_instance;
    vkGetPhysicalDeviceQueueFamilyProperties(physical, &queue_count, queues);
    for (uint32_t i = 0; i < queue_count; ++i)
        if (queues[i].queueFlags & VK_QUEUE_COMPUTE_BIT)
        {
            queue_family = i;
            break;
        }
    if (queue_family == UINT32_MAX) goto fail_instance;

    if (has_robustness)
    {
        device_extensions[device_extension_count++] = VK_EXT_ROBUSTNESS_2_EXTENSION_NAME;
    }
    queue_info.queueFamilyIndex = queue_family;
    queue_info.queueCount = 1;
    queue_info.pQueuePriorities = &priority;
    device_info.queueCreateInfoCount = 1;
    device_info.pQueueCreateInfos = &queue_info;
    device_info.enabledExtensionCount = device_extension_count;
    device_info.ppEnabledExtensionNames = device_extensions;
    device_info.pNext = has_robustness ? &robustness : NULL;
    if (has_robustness)
    {
        robustness.pNext = NULL;
        robustness.robustBufferAccess2 = robustness.robustBufferAccess2;
        robustness.robustImageAccess2 = robustness.robustImageAccess2;
        robustness.nullDescriptor = robustness.nullDescriptor;
    }
    if (vkCreateDevice(physical, &device_info, NULL, &device) != VK_SUCCESS)
        goto fail_instance;
    vkGetDeviceQueue(device, queue_family, 0, &queue);

    if (has_robustness && robustness.nullDescriptor)
    {
        int result = run_storage_read(physical, device, queue, queue_family,
                                      shader_words, shader_word_count, 1, 0);
        printf(result == 0 ? "MOLTENVK_NULL_DESCRIPTOR_BEHAVIOR_OK\n" :
                             "MOLTENVK_NULL_DESCRIPTOR_BEHAVIOR_FAIL\n");
        if (result) fail = 1;
    }
    else printf("MOLTENVK_NULL_DESCRIPTOR_NOT_ADVERTISED_OK\n");
    if (has_robustness && robustness.robustBufferAccess2)
    {
        int result = run_storage_read(physical, device, queue, queue_family,
                                      shader_words, shader_word_count, 0, 1);
        printf(result == 0 ? "MOLTENVK_ROBUST_BUFFER_BEHAVIOR_OK\n" :
                             "MOLTENVK_ROBUST_BUFFER_BEHAVIOR_FAIL\n");
        if (result) fail = 1;
    }
    else printf("MOLTENVK_ROBUST_BUFFER_NOT_ADVERTISED_OK\n");

    if (has_robustness && robustness.robustImageAccess2)
    {
        uint32_t *image_shader_words = NULL;
        size_t image_shader_word_count = 0;
        if (load_spirv(image_shader_path, &image_shader_words, &image_shader_word_count))
        {
            printf("MOLTENVK_ROBUST_IMAGE_BEHAVIOR_FAIL\n");
            fail = 1;
        }
        else
        {
            int result = run_image_read(physical, device, queue, queue_family,
                                        image_shader_words, image_shader_word_count);
            printf(result == 0 ? "MOLTENVK_ROBUST_IMAGE_BEHAVIOR_OK\n" :
                                 "MOLTENVK_ROBUST_IMAGE_BEHAVIOR_FAIL\n");
            if (result) fail = 1;
            free(image_shader_words);
        }
    }
    else printf("MOLTENVK_ROBUST_IMAGE_NOT_ADVERTISED_OK\n");

    vkDestroyDevice(device, NULL);
    free(queues);
    vkDestroyInstance(instance, NULL);
    free(shader_words);
    if (fail) return 1;
    printf("MOLTENVK_BEHAVIOR_CONTRACT_OK\n");
    return 0;

fail_instance:
    free(queues);
    if (device) vkDestroyDevice(device, NULL);
    vkDestroyInstance(instance, NULL);
    free(shader_words);
    return 4;
}
