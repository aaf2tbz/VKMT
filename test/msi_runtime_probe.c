#include <windows.h>
#include <msi.h>
#include <stdio.h>
#include <string.h>

static const char product_code[] = "{D0A8B320-6D92-4CA7-A071-000000000101}";

static void marker_path(char path[MAX_PATH])
{
    GetEnvironmentVariableA("SystemDrive", path, MAX_PATH);
    strcat(path, "\\VKMT MSI Probe\\vkmt-msi-marker.txt");
}

static int verify_installed(void)
{
    char path[MAX_PATH], value[64];
    DWORD size = sizeof(value), type = 0;
    HKEY key;
    HANDLE file;
    DWORD read;
    char marker[64] = {0};

    if (MsiQueryProductStateA(product_code) != INSTALLSTATE_DEFAULT)
    {
        puts("FAIL product state is not installed");
        return 0;
    }
    marker_path(path);
    file = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (file == INVALID_HANDLE_VALUE)
    {
        printf("FAIL marker missing error=%lu path=%s\n", GetLastError(), path);
        return 0;
    }
    ReadFile(file, marker, sizeof(marker) - 1, &read, NULL);
    CloseHandle(file);
    if (!strstr(marker, "VKMT_MSI_PAYLOAD_V1"))
    {
        printf("FAIL marker content: %s\n", marker);
        return 0;
    }
    if (RegOpenKeyExA(HKEY_CURRENT_USER, "Software\\VKMT\\InstallerProbe", 0,
                      KEY_QUERY_VALUE, &key) ||
        RegQueryValueExA(key, "Version", NULL, &type, (BYTE *)value, &size))
    {
        puts("FAIL registry marker missing");
        return 0;
    }
    RegCloseKey(key);
    if (type != REG_SZ || strcmp(value, "1.0.0"))
    {
        printf("FAIL registry marker value=%s type=%lu\n", value, type);
        return 0;
    }
    return 1;
}

int main(int argc, char **argv)
{
    UINT result;

    if (argc != 3)
    {
        fprintf(stderr, "usage: msi_runtime_probe install|damage|repair|uninstall package.msi\n");
        return 2;
    }
    else if (!strcmp(argv[1], "damage"))
    {
        char path[MAX_PATH];
        HANDLE file;
        DWORD written;
        marker_path(path);
        file = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL);
        if (file == INVALID_HANDLE_VALUE) return 15;
        WriteFile(file, "DAMAGED", 7, &written, NULL);
        CloseHandle(file);
        puts("MSI_DAMAGE_OK");
        return 0;
    }
    MsiSetInternalUI(INSTALLUILEVEL_NONE, NULL);
    if (!strcmp(argv[1], "install"))
    {
        result = MsiInstallProductA(argv[2], "ACTION=INSTALL");
        if (result != ERROR_SUCCESS)
        {
            printf("FAIL install result=%u\n", result);
            return 10;
        }
        if (!verify_installed()) return 11;
        puts("MSI_INSTALL_OK");
    }
    else if (!strcmp(argv[1], "repair"))
    {
        result = MsiInstallProductA(argv[2],
                "ACTION=INSTALL REINSTALL=ALL REINSTALLMODE=amus");
        if (result != ERROR_SUCCESS)
        {
            printf("FAIL repair result=%u\n", result);
            return 20;
        }
        if (!verify_installed()) return 21;
        puts("MSI_REPAIR_OK");
    }
    else if (!strcmp(argv[1], "uninstall"))
    {
        result = MsiConfigureProductExA(product_code, 0, INSTALLSTATE_ABSENT, "REMOVE=ALL");
        if (result != ERROR_SUCCESS)
        {
            printf("FAIL uninstall result=%u\n", result);
            return 30;
        }
        if (MsiQueryProductStateA(product_code) != INSTALLSTATE_UNKNOWN &&
            MsiQueryProductStateA(product_code) != INSTALLSTATE_ABSENT)
        {
            puts("FAIL product remains installed");
            return 31;
        }
        puts("MSI_UNINSTALL_OK");
    }
    else return 3;
    return 0;
}
