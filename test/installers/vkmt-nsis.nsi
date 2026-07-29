Unicode true
!ifndef VKMT_NSIS_PAYLOAD
  !error "VKMT_NSIS_PAYLOAD must name the built i386 payload"
!endif
!ifndef VKMT_NSIS_OUTFILE
  !error "VKMT_NSIS_OUTFILE must name the generated installer"
!endif
Name "VKMT NSIS Runtime Probe"
OutFile "${VKMT_NSIS_OUTFILE}"
InstallDir "$LOCALAPPDATA\VKMTNSISProbe"
RequestExecutionLevel user
SilentInstall silent
SilentUnInstall silent

Section "Install"
  SetOutPath "$INSTDIR"
  File "/oname=vkmt-nsis-payload.exe" "${VKMT_NSIS_PAYLOAD}"
  FileOpen $0 "$INSTDIR\installed.txt" w
  FileWrite $0 "VKMT_NSIS_INSTALLED$\r$\n"
  FileClose $0
  WriteRegStr HKCU "Software\VKMT\NSISProbe" "InstallDir" "$INSTDIR"
  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\vkmt-nsis-payload.exe"
  Delete "$INSTDIR\installed.txt"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "Software\VKMT\NSISProbe"
SectionEnd
