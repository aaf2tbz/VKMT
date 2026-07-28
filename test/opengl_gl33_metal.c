#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>

#define GL_VERTEX_SHADER 0x8b31
#define GL_FRAGMENT_SHADER 0x8b30
#define GL_COMPILE_STATUS 0x8b81
#define GL_LINK_STATUS 0x8b82

typedef GLuint (WINAPI *PFNGLCREATESHADERPROC)(GLenum);
typedef void (WINAPI *PFNGLSHADERSOURCEPROC)(GLuint, GLsizei, const char *const *, const GLint *);
typedef void (WINAPI *PFNGLCOMPILESHADERPROC)(GLuint);
typedef void (WINAPI *PFNGLGETSHADERIVPROC)(GLuint, GLenum, GLint *);
typedef void (WINAPI *PFNGLGETSHADERINFOLOGPROC)(GLuint, GLsizei, GLsizei *, char *);
typedef GLuint (WINAPI *PFNGLCREATEPROGRAMPROC)(void);
typedef void (WINAPI *PFNGLATTACHSHADERPROC)(GLuint, GLuint);
typedef void (WINAPI *PFNGLLINKPROGRAMPROC)(GLuint);
typedef void (WINAPI *PFNGLGETPROGRAMIVPROC)(GLuint, GLenum, GLint *);
typedef void (WINAPI *PFNGLGETPROGRAMINFOLOGPROC)(GLuint, GLsizei, GLsizei *, char *);
typedef void (WINAPI *PFNGLUSEPROGRAMPROC)(GLuint);
typedef void (WINAPI *PFNGLDELETEOBJECTPROC)(GLuint);

static void *get_gl_proc(const char *name)
{
    PROC proc = wglGetProcAddress(name);
    HMODULE module;

    if (proc) return (void *)proc;
    module = GetModuleHandleA("opengl32.dll");
    return module ? (void *)GetProcAddress(module, name) : NULL;
}

static int compile_one(GLuint shader, const char *source,
                       PFNGLSHADERSOURCEPROC shader_source,
                       PFNGLCOMPILESHADERPROC compile_shader,
                       PFNGLGETSHADERIVPROC get_shader_iv,
                       PFNGLGETSHADERINFOLOGPROC get_shader_log)
{
    char log[2048] = {0};
    GLint compiled = 0;

    shader_source(shader, 1, &source, NULL);
    compile_shader(shader);
    get_shader_iv(shader, GL_COMPILE_STATUS, &compiled);
    if (!compiled)
    {
        get_shader_log(shader, sizeof(log), NULL, log);
        printf("FAIL GLSL330 compile: %s\n", log);
        return 0;
    }
    return 1;
}

int main(void)
{
#ifdef VKMT_OPENGL_GLSL450
    static const char version_name[] = "GLSL450";
    static const char success_marker[] = "OPENGL_GL450_METAL_DRAW_READBACK_OK";
    static const char vertex_source[] =
        "#version 450 core\n"
        "const vec2 positions[3] = vec2[3](vec2(-1.0, -1.0),"
        " vec2(3.0, -1.0), vec2(-1.0, 3.0));\n"
        "void main() { gl_Position = vec4(positions[gl_VertexID], 0.0, 1.0); }\n";
    static const char fragment_source[] =
        "#version 450 core\n"
        "layout(location = 0) out vec4 color;\n"
        "void main() { color = vec4(0.2, 0.4, 0.6, 1.0); }\n";
#else
    static const char version_name[] = "GLSL330";
    static const char success_marker[] = "OPENGL_GL330_METAL_DRAW_READBACK_OK";
    static const char vertex_source[] =
        "#version 330 core\n"
        "const vec2 positions[3] = vec2[3](vec2(-1.0, -1.0),"
        " vec2(3.0, -1.0), vec2(-1.0, 3.0));\n"
        "void main() { gl_Position = vec4(positions[gl_VertexID], 0.0, 1.0); }\n";
    static const char fragment_source[] =
        "#version 330 core\n"
        "out vec4 color;\n"
        "void main() { color = vec4(0.2, 0.4, 0.6, 1.0); }\n";
#endif
    PIXELFORMATDESCRIPTOR pfd = {0};
    PFNGLCREATESHADERPROC create_shader;
    PFNGLSHADERSOURCEPROC shader_source;
    PFNGLCOMPILESHADERPROC compile_shader;
    PFNGLGETSHADERIVPROC get_shader_iv;
    PFNGLGETSHADERINFOLOGPROC get_shader_log;
    PFNGLCREATEPROGRAMPROC create_program;
    PFNGLATTACHSHADERPROC attach_shader;
    PFNGLLINKPROGRAMPROC link_program;
    PFNGLGETPROGRAMIVPROC get_program_iv;
    PFNGLGETPROGRAMINFOLOGPROC get_program_log;
    PFNGLUSEPROGRAMPROC use_program;
    PFNGLDELETEOBJECTPROC delete_shader, delete_program;
    HWND window;
    HDC dc;
    HGLRC context;
    GLuint vertex, fragment, program;
    GLint linked = 0;
    unsigned char pixel[4] = {0};
    char log[2048] = {0};
    int format;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (!LoadLibraryA("opengl32.dll"))
    {
        printf("FAIL opengl32 load error=%lu\n", GetLastError());
        return 10;
    }
    window = CreateWindowA("STATIC", "VKMT GL330 Metal", WS_OVERLAPPEDWINDOW,
                           0, 0, 64, 64, NULL, NULL, NULL, NULL);
    if (!window) return 11;
    dc = GetDC(window);
    pfd.nSize = sizeof(pfd);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    format = ChoosePixelFormat(dc, &pfd);
    if (!format || !SetPixelFormat(dc, format, &pfd)) return 12;
    context = wglCreateContext(dc);
    if (!context || !wglMakeCurrent(dc, context)) return 13;

#define LOAD(type, variable, symbol) do { \
    variable = (type)get_gl_proc(symbol); \
    if (!variable) { printf("FAIL missing %s\n", symbol); return 14; } \
} while (0)
    LOAD(PFNGLCREATESHADERPROC, create_shader, "glCreateShader");
    LOAD(PFNGLSHADERSOURCEPROC, shader_source, "glShaderSource");
    LOAD(PFNGLCOMPILESHADERPROC, compile_shader, "glCompileShader");
    LOAD(PFNGLGETSHADERIVPROC, get_shader_iv, "glGetShaderiv");
    LOAD(PFNGLGETSHADERINFOLOGPROC, get_shader_log, "glGetShaderInfoLog");
    LOAD(PFNGLCREATEPROGRAMPROC, create_program, "glCreateProgram");
    LOAD(PFNGLATTACHSHADERPROC, attach_shader, "glAttachShader");
    LOAD(PFNGLLINKPROGRAMPROC, link_program, "glLinkProgram");
    LOAD(PFNGLGETPROGRAMIVPROC, get_program_iv, "glGetProgramiv");
    LOAD(PFNGLGETPROGRAMINFOLOGPROC, get_program_log, "glGetProgramInfoLog");
    LOAD(PFNGLUSEPROGRAMPROC, use_program, "glUseProgram");
    LOAD(PFNGLDELETEOBJECTPROC, delete_shader, "glDeleteShader");
    LOAD(PFNGLDELETEOBJECTPROC, delete_program, "glDeleteProgram");
#undef LOAD

    vertex = create_shader(GL_VERTEX_SHADER);
    fragment = create_shader(GL_FRAGMENT_SHADER);
    if (!vertex || !fragment ||
        !compile_one(vertex, vertex_source, shader_source, compile_shader,
                     get_shader_iv, get_shader_log) ||
        !compile_one(fragment, fragment_source, shader_source, compile_shader,
                     get_shader_iv, get_shader_log))
        return 15;
    printf("OPENGL_%s_COMPILE_OK\n", version_name);

    program = create_program();
    attach_shader(program, vertex);
    attach_shader(program, fragment);
    link_program(program);
    get_program_iv(program, GL_LINK_STATUS, &linked);
    if (!linked)
    {
        get_program_log(program, sizeof(log), NULL, log);
        printf("FAIL GLSL330 link: %s\n", log);
        return 16;
    }
    printf("OPENGL_%s_LINK_OK\n", version_name);

    use_program(program);
    glViewport(0, 0, 64, 64);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glReadPixels(32, 32, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    printf("%s Metal readback rgba=%u,%u,%u,%u error=0x%x\n",
           version_name, pixel[0], pixel[1], pixel[2], pixel[3], (unsigned)glGetError());
    if (pixel[0] < 47 || pixel[0] > 55 ||
        pixel[1] < 98 || pixel[1] > 106 ||
        pixel[2] < 149 || pixel[2] > 157 || pixel[3] < 250)
        return 17;
    printf("%s\n", success_marker);

    use_program(0);
    delete_program(program);
    delete_shader(fragment);
    delete_shader(vertex);
    wglMakeCurrent(NULL, NULL);
    wglDeleteContext(context);
    ReleaseDC(window, dc);
    DestroyWindow(window);
    return 0;
}
