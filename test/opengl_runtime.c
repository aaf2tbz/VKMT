#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
#include <string.h>

typedef HGLRC (WINAPI *p_wglCreateContext)(HDC);
typedef BOOL (WINAPI *p_wglDeleteContext)(HGLRC);
typedef BOOL (WINAPI *p_wglMakeCurrent)(HDC,HGLRC);
typedef PROC (WINAPI *p_wglGetProcAddress)(LPCSTR);
typedef const GLubyte *(APIENTRY *p_glGetString)(GLenum);
typedef void (APIENTRY *p_glClearColor)(GLfloat,GLfloat,GLfloat,GLfloat);
typedef void (APIENTRY *p_glClear)(GLbitfield);
typedef void (APIENTRY *p_glFinish)(void);
typedef void (APIENTRY *p_glReadPixels)(GLint,GLint,GLsizei,GLsizei,GLenum,GLenum,void *);
typedef void (APIENTRY *p_glViewport)(GLint,GLint,GLsizei,GLsizei);
typedef GLenum (APIENTRY *p_glGetError)(void);
typedef void (APIENTRY *p_glReadBuffer)(GLenum);
typedef void (APIENTRY *p_glGenTextures)(GLsizei,GLuint *);
typedef void (APIENTRY *p_glBindTexture)(GLenum,GLuint);
typedef void (APIENTRY *p_glTexParameteri)(GLenum,GLenum,GLint);
typedef void (APIENTRY *p_glTexImage2D)(GLenum,GLint,GLint,GLsizei,GLsizei,GLint,GLenum,GLenum,const void *);
typedef void (APIENTRY *p_glDeleteTextures)(GLsizei,const GLuint *);
typedef void (APIENTRY *p_glGenFramebuffersEXT)(GLsizei,GLuint *);
typedef void (APIENTRY *p_glBindFramebufferEXT)(GLenum,GLuint);
typedef void (APIENTRY *p_glFramebufferTexture2DEXT)(GLenum,GLenum,GLenum,GLuint,GLint);
typedef GLenum (APIENTRY *p_glCheckFramebufferStatusEXT)(GLenum);
typedef void (APIENTRY *p_glDeleteFramebuffersEXT)(GLsizei,const GLuint *);

#ifndef GL_FRAMEBUFFER_EXT
#define GL_FRAMEBUFFER_EXT 0x8d40
#define GL_COLOR_ATTACHMENT0_EXT 0x8ce0
#define GL_FRAMEBUFFER_COMPLETE_EXT 0x8cd5
#endif
#ifndef GL_RGBA8
#define GL_RGBA8 0x8058
#endif

static HANDLE marker;

static void mark(const char *text)
{
    DWORD written;
    WriteFile(marker, text, (DWORD)strlen(text), &written, NULL);
    WriteFile(marker, "\r\n", 2, &written, NULL);
    FlushFileBuffers(marker);
}

int main(int argc, char **argv)
{
    PIXELFORMATDESCRIPTOR pfd = {0};
    p_wglCreateContext create_context;
    p_wglDeleteContext delete_context;
    p_wglMakeCurrent make_current;
    p_wglGetProcAddress get_proc_address;
    p_glGetString get_string;
    p_glClearColor clear_color;
    p_glClear clear;
    p_glFinish finish;
    p_glReadPixels read_pixels;
    p_glViewport viewport;
    p_glGetError get_error;
    p_glReadBuffer read_buffer;
    p_glGenTextures gen_textures;
    p_glBindTexture bind_texture;
    p_glTexParameteri tex_parameteri;
    p_glTexImage2D tex_image_2d;
    p_glDeleteTextures delete_textures;
    p_glGenFramebuffersEXT gen_framebuffers;
    p_glBindFramebufferEXT bind_framebuffer;
    p_glFramebufferTexture2DEXT framebuffer_texture_2d;
    p_glCheckFramebufferStatusEXT check_framebuffer_status;
    p_glDeleteFramebuffersEXT delete_framebuffers;
    const GLubyte *version, *renderer;
    HMODULE opengl;
    HGLRC context;
    HWND window;
    HDC dc;
    int format;
    GLuint texture = 0, framebuffer = 0;
    unsigned char pixel[4] = {0};

    if (argc != 2) return 2;
    marker = CreateFileA(argv[1], GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS,
                         FILE_ATTRIBUTE_NORMAL, NULL);
    if (marker == INVALID_HANDLE_VALUE) return 3;
    mark("OPENGL_PROBE_PROCESS_STARTED");

    opengl = LoadLibraryA("opengl32.dll");
    if (!opengl)
    {
        char line[80];
        snprintf(line, sizeof(line), "OPENGL32_LOAD_FAILED_%lu", GetLastError());
        mark(line);
        return 4;
    }
    mark("OPENGL32_LOAD_OK");

#define RESOLVE(target, symbol, type) do { target = (type)GetProcAddress(opengl, symbol); if (!target) { mark("OPENGL32_EXPORTS_FAILED"); return 5; } } while (0)
    RESOLVE(create_context, "wglCreateContext", p_wglCreateContext);
    RESOLVE(delete_context, "wglDeleteContext", p_wglDeleteContext);
    RESOLVE(make_current, "wglMakeCurrent", p_wglMakeCurrent);
    RESOLVE(get_proc_address, "wglGetProcAddress", p_wglGetProcAddress);
    RESOLVE(get_string, "glGetString", p_glGetString);
    RESOLVE(clear_color, "glClearColor", p_glClearColor);
    RESOLVE(clear, "glClear", p_glClear);
    RESOLVE(finish, "glFinish", p_glFinish);
    RESOLVE(read_pixels, "glReadPixels", p_glReadPixels);
    RESOLVE(viewport, "glViewport", p_glViewport);
    RESOLVE(get_error, "glGetError", p_glGetError);
    RESOLVE(read_buffer, "glReadBuffer", p_glReadBuffer);
    RESOLVE(gen_textures, "glGenTextures", p_glGenTextures);
    RESOLVE(bind_texture, "glBindTexture", p_glBindTexture);
    RESOLVE(tex_parameteri, "glTexParameteri", p_glTexParameteri);
    RESOLVE(tex_image_2d, "glTexImage2D", p_glTexImage2D);
    RESOLVE(delete_textures, "glDeleteTextures", p_glDeleteTextures);
#undef RESOLVE
    mark("OPENGL32_EXPORTS_OK");

    window = CreateWindowExA(0, "STATIC", "VKMT OpenGL Probe",
                             WS_OVERLAPPEDWINDOW, 0, 0, 64, 64, NULL, NULL, NULL, NULL);
    if (!window)
    {
        char line[80];
        snprintf(line, sizeof(line), "OPENGL_WINDOW_FAILED_%lu", GetLastError());
        mark(line);
        return 7;
    }
    mark("OPENGL_WINDOW_OK");

    dc = GetDC(window);
    {
        char line[128];
        snprintf(line, sizeof(line), "OPENGL_DC_%p_TYPE_%lu_FORMATS_%d_ERROR_%lu",
                 dc, GetObjectType(dc), DescribePixelFormat(dc, 0, 0, NULL), GetLastError());
        mark(line);
    }
    pfd.nSize = sizeof(pfd);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cAlphaBits = 8;
    pfd.cDepthBits = 24;
    pfd.iLayerType = PFD_MAIN_PLANE;
    format = ChoosePixelFormat(dc, &pfd);
    {
        char line[96];
        snprintf(line, sizeof(line), "OPENGL_CHOSEN_FORMAT_%d_ERROR_%lu", format, GetLastError());
        mark(line);
    }
    if (!format)
    {
        mark("OPENGL_CHOOSE_PIXEL_FORMAT_FAILED");
        return 8;
    }
    if (!SetPixelFormat(dc, format, &pfd))
    {
        char line[96];
        snprintf(line, sizeof(line), "OPENGL_SET_PIXEL_FORMAT_FAILED_%lu", GetLastError());
        mark(line);
        return 8;
    }
    mark("OPENGL_PIXEL_FORMAT_OK");

    context = create_context(dc);
    if (!context || !make_current(dc, context))
    {
        mark("OPENGL_CONTEXT_FAILED");
        return 9;
    }
    mark("OPENGL_CONTEXT_OK");

    version = get_string(GL_VERSION);
    renderer = get_string(GL_RENDERER);
    if (!version || !renderer)
    {
        mark("OPENGL_IDENTITY_FAILED");
        return 10;
    }
    {
        char line[512];
        snprintf(line, sizeof(line), "OPENGL_VERSION_%s", version);
        mark(line);
        snprintf(line, sizeof(line), "OPENGL_RENDERER_%s", renderer);
        mark(line);
    }

    gen_framebuffers = (p_glGenFramebuffersEXT)get_proc_address("glGenFramebuffersEXT");
    bind_framebuffer = (p_glBindFramebufferEXT)get_proc_address("glBindFramebufferEXT");
    framebuffer_texture_2d = (p_glFramebufferTexture2DEXT)get_proc_address("glFramebufferTexture2DEXT");
    check_framebuffer_status = (p_glCheckFramebufferStatusEXT)get_proc_address("glCheckFramebufferStatusEXT");
    delete_framebuffers = (p_glDeleteFramebuffersEXT)get_proc_address("glDeleteFramebuffersEXT");
    if (!gen_framebuffers || !bind_framebuffer || !framebuffer_texture_2d ||
        !check_framebuffer_status || !delete_framebuffers)
    {
        char line[192];
        snprintf(line, sizeof(line), "OPENGL_FBO_EXPORTS_FAILED_%u_%u_%u_%u_%u",
                 !!gen_framebuffers, !!bind_framebuffer, !!framebuffer_texture_2d,
                 !!check_framebuffer_status, !!delete_framebuffers);
        mark(line);
        return 11;
    }
    mark("OPENGL_FBO_EXPORTS_OK");

    gen_textures(1, &texture);
    bind_texture(GL_TEXTURE_2D, texture);
    tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    tex_image_2d(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    gen_framebuffers(1, &framebuffer);
    bind_framebuffer(GL_FRAMEBUFFER_EXT, framebuffer);
    framebuffer_texture_2d(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT,
                           GL_TEXTURE_2D, texture, 0);
    if (check_framebuffer_status(GL_FRAMEBUFFER_EXT) != GL_FRAMEBUFFER_COMPLETE_EXT)
    {
        mark("OPENGL_FBO_INCOMPLETE");
        return 11;
    }
    mark("OPENGL_FBO_COMPLETE");

    viewport(0, 0, 1, 1);
    clear_color(0.2f, 0.4f, 0.6f, 1.0f);
    clear(GL_COLOR_BUFFER_BIT);
    finish();
    read_buffer(GL_COLOR_ATTACHMENT0_EXT);
    read_pixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    {
        char line[96];
        snprintf(line, sizeof(line), "OPENGL_RENDER_ERROR_%u", get_error());
        mark(line);
        snprintf(line, sizeof(line), "OPENGL_READBACK_RGBA_%u_%u_%u_%u",
                 pixel[0], pixel[1], pixel[2], pixel[3]);
        mark(line);
    }
    if (pixel[0] < 45 || pixel[0] > 58 || pixel[1] < 96 || pixel[1] > 109 ||
        pixel[2] < 147 || pixel[2] > 160 || pixel[3] < 248)
    {
        char line[96];
        snprintf(line, sizeof(line), "OPENGL_READBACK_FAILED_%u_%u_%u_%u",
                 pixel[0], pixel[1], pixel[2], pixel[3]);
        mark(line);
        return 11;
    }
    mark("OPENGL_CLEAR_READBACK_OK");

    bind_framebuffer(GL_FRAMEBUFFER_EXT, 0);
    delete_framebuffers(1, &framebuffer);
    delete_textures(1, &texture);
    make_current(NULL, NULL);
    delete_context(context);
    ReleaseDC(window, dc);
    DestroyWindow(window);
    FreeLibrary(opengl);
    mark("OPENGL_RUNTIME_ALL_OK");
    CloseHandle(marker);
    return 0;
}
