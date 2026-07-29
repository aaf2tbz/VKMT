[Setup]
AppId={{1E55AA3A-9BC4-4D6B-9EA0-9A2A1E22C501}
AppName=VKMT Inno Probe
AppVersion=1.0.0
DefaultDirName={autopf}\VKMT Inno Probe
DefaultGroupName=VKMT Inno Probe
OutputBaseFilename=vkmt-inno-probe
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
Uninstallable=yes
ArchitecturesAllowed=x86compatible

[Files]
Source: "vkmt-inno-marker.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\VKMT Inno Probe"; Filename: "{app}\vkmt-inno-marker.txt"
