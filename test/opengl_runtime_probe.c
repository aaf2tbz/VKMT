#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
#include <string.h>

#ifndef GL_VERTEX_SHADER
#define GL_VERTEX_SHADER 0x8b31
#define GL_FRAGMENT_SHADER 0x8b30
#define GL_COMPILE_STATUS 0x8b81
#define GL_LINK_STATUS 0x8b82
#endif

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
typedef void (WINAPI *PFNGLDELETESHADERPROC)(GLuint);
typedef void (WINAPI *PFNGLDELETEPROGRAMPROC)(GLuint);
typedef void (WINAPI *PFNGLGENFRAMEBUFFERSEXTPROC)(GLsizei, GLuint *);
typedef void (WINAPI *PFNGLBINDFRAMEBUFFEREXTPROC)(GLenum, GLuint);
typedef void (WINAPI *PFNGLFRAMEBUFFERTEXTURE2DEXTPROC)(GLenum, GLenum, GLenum, GLuint, GLint);
typedef GLenum (WINAPI *PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC)(GLenum);
typedef void (WINAPI *PFNGLDELETEFRAMEBUFFERSEXTPROC)(GLsizei, const GLuint *);

static void *get_gl_proc(const char *name)
{
    PROC proc = wglGetProcAddress(name);
    HMODULE module;

    if (proc) return (void *)proc;
    module = GetModuleHandleA("opengl32.dll");
    return module ? (void *)GetProcAddress(module, name) : NULL;
}

static int compile_shader(GLuint shader, const char *source,
                          PFNGLSHADERSOURCEPROC shader_source,
                          PFNGLCOMPILESHADERPROC compile,
                          PFNGLGETSHADERIVPROC get_shader_iv,
                          PFNGLGETSHADERINFOLOGPROC get_shader_log)
{
    GLint status = 0;
    char log[1024] = {0};

    shader_source(shader, 1, &source, NULL);
    compile(shader);
    get_shader_iv(shader, GL_COMPILE_STATUS, &status);
    if (!status)
    {
        get_shader_log(shader, sizeof(log), NULL, log);
        printf("FAIL shader compile: %s\n", log);
        return 0;
    }
    return 1;
}

int main(void)
{
    static const char vertex_source[] =
        "#version 120\n"
        "varying vec4 v_color;\n"
        "void main() { gl_Position = gl_Vertex; v_color = gl_Color; }\n";
    static const char fragment_source[] =
        "#version 120\n"
        "varying vec4 v_color;\n"
        "void main() { gl_FragColor = vec4(0.25, 0.75, 0.5, 1.0); }\n";
    static const GLfloat triangle[] = {
        -1.0f, -1.0f,
         1.0f, -1.0f,
         0.0f,  1.0f
    };
    PIXELFORMATDESCRIPTOR pfd = {0};
    PFNGLCREATESHADERPROC create_shader;
    PFNGLSHADERSOURCEPROC shader_source;
    PFNGLCOMPILESHADERPROC compile_shader_proc;
    PFNGLGETSHADERIVPROC get_shader_iv;
    PFNGLGETSHADERINFOLOGPROC get_shader_log;
    PFNGLCREATEPROGRAMPROC create_program;
    PFNGLATTACHSHADERPROC attach_shader;
    PFNGLLINKPROGRAMPROC link_program;
    PFNGLGETPROGRAMIVPROC get_program_iv;
    PFNGLGETPROGRAMINFOLOGPROC get_program_log;
    PFNGLUSEPROGRAMPROC use_program;
    PFNGLDELETESHADERPROC delete_shader;
    PFNGLDELETEPROGRAMPROC delete_program;
    PFNGLGENFRAMEBUFFERSEXTPROC gen_framebuffers;
    PFNGLBINDFRAMEBUFFEREXTPROC bind_framebuffer;
    PFNGLFRAMEBUFFERTEXTURE2DEXTPROC framebuffer_texture_2d;
    PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC check_framebuffer_status;
    PFNGLDELETEFRAMEBUFFERSEXTPROC delete_framebuffers;
    HMODULE opengl;
    HWND hwnd;
    HDC dc;
    HGLRC context;
    GLuint vertex_shader, fragment_shader, program;
    GLuint framebuffer = 0, color_texture = 0;
    GLint linked = 0;
    int format;
    unsigned char pixel[4] = {0};
    char log[1024] = {0};

    setvbuf(stdout, NULL, _IONBF, 0);
    opengl = LoadLibraryA("opengl32.dll");
    if (!opengl || !GetProcAddress(opengl, "wglCreateContext") ||
        !GetProcAddress(opengl, "glReadPixels"))
    {
        printf("FAIL opengl32 load/exports error=%lu\n", GetLastError());
        return 10;
    }
    printf("PASS opengl32 load/exports pointer_bits=%u\n", (unsigned)(sizeof(void *) * 8));

    hwnd = CreateWindowA("STATIC", "VKMT OpenGL Probe", WS_OVERLAPPEDWINDOW,
                         CW_USEDEFAULT, CW_USEDEFAULT, 64, 64, NULL, NULL, NULL, NULL);
    if (!hwnd)
    {
        printf("FAIL CreateWindow error=%lu\n", GetLastError());
        return 12;
    }
    dc = GetDC(hwnd);
    pfd.nSize = sizeof(pfd);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    format = ChoosePixelFormat(dc, &pfd);
    if (!format || !SetPixelFormat(dc, format, &pfd))
    {
        printf("FAIL pixel format error=%lu\n", GetLastError());
        return 13;
    }
    context = wglCreateContext(dc);
    if (!context || !wglMakeCurrent(dc, context))
    {
        printf("FAIL WGL context error=%lu\n", GetLastError());
        return 14;
    }
    printf("PASS context version=%s renderer=%s\n",
           glGetString(GL_VERSION), glGetString(GL_RENDERER));

    gen_framebuffers = (PFNGLGENFRAMEBUFFERSEXTPROC)get_gl_proc("glGenFramebuffersEXT");
    if (!gen_framebuffers)
        gen_framebuffers = (PFNGLGENFRAMEBUFFERSEXTPROC)get_gl_proc("glGenFramebuffers");
    bind_framebuffer = (PFNGLBINDFRAMEBUFFEREXTPROC)get_gl_proc("glBindFramebufferEXT");
    if (!bind_framebuffer)
        bind_framebuffer = (PFNGLBINDFRAMEBUFFEREXTPROC)get_gl_proc("glBindFramebuffer");
    framebuffer_texture_2d =
        (PFNGLFRAMEBUFFERTEXTURE2DEXTPROC)get_gl_proc("glFramebufferTexture2DEXT");
    if (!framebuffer_texture_2d)
        framebuffer_texture_2d =
            (PFNGLFRAMEBUFFERTEXTURE2DEXTPROC)get_gl_proc("glFramebufferTexture2D");
    check_framebuffer_status =
        (PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC)get_gl_proc("glCheckFramebufferStatusEXT");
    if (!check_framebuffer_status)
        check_framebuffer_status =
            (PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC)get_gl_proc("glCheckFramebufferStatus");
    delete_framebuffers =
        (PFNGLDELETEFRAMEBUFFERSEXTPROC)get_gl_proc("glDeleteFramebuffersEXT");
    if (!delete_framebuffers)
        delete_framebuffers =
            (PFNGLDELETEFRAMEBUFFERSEXTPROC)get_gl_proc("glDeleteFramebuffers");
    if (!gen_framebuffers || !bind_framebuffer || !framebuffer_texture_2d ||
        !check_framebuffer_status || !delete_framebuffers)
    {
        printf("FAIL missing framebuffer object API gen=%p bind=%p attach=%p check=%p delete=%p\n",
               gen_framebuffers, bind_framebuffer, framebuffer_texture_2d,
               check_framebuffer_status, delete_framebuffers);
        return 15;
    }
    glGenTextures(1, &color_texture);
    glBindTexture(GL_TEXTURE_2D, color_texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 64, 64, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    gen_framebuffers(1, &framebuffer);
    bind_framebuffer(0x8d40, framebuffer); /* GL_FRAMEBUFFER_EXT */
    framebuffer_texture_2d(0x8d40, 0x8ce0, GL_TEXTURE_2D, color_texture, 0);
    if (check_framebuffer_status(0x8d40) != 0x8cd5) /* GL_FRAMEBUFFER_COMPLETE_EXT */
    {
        printf("FAIL offscreen framebuffer incomplete\n");
        return 15;
    }
    printf("PASS GL2 offscreen framebuffer\n");

    glViewport(0, 0, 64, 64);
    glClearColor(0.125f, 0.5f, 0.75f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glFinish();
    glReadPixels(32, 32, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    if (pixel[0] < 25 || pixel[0] > 40 || pixel[1] < 120 || pixel[1] > 135 ||
        pixel[2] < 185 || pixel[2] > 200 || pixel[3] < 250)
    {
        printf("FAIL clear/readback rgba=%u,%u,%u,%u\n", pixel[0], pixel[1], pixel[2], pixel[3]);
        return 16;
    }
    printf("PASS clear/readback rgba=%u,%u,%u,%u\n", pixel[0], pixel[1], pixel[2], pixel[3]);

#define GET_PROC(type, variable, name) \
    do { variable = (type)get_gl_proc(name); if (!variable) { \
        printf("FAIL missing %s\n", name); return 17; } } while (0)
    GET_PROC(PFNGLCREATESHADERPROC, create_shader, "glCreateShader");
    GET_PROC(PFNGLSHADERSOURCEPROC, shader_source, "glShaderSource");
    GET_PROC(PFNGLCOMPILESHADERPROC, compile_shader_proc, "glCompileShader");
    GET_PROC(PFNGLGETSHADERIVPROC, get_shader_iv, "glGetShaderiv");
    GET_PROC(PFNGLGETSHADERINFOLOGPROC, get_shader_log, "glGetShaderInfoLog");
    GET_PROC(PFNGLCREATEPROGRAMPROC, create_program, "glCreateProgram");
    GET_PROC(PFNGLATTACHSHADERPROC, attach_shader, "glAttachShader");
    GET_PROC(PFNGLLINKPROGRAMPROC, link_program, "glLinkProgram");
    GET_PROC(PFNGLGETPROGRAMIVPROC, get_program_iv, "glGetProgramiv");
    GET_PROC(PFNGLGETPROGRAMINFOLOGPROC, get_program_log, "glGetProgramInfoLog");
    GET_PROC(PFNGLUSEPROGRAMPROC, use_program, "glUseProgram");
    GET_PROC(PFNGLDELETESHADERPROC, delete_shader, "glDeleteShader");
    GET_PROC(PFNGLDELETEPROGRAMPROC, delete_program, "glDeleteProgram");
#undef GET_PROC

    vertex_shader = create_shader(GL_VERTEX_SHADER);
    fragment_shader = create_shader(GL_FRAGMENT_SHADER);
    if (!vertex_shader || !fragment_shader ||
        !compile_shader(vertex_shader, vertex_source, shader_source, compile_shader_proc,
                        get_shader_iv, get_shader_log) ||
        !compile_shader(fragment_shader, fragment_source, shader_source, compile_shader_proc,
                        get_shader_iv, get_shader_log))
        return 18;

    program = create_program();
    attach_shader(program, vertex_shader);
    attach_shader(program, fragment_shader);
    link_program(program);
    get_program_iv(program, GL_LINK_STATUS, &linked);
    if (!linked)
    {
        get_program_log(program, sizeof(log), NULL, log);
        printf("FAIL program link: %s\n", log);
        return 19;
    }
    use_program(program);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glEnableClientState(GL_VERTEX_ARRAY);
    glVertexPointer(2, GL_FLOAT, 0, triangle);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glDisableClientState(GL_VERTEX_ARRAY);
    glFinish();
    glReadPixels(32, 24, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    if (pixel[0] + pixel[1] + pixel[2] < 100)
    {
        printf("FAIL shader draw/readback rgba=%u,%u,%u,%u\n", pixel[0], pixel[1], pixel[2], pixel[3]);
        return 20;
    }
    printf("PASS GLSL120 draw/readback rgba=%u,%u,%u,%u\n", pixel[0], pixel[1], pixel[2], pixel[3]);

    use_program(0);
    delete_program(program);
    delete_shader(fragment_shader);
    delete_shader(vertex_shader);
    bind_framebuffer(0x8d40, 0);
    delete_framebuffers(1, &framebuffer);
    glDeleteTextures(1, &color_texture);
    wglMakeCurrent(NULL, NULL);
    wglDeleteContext(context);
    ReleaseDC(hwnd, dc);
    DestroyWindow(hwnd);
    FreeLibrary(opengl);
    printf("PASS OpenGL runtime probe\n");
    return 0;
}
