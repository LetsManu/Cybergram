; Cybergram per-user installer (NSIS 3). No admin rights, no UAC prompt.
; Build (Linux or Windows):
;   makensis -DVERSION=0.9.0 -DLAUNCHER_DIR=<dir with CybergramLauncher.exe + launcher.cfg> \
;            -DGAME_DIR=<dir with the Windows game export> -DOUTFILE=CybergramSetup-0.9.0.exe cybergram.nsi
; Layout installed under %LOCALAPPDATA%\Cybergram (what the launcher expects):
;   CybergramLauncher.exe, launcher.cfg, game\Cybergram.exe ..., game\installed_version.txt
;   game\Cybergram.pck + game\packs\*.pck (content packs; heroes_hd is optional = "Lite install")
Unicode true
!include "MUI2.nsh"

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef OUTFILE
  !define OUTFILE "CybergramSetup-${VERSION}.exe"
!endif
!ifndef ICON
  !define ICON "..\cybergram.ico"
!endif

!define APP "Cybergram"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Cybergram"

Name "${APP}"
OutFile "${OUTFILE}"
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\${APP}"
InstallDirRegKey HKCU "Software\${APP}" "InstallDir"
SetCompressor /SOLID lzma
BrandingText "Cybergram ${VERSION}"

!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\CybergramLauncher.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch Cybergram"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

!ifndef VERSION_NUM
  !define VERSION_NUM "0.0.0"
!endif
VIProductVersion "${VERSION_NUM}.0"
VIAddVersionKey "ProductName" "Cybergram"
VIAddVersionKey "FileDescription" "Cybergram installer"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Cybergram"

Section "Cybergram (launcher and game)" SecMain
  SectionIn RO
  SetOutPath "$INSTDIR"
  File "${LAUNCHER_DIR}\CybergramLauncher.exe"
  ; launcher.cfg is the player's own config: keep it on re-install.
  IfFileExists "$INSTDIR\launcher.cfg" +2 0
    File "${LAUNCHER_DIR}\launcher.cfg"
  File "${ICON}"
  ; The game goes in game\ - the launcher updates it there.
  RMDir /r "$INSTDIR\game"
  SetOutPath "$INSTDIR\game"
  ; Everything except the optional HD hero textures (own section below).
  File /r /x heroes_hd.pck "${GAME_DIR}\*.*"
  ; Lite until the HD section (selected by default) runs and removes this again.
  FileOpen $0 "$INSTDIR\content.cfg" w
  FileWrite $0 '[content]$\r$\n$\r$\nskip=PackedStringArray("heroes_hd")$\r$\n'
  FileClose $0
  FileOpen $0 "$INSTDIR\game\installed_version.txt" w
  FileWrite $0 "${VERSION}$\r$\n"
  FileClose $0

  CreateDirectory "$SMPROGRAMS\${APP}"
  CreateShortcut "$SMPROGRAMS\${APP}\Cybergram.lnk" "$INSTDIR\CybergramLauncher.exe" "" "$INSTDIR\cybergram.ico"
  CreateShortcut "$SMPROGRAMS\${APP}\Uninstall Cybergram.lnk" "$INSTDIR\Uninstall.exe"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\${APP}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "Cybergram"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "Cybergram"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\cybergram.ico"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
SectionEnd

Section "HD hero textures" SecHD
  ; Untick for a Lite install: a smaller download for weaker PCs. Can be switched
  ; on later in the launcher (Settings > Content).
  SetOutPath "$INSTDIR\game\packs"
  File /nonfatal "${GAME_DIR}\packs\heroes_hd.pck"
  Delete "$INSTDIR\content.cfg"
SectionEnd

Section /o "Desktop shortcut" SecDesktop
  CreateShortcut "$DESKTOP\Cybergram.lnk" "$INSTDIR\CybergramLauncher.exe" "" "$INSTDIR\cybergram.ico"
SectionEnd

LangString DESC_Main ${LANG_ENGLISH} "The Cybergram launcher and the game (required)."
LangString DESC_Desktop ${LANG_ENGLISH} "Add a Cybergram shortcut to your desktop."
LangString DESC_HD ${LANG_ENGLISH} "Detailed hero textures. Untick for a Lite install: a smaller download for weaker PCs."
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMain} $(DESC_Main)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} $(DESC_Desktop)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecHD} $(DESC_HD)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
  ; Program files (the game folder, the launcher and its leftovers).
  Delete "$DESKTOP\Cybergram.lnk"
  RMDir /r "$SMPROGRAMS\${APP}"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKCU "${UNINST_KEY}"
  DeleteRegKey HKCU "Software\${APP}"

  ; Personal data lives outside the install folder (Godot's user:// folders).
  ; Ask in plain words; /SD IDNO keeps it on a silent uninstall.
  MessageBox MB_YESNO|MB_ICONQUESTION|MB_DEFBUTTON2 \
    "Cybergram has been removed.$\r$\n$\r$\nDo you also want to delete your saved settings and sign-in name?$\r$\nThey are stored in:$\r$\n$APPDATA\Godot\app_userdata\Cybergram$\r$\n$APPDATA\Godot\app_userdata\Cybergram Launcher$\r$\n$\r$\nYes = delete them. No = keep them for a later re-install." \
    /SD IDNO IDNO keep
    RMDir /r "$APPDATA\Godot\app_userdata\Cybergram"
    RMDir /r "$APPDATA\Godot\app_userdata\Cybergram Launcher"
  keep:
SectionEnd
