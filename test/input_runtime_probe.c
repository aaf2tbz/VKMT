#define COBJMACROS
#define DIRECTINPUT_VERSION 0x0800
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <xinput.h>
#include <dinput.h>

typedef DWORD (WINAPI *xinput_get_state_fn)(DWORD, XINPUT_STATE *);
typedef DWORD (WINAPI *xinput_set_state_fn)(DWORD, XINPUT_VIBRATION *);
typedef DWORD (WINAPI *xinput_get_caps_fn)(DWORD, DWORD, XINPUT_CAPABILITIES *);
typedef HRESULT (WINAPI *directinput8_create_fn)(HINSTANCE, DWORD, REFIID, void **, IUnknown *);
typedef HRESULT (WINAPI *directinput_create_fn)(HINSTANCE, DWORD, LPDIRECTINPUTA *, LPUNKNOWN);

static unsigned int dinput8_gamepads, dinput8_all, dinput7_gamepads, dinput7_all;
static int xinput_connected;

static BOOL CALLBACK count_dinput8(const DIDEVICEINSTANCEA *device, void *context)
{
    unsigned int *count = context;
    ++*count;
    printf("DINPUT8_DEVICE name=\"%s\" type=%#lx\n", device->tszProductName,
           (unsigned long)device->dwDevType);
    return DIENUM_CONTINUE;
}

static BOOL CALLBACK count_dinput7(const DIDEVICEINSTANCEA *device, void *context)
{
    unsigned int *count = context;
    ++*count;
    printf("DINPUT7_DEVICE name=\"%s\" type=%#lx\n", device->tszProductName,
           (unsigned long)device->dwDevType);
    return DIENUM_CONTINUE;
}

static int good_xinput_result(DWORD result)
{
    return result == ERROR_SUCCESS || result == ERROR_DEVICE_NOT_CONNECTED;
}

static int probe_xinput_dll(const char *name)
{
    HMODULE module = LoadLibraryA(name);
    xinput_get_state_fn get_state;
    xinput_set_state_fn set_state;
    xinput_get_caps_fn get_caps;
    XINPUT_STATE state;
    XINPUT_CAPABILITIES caps;
    XINPUT_VIBRATION vibration = {0};
    DWORD result, index;
    int connected = 0;

    if (!module)
    {
        printf("FAIL LoadLibrary %s error=%lu\n", name, GetLastError());
        return 0;
    }
    get_state = (xinput_get_state_fn)GetProcAddress(module, "XInputGetState");
    set_state = (xinput_set_state_fn)GetProcAddress(module, "XInputSetState");
    get_caps = (xinput_get_caps_fn)GetProcAddress(module, "XInputGetCapabilities");
    if (!get_state || !set_state || !get_caps)
    {
        printf("FAIL exports %s state=%p set=%p caps=%p\n", name, get_state, set_state, get_caps);
        FreeLibrary(module);
        return 0;
    }

    memset(&state, 0, sizeof(state));
    result = get_state(XUSER_MAX_COUNT, &state);
    if (result != ERROR_BAD_ARGUMENTS)
    {
        printf("FAIL %s invalid-index result=%lu\n", name, result);
        FreeLibrary(module);
        return 0;
    }

    for (index = 0; index < XUSER_MAX_COUNT; ++index)
    {
        memset(&state, 0, sizeof(state));
        result = get_state(index, &state);
        if (!good_xinput_result(result))
        {
            printf("FAIL %s GetState[%lu]=%lu\n", name, index, result);
            FreeLibrary(module);
            return 0;
        }
        if (result != ERROR_SUCCESS) continue;
        connected = 1;
        xinput_connected = 1;
        memset(&caps, 0, sizeof(caps));
        result = get_caps(index, 0, &caps);
        if (result != ERROR_SUCCESS)
        {
            printf("FAIL %s GetCapabilities[%lu]=%lu\n", name, index, result);
            FreeLibrary(module);
            return 0;
        }
        result = set_state(index, &vibration);
        if (result != ERROR_SUCCESS)
        {
            printf("FAIL %s zero-vibration[%lu]=%lu\n", name, index, result);
            FreeLibrary(module);
            return 0;
        }
        printf("XINPUT_CONNECTED dll=%s index=%lu packet=%lu buttons=%#x subtype=%u\n",
               name, index, state.dwPacketNumber, state.Gamepad.wButtons, caps.SubType);
    }
    printf("XINPUT_DLL_OK %s connected=%d\n", name, connected);
    FreeLibrary(module);
    return 1;
}

static int probe_dinput8(void)
{
    HMODULE module = LoadLibraryA("dinput8.dll");
    directinput8_create_fn create;
    IDirectInput8A *dinput = NULL;
    IDirectInputDevice8A *keyboard = NULL, *mouse = NULL;
    HRESULT hr;

    if (!module || !(create = (directinput8_create_fn)GetProcAddress(module, "DirectInput8Create")))
    {
        printf("FAIL dinput8 load/export error=%lu\n", GetLastError());
        return 0;
    }
    hr = create(GetModuleHandleA(NULL), DIRECTINPUT_VERSION, &IID_IDirectInput8A,
                (void **)&dinput, NULL);
    if (FAILED(hr))
    {
        printf("FAIL DirectInput8Create hr=%#lx\n", (unsigned long)hr);
        FreeLibrary(module);
        return 0;
    }
    hr = IDirectInput8_EnumDevices(dinput, DI8DEVCLASS_ALL, count_dinput8,
                                   &dinput8_all, DIEDFL_ALLDEVICES);
    if (FAILED(hr)) goto fail;
    hr = IDirectInput8_EnumDevices(dinput, DI8DEVCLASS_GAMECTRL, count_dinput8,
                                   &dinput8_gamepads, DIEDFL_ATTACHEDONLY);
    if (FAILED(hr)) goto fail;
    hr = IDirectInput8_CreateDevice(dinput, &GUID_SysKeyboard, &keyboard, NULL);
    if (FAILED(hr)) goto fail;
    hr = IDirectInput8_CreateDevice(dinput, &GUID_SysMouse, &mouse, NULL);
    if (FAILED(hr)) goto fail;
    printf("DINPUT8_OK all=%u gamepads=%u keyboard=1 mouse=1\n",
           dinput8_all, dinput8_gamepads);
    IDirectInputDevice8_Release(mouse);
    IDirectInputDevice8_Release(keyboard);
    IDirectInput8_Release(dinput);
    FreeLibrary(module);
    return 1;
fail:
    printf("FAIL DirectInput8 hr=%#lx\n", (unsigned long)hr);
    if (mouse) IDirectInputDevice8_Release(mouse);
    if (keyboard) IDirectInputDevice8_Release(keyboard);
    IDirectInput8_Release(dinput);
    FreeLibrary(module);
    return 0;
}

static int probe_dinput7(void)
{
    HMODULE module = LoadLibraryA("dinput.dll");
    directinput_create_fn create;
    IDirectInputA *dinput = NULL;
    HRESULT hr;

    if (!module || !(create = (directinput_create_fn)GetProcAddress(module, "DirectInputCreateA")))
    {
        printf("FAIL dinput load/export error=%lu\n", GetLastError());
        return 0;
    }
    hr = create(GetModuleHandleA(NULL), 0x0700, &dinput, NULL);
    if (FAILED(hr))
    {
        printf("FAIL DirectInputCreateA hr=%#lx\n", (unsigned long)hr);
        FreeLibrary(module);
        return 0;
    }
    hr = IDirectInput_EnumDevices(dinput, 0, count_dinput7, &dinput7_all, DIEDFL_ALLDEVICES);
    if (FAILED(hr)) goto fail;
    hr = IDirectInput_EnumDevices(dinput, DIDEVTYPE_JOYSTICK, count_dinput7,
                                  &dinput7_gamepads, DIEDFL_ATTACHEDONLY);
    if (FAILED(hr)) goto fail;
    printf("DINPUT7_OK all=%u gamepads=%u\n", dinput7_all, dinput7_gamepads);
    IDirectInput_Release(dinput);
    FreeLibrary(module);
    return 1;
fail:
    printf("FAIL DirectInput7 hr=%#lx\n", (unsigned long)hr);
    IDirectInput_Release(dinput);
    FreeLibrary(module);
    return 0;
}

int main(void)
{
    static const char *xinput_dlls[] = {
        "xinput1_1.dll", "xinput1_2.dll", "xinput1_3.dll", "xinput1_4.dll",
        "xinput9_1_0.dll", "xinputuap.dll"
    };
    unsigned int i;

    for (i = 0; i < sizeof(xinput_dlls) / sizeof(xinput_dlls[0]); ++i)
        if (!probe_xinput_dll(xinput_dlls[i])) return 10 + i;
    if (!probe_dinput8()) return 30;
    if (!probe_dinput7()) return 31;
    puts("INPUT_PROVIDER_READY");
    puts(xinput_connected || dinput8_gamepads || dinput7_gamepads
         ? "INPUT_ATTACHED_CONTROLLER_BEHAVIOR_OK"
         : "INPUT_NO_CONTROLLER_ATTACHED");
    puts("INPUT_RUNTIME_ALL_OK");
    return 0;
}
