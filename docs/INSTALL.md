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
game\Cybergram.exe, game\Cybergram.pck  (the game, where the launcher expects it)
game\packs\maps.pck, heroes_hd.pck      (content packs, see "Content packs and Lite install")
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

Builds made without the signing secrets (below) are not code-signed, so Windows
shows "Windows protected your PC - Unknown publisher". Choose **More info**,
then **Run anyway**. Check the file against `SHA256SUMS.txt` first if you want
to be sure.

### Turning on code signing

CI already signs `Cybergram.exe`, `CybergramLauncher.exe` and
`CybergramSetup-*.exe` (`installer/sign_windows.sh`, osslsigncode, SHA-256,
DigiCert timestamp) as soon as two repository secrets exist. Without them the
step prints a notice and the build stays unsigned.

1. Export the code-signing certificate **with its private key** as a `.pfx`
   (`.p12`) file with a password. (Windows: certmgr, Personal, Certificates,
   right-click, All Tasks, Export, "Yes, export the private key".)
2. Base64-encode it on one line:
   - Linux/macOS: `base64 -w0 cert.pfx > cert.b64` (macOS: `base64 -i cert.pfx -o cert.b64`)
   - Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("cert.pfx")) | Set-Content cert.b64`
3. GitHub, repository **Settings, Secrets and variables, Actions, New repository secret**:
   - `WINDOWS_SIGN_PFX_B64`: the contents of `cert.b64`
   - `WINDOWS_SIGN_PASSWORD`: the `.pfx` password
4. Delete `cert.b64` afterwards. The next CI run signs the executables; the
   "Sign Windows executables" step log lists each signed file.

Notes: a certificate kept only on a hardware token (most EV certificates
since 2023) cannot be exported as a `.pfx`; it then needs a cloud signing
service or a Windows runner with the token, which is a separate change. The
NSIS uninstaller inside the installer stays unsigned. An EV certificate removes
the SmartScreen warning at once; a standard one builds reputation over time.

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

## Content packs and Lite install

The game is exported as the executable plus `Cybergram.pck` (core) and content
packs in `game/packs/`: `maps.pck` (required) and `heroes_hd.pck`, the
**HD hero textures** (optional). Language packs (`lang_<code>.pck`) are
supported but none exist yet; English is built in. The game mounts every pack
at start (`src/core/boot/content_packs.gd`); without the HD pack heroes use
their flat team colours.

**Lite install** skips the HD hero textures: a smaller download for weaker PCs.
- Windows setup: untick "HD hero textures" on the components page.
- Linux tar: `./install.sh --lite`.
- Launcher: Settings > Content > "Lite install", or the per-pack switches.
  Switching a pack off deletes its files; switching it on downloads them.
The choice is stored in `content.cfg` next to the `game` folder.

## Updates

The launcher reads the signed `version.json` (ECDSA P-256, `version.json.sig`).
Each platform lists every file with `path`, `size`, `sha256` and its pack
`group`; the files are served once each as `blobs/<sha256>`.
- **Per-file (delta) updates:** only files whose sha256 differs are fetched.
  Each one is checked against the signed list, staged in `game.stage/`, then
  renamed in; on any error every replaced file is put back (`game.undo/`).
- **Full package:** the zip is still used for a first install, for installs
  older than 0.11 (no `game/installed_manifest.json` yet) and as a fallback
  when the host has no blobs.
- **Pause / resume:** "Pause download" in the play bar. A paused or interrupted
  file continues where it stopped (HTTP Range), also after a restart.
- **Speed limit:** Settings > Storage > Download speed.
- **Repair** (Settings > Verify / Repair) re-downloads only broken files.

### Pre-loading the next patch

The feed may carry a `next` block (version, file list, `activate_at` in ISO UTC).
The launcher downloads it in the background into `preload/`, shows
"Pre-loaded 0.x.y, ready at <local time>", and switches to it on the first
launch or check at or after that time, even offline. To publish one, build the
feed with:

```
NEXT_VERSION=v0.12.0 NEXT_WIN_DIR=<win build> NEXT_LIN_DIR=<linux build> \
NEXT_ACTIVATE_AT=2026-11-01T18:00:00Z launcher/tools/make_update_feed.sh <current args>
```

## Install management (launcher Settings)

- **Install folder:** "Install folder..." moves the game, its content choice and
  any pre-load to another folder or drive.
- **Storage:** space the game uses and the free space on that drive.
- **Uninstall game:** removes the game and its downloads. Choose whether to keep
  your settings. The launcher stays. To remove it too, use Windows Settings >
  Apps, `uninstall.sh` (Linux tar), or delete the AppImage file.

## AppImage self-update

The AppImage embeds the update information
`gh-releases-zsync|LetsManu|Cybergram|latest|Cybergram-*-x86_64.AppImage.zsync`,
and each release publishes the matching `.zsync`, so AppImageUpdate works.
The launcher also updates itself: when the signed feed lists a newer launcher
with an `appimage` entry (URL and sha256), it downloads the AppImage, checks the
sha256, writes `<name>.new`, makes it executable, renames it over `$APPIMAGE`
and restarts.
