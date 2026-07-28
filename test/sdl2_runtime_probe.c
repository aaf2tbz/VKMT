#define SDL_MAIN_HANDLED
#include <SDL.h>
#include <stdio.h>
#include <string.h>

static int SDLCALL worker(void *opaque)
{
    int *value = opaque;
    *value = 0x2a;
    return 17;
}

static int fail(const char *gate)
{
    fprintf(stderr, "SDL2_FAIL gate=%s error=%s\n", gate, SDL_GetError());
    SDL_Quit();
    return 1;
}

static void checkpoint(const char *gate)
{
    fprintf(stderr, "SDL2_GATE %s\n", gate);
    fflush(stderr);
}

int main(void)
{
    SDL_version version;
    SDL_Window *window;
    SDL_Surface *surface;
    SDL_Thread *thread;
    SDL_Event event;
    void *kernel;
    int thread_value = 0, thread_status = 0;
    int enum_bpp = 0;
    Uint32 enum_r = 0, enum_g = 0, enum_b = 0, enum_a = 0;
    Uint8 r = 0, g = 0, b = 0, a = 0;
    Uint32 pixel;

    SDL_SetMainReady();
    checkpoint("start");
    SDL_GetVersion(&version);
    if (version.major != 2 || version.minor != 32 || version.patch != 10)
        return fail("version");

    SDL_SetHint(SDL_HINT_VIDEODRIVER, "dummy");
    SDL_SetHint(SDL_HINT_AUDIODRIVER, "dummy");
    if (SDL_Init(SDL_INIT_TIMER | SDL_INIT_EVENTS | SDL_INIT_VIDEO |
                 SDL_INIT_AUDIO) != 0)
        return fail("init");
    checkpoint("init");
    if (!SDL_PixelFormatEnumToMasks(SDL_PIXELFORMAT_RGBA32, &enum_bpp,
                                    &enum_r, &enum_g, &enum_b, &enum_a) ||
        enum_bpp != 32 || !enum_r || !enum_g || !enum_b || !enum_a) {
        fprintf(stderr,
                "SDL2_ENUM_MISMATCH bpp=%d masks=%08x/%08x/%08x/%08x\n",
                enum_bpp, (unsigned)enum_r, (unsigned)enum_g,
                (unsigned)enum_b, (unsigned)enum_a);
        return fail("pixel-enum");
    }
    checkpoint("pixel-enum");

    window = SDL_CreateWindow("VKMT SDL2 probe", SDL_WINDOWPOS_UNDEFINED,
                              SDL_WINDOWPOS_UNDEFINED, 32, 32,
                              SDL_WINDOW_HIDDEN);
    if (!window) return fail("window");
    checkpoint("window");

    surface = SDL_CreateRGBSurfaceWithFormat(0, 4, 4, 32,
                                             SDL_PIXELFORMAT_RGBA32);
    if (!surface) return fail("surface");
    if (!surface->format)
        return fail("surface-format-pointer");
    pixel = SDL_MapRGBA(surface->format, 0x12, 0x34, 0x56, 0x78);
    if (SDL_FillRect(surface, NULL, pixel) != 0) return fail("surface-fill");
    SDL_GetRGBA(*(Uint32 *)surface->pixels, surface->format, &r, &g, &b, &a);
    if (r != 0x12 || g != 0x34 || b != 0x56 || a != 0x78)
    {
        fprintf(stderr,
                "SDL2_PIXEL_MISMATCH request=%08x surface=%08x bpp=%u losses=%u/%u/%u/%u shifts=%u/%u/%u/%u masks=%08x/%08x/%08x/%08x palette=%p mapped=%08x actual=%08x rgba=%02x%02x%02x%02x\n",
                (unsigned)SDL_PIXELFORMAT_RGBA32,
                (unsigned)surface->format->format,
                (unsigned)surface->format->BitsPerPixel,
                surface->format->Rloss, surface->format->Gloss,
                surface->format->Bloss, surface->format->Aloss,
                surface->format->Rshift, surface->format->Gshift,
                surface->format->Bshift, surface->format->Ashift,
                (unsigned)surface->format->Rmask,
                (unsigned)surface->format->Gmask,
                (unsigned)surface->format->Bmask,
                (unsigned)surface->format->Amask,
                (void *)surface->format->palette,
                (unsigned)pixel, (unsigned)*(Uint32 *)surface->pixels,
                r, g, b, a);
        return fail("surface-readback");
    }
    checkpoint("surface");

    SDL_zero(event);
    event.type = SDL_USEREVENT;
    event.user.code = 0x53444c32;
    if (SDL_PushEvent(&event) != 1) return fail("event-push");
    do {
        SDL_zero(event);
        if (SDL_PollEvent(&event) != 1) return fail("event-poll");
    } while (event.type != SDL_USEREVENT ||
             event.user.code != 0x53444c32);
    checkpoint("event");

    thread = SDL_CreateThread(worker, "vkmt-sdl2-worker", &thread_value);
    if (!thread) return fail("thread-create");
    SDL_WaitThread(thread, &thread_status);
    if (thread_value != 0x2a || thread_status != 17)
        return fail("thread-result");
    checkpoint("thread");

    kernel = SDL_LoadObject("kernel32.dll");
    if (!kernel) return fail("load-object");
    if (!SDL_LoadFunction(kernel, "GetTickCount")) return fail("load-function");
    SDL_UnloadObject(kernel);
    checkpoint("load-object");

    SDL_FreeSurface(surface);
    checkpoint("free-surface");
    SDL_DestroyWindow(window);
    checkpoint("destroy-window");
    SDL_QuitSubSystem(SDL_INIT_AUDIO);
    checkpoint("quit-audio");
    SDL_QuitSubSystem(SDL_INIT_VIDEO);
    checkpoint("quit-video");
    SDL_QuitSubSystem(SDL_INIT_EVENTS);
    checkpoint("quit-events");
    SDL_QuitSubSystem(SDL_INIT_TIMER);
    checkpoint("quit-timer");
    SDL_Quit();
    checkpoint("quit");
    printf("VKMT_SDL2_RUNTIME_OK version=%u.%u.%u\n",
           version.major, version.minor, version.patch);
    return 0;
}
