#define SDL_MAIN_HANDLED
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <stdio.h>

static int SDLCALL worker(void *opaque)
{
    int *value = opaque;
    *value = 0x3a;
    return 23;
}

static int fail(const char *gate)
{
    fprintf(stderr, "SDL3_FAIL gate=%s error=%s\n", gate, SDL_GetError());
    SDL_Quit();
    return 1;
}

static void checkpoint(const char *gate)
{
    fprintf(stderr, "SDL3_GATE %s\n", gate);
    fflush(stderr);
}

int main(void)
{
    const int expected = SDL_VERSIONNUM(3, 4, 10);
    const int version = SDL_GetVersion();
    const SDL_PixelFormatDetails *details;
    SDL_Window *window;
    SDL_Surface *surface;
    SDL_Thread *thread;
    SDL_Event event;
    SDL_SharedObject *kernel;
    int thread_value = 0, thread_status = 0;
    Uint8 r = 0, g = 0, b = 0, a = 0;
    Uint32 pixel;

    SDL_SetMainReady();
    checkpoint("start");
    if (version != expected) return fail("version");

    SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "dummy");
    SDL_SetHint(SDL_HINT_AUDIO_DRIVER, "dummy");
    if (!SDL_Init(SDL_INIT_EVENTS | SDL_INIT_VIDEO | SDL_INIT_AUDIO))
        return fail("init");
    checkpoint("init");

    window = SDL_CreateWindow("VKMT SDL3 probe", 32, 32, SDL_WINDOW_HIDDEN);
    if (!window) return fail("window");
    checkpoint("window");

    surface = SDL_CreateSurface(4, 4, SDL_PIXELFORMAT_RGBA32);
    if (!surface) return fail("surface");
    details = SDL_GetPixelFormatDetails(surface->format);
    if (!details) return fail("pixel-format");
    pixel = SDL_MapRGBA(details, NULL, 0x12, 0x34, 0x56, 0x78);
    if (!SDL_FillSurfaceRect(surface, NULL, pixel))
        return fail("surface-fill");
    SDL_GetRGBA(*(Uint32 *)surface->pixels, details, NULL, &r, &g, &b, &a);
    if (r != 0x12 || g != 0x34 || b != 0x56 || a != 0x78)
        return fail("surface-readback");
    checkpoint("surface");

    SDL_zero(event);
    event.type = SDL_EVENT_USER;
    event.user.code = 0x53444c33;
    if (!SDL_PushEvent(&event)) return fail("event-push");
    do {
        SDL_zero(event);
        if (!SDL_PollEvent(&event)) return fail("event-poll");
    } while (event.type != SDL_EVENT_USER ||
             event.user.code != 0x53444c33);
    checkpoint("event");

    thread = SDL_CreateThread(worker, "vkmt-sdl3-worker", &thread_value);
    if (!thread) return fail("thread-create");
    SDL_WaitThread(thread, &thread_status);
    if (thread_value != 0x3a || thread_status != 23)
        return fail("thread-result");
    checkpoint("thread");

    kernel = SDL_LoadObject("kernel32.dll");
    if (!kernel) return fail("load-object");
    if (!SDL_LoadFunction(kernel, "GetTickCount")) return fail("load-function");
    SDL_UnloadObject(kernel);
    checkpoint("load-object");

    SDL_DestroySurface(surface);
    SDL_DestroyWindow(window);
    SDL_Quit();
    printf("VKMT_SDL3_RUNTIME_OK version=%d\n", version);
    return 0;
}
