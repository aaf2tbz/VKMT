#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>

#define GL_VERTEX_SHADER 0x8b31
#define GL_COMPILE_STATUS 0x8b81
#define GL_INFO_LOG_LENGTH 0x8b84

typedef uint32_t (*create_shader_fn)(uint32_t);
typedef void (*shader_source_fn)(uint32_t, int32_t, const char **, const int32_t *);
typedef void (*compile_shader_fn)(uint32_t);
typedef void (*get_shader_iv_fn)(uint32_t, uint32_t, int32_t *);
typedef void (*get_shader_log_fn)(uint32_t, int32_t, int32_t *, char *);

int main(int argc, char **argv)
{
    static const char source[] =
        "#version 330 core\n"
        "layout(location = 0) in vec3 position;\n"
        "void main() { gl_Position = vec4(position, 1.0); }\n";
    create_shader_fn create_shader;
    shader_source_fn shader_source;
    compile_shader_fn compile_shader;
    get_shader_iv_fn get_shader_iv;
    get_shader_log_fn get_shader_log;
    const char *source_ptr = source;
    void *module;
    uint32_t shader;
    int32_t status = 0, log_length = 0;
    char log[4096] = {0};

    if (argc != 2)
    {
        fprintf(stderr, "usage: %s metalsharp-opengl.dylib\n", argv[0]);
        return 2;
    }
    module = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!module)
    {
        fprintf(stderr, "FAIL dlopen: %s\n", dlerror());
        return 3;
    }
    *(void **)(&create_shader) = dlsym(module, "glCreateShader");
    *(void **)(&shader_source) = dlsym(module, "glShaderSource");
    *(void **)(&compile_shader) = dlsym(module, "glCompileShader");
    *(void **)(&get_shader_iv) = dlsym(module, "glGetShaderiv");
    *(void **)(&get_shader_log) = dlsym(module, "glGetShaderInfoLog");
    if (!create_shader || !shader_source || !compile_shader || !get_shader_iv || !get_shader_log)
    {
        fprintf(stderr, "FAIL MetalSharp shader exports\n");
        return 4;
    }

    shader = create_shader(GL_VERTEX_SHADER);
    shader_source(shader, 1, &source_ptr, NULL);
    compile_shader(shader);
    get_shader_iv(shader, GL_COMPILE_STATUS, &status);
    get_shader_iv(shader, GL_INFO_LOG_LENGTH, &log_length);
    if (!status)
    {
        get_shader_log(shader, sizeof(log), NULL, log);
        fprintf(stderr, "FAIL GLSL330 translation: %s\n", log);
        return 5;
    }
    printf("PASS GLSL330 glslang -> SPIR-V -> MSL translation shader=%u log_length=%d\n",
           shader, log_length);
    dlclose(module);
    return 0;
}
