# Installing Cybergram

Every release has one installer per platform. It contains the launcher and the
game; the launcher is what you start, and it keeps the game and itself up to date.

| Platform | Main download | Notes |
|---|---|---|
| Windows 10/11 | `CybergramSetup-<version>.exe` | Per-user install, no admin rights, no UAC prompt |
| Linux (AppImage) | `Cybergram-<version>-x86_64.AppImage` | `chmod +x` it, then run it |
| Linux (installer) | `CybergramInstaller-<version>-linux-x86_64.tar.gz` | Extract, run `./install.sh` |

**Portable builds** (advanced users, no install, no menu entries): the
`Cybergram-<version>-windows-x86_64.zip` / `-linux-x86_64.tar.gz` game builds
and the bare `CybergramLauncher-windows.zip` / `-linux.tar.gz`. All files and
their SHA-256 checksums are in `SHA256SUMS.txt` on the release page.

## Windows

Run the setup. It installs to `%LOCALAPPDATA%\Cybergram`:

```
CybergramLauncher.exe, launcher.cfg      (launcher, at the root)
game\Cybergram.exe ...                   (the game, where the launcher expects it)
Uninstall.exe
```

You get a Start menu entry, an optional desktop shortcut (a checkbox on the
components page) and a "Launch Cybergram" checkbox on the last page. The
uninstaller is listed under Settings > Apps (per user).

**Uninstall** removes the program files and shortcuts. It then asks in plain
words whether to also delete your saved settings and sign-in name, which are
kept outside the install folder in `%APPDATA%\Godot\app_userdata\Cybergram` and
`...\Cybergram Launcher`. Yes deletes them, No keeps them. A silent uninstall
(`/S`) keeps them. If you moved the game to another folder with the launcher,
delete that folder yourself.

### Unsigned installer warning (SmartScreen)

The installer is not code-signed yet, so Windows shows "Windows protected your
PC - Unknown publisher". Choose **More info**, then **Run anyway**. Check the
file against `SHA256SUMS.txt` first if you want to be sure.

### Adding signing later

1. Buy or obtain a code-signing certificate (an EV certificate removes the
   SmartScreen warning at once; a standard one builds reputation over time).
2. Store it as GitHub secrets, for example `WINDOWS_CERT_PFX_BASE64` and
   `WINDOWS_CERT_PASSWORD`.
3. In `.github/workflows/build.yml`, after "Build installers", sign on the
   Ubuntu runner with `osslsigncode` (`apt install osslsigncode`):
   `osslsigncode sign -pkcs12 cert.pfx -pass "$PW" -n Cybergram -t http://timestamp.digicert.com -in X.exe -out X.signed.exe`
   Sign `CybergramLauncher.exe` and the game exe before packaging, and the
   `CybergramSetup-*.exe` after. (On a Windows runner use `signtool sign /fd sha256 /tr <timestamp-url> /td sha256`.)
4. Delete the temporary .pfx afterwards. Nothing is signed or bought today.

## Linux

**AppImage.** An AppImage is read-only, so on first run the launcher copies the
bundled game to `~/.local/share/cybergram` (or `$XDG_DATA_HOME/cybergram`) and
updates it there. Game updates work as normal. The launcher itself cannot
replace the AppImage: when a newer launcher exists it shows a notice, and you
download the new AppImage from the Releases page.

**Installer.** `./install.sh` installs to `~/.local/share/cybergram`, adds a
menu entry (`~/.local/share/applications/cybergram.desktop`) and an icon, no
root needed. The launcher can update itself there.
`~/.local/share/cybergram/uninstall.sh` removes everything and asks whether to
also delete your settings (`~/.local/share/godot/app_userdata/Cybergram*`);
use `--remove-settings` or `--keep-settings` to skip the question.

## Building the installers locally

Needs `makensis` (apt `nsis`), `curl`, `zip`, `jq`. With the four exports in
`build/` (see `.github/workflows/build.yml`):

```
installer/build_windows.sh   <ver> build/launcher-windows build/windows build/installers
installer/build_linux_tar.sh <ver> build/launcher-linux   build/linux   build/installers
installer/build_appimage.sh  <ver> build/launcher-linux   build/linux   build/installers
installer/smoke_linux_tar.sh build/installers/CybergramInstaller-<ver>-linux-x86_64.tar.gz
installer/smoke_appimage.sh  build/installers/Cybergram-<ver>-x86_64.AppImage <ver>
```

appimagetool 1.9.1 is downloaded by `installer/fetch_appimagetool.sh`, pinned by URL and SHA-256.
