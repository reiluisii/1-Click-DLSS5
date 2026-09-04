# Fork notes: English-default build of 1 Click DLSS 5

Branch: `english-default`, based on upstream `reiluisii/1-Click-DLSS5` at commit `48135cf`
(tag `v2.6.0`, the v2.6.0-release package). Prepared 2026-09-04.

## Why this fork exists

I ran the v2.6.0 release and hit problems with the Portuguese-to-English translation: the app
opened in Portuguese, switching the dropdown to English left a lot of the interface untranslated
(status bar, dialogs, error messages, log lines), and several labels and buttons showed empty
brackets, stray spaces, or clipped text. Rather than keep flipping the language switch and
guessing at what the Portuguese meant, I had the script translated properly so it runs in English
natively, fixed the rendering problems that were causing the broken labels, and had the whole
package checked for safety before using it. This branch is that solution.

This document has three parts: what was changed and why, how to publish and maintain the fork,
and the full security review of the v2.6.0 package (including how to re-run the checks yourself).

---

## 1. What changed

Only three source files were modified. No payload binary was touched, added, or removed.

| File | Change |
|---|---|
| `core/1-Click-DLSS5.ps1` | English is the default language; ~120 hard-coded Portuguese strings translated; GUI layout fixes (see below) |
| `core/assets/translations.json` | Emoji removed from every language; English entries cleaned up; `EN` moved to the top |
| `src/Launcher.cs` | The three error dialogs the launcher can show are now English (source only, see 1.4) |

New files: `docs/FORK-NOTES.md` (this file), `tools/Verify-Payload.ps1`, `tools/payload-manifest.json`.

### 1.1 Language

* `$script:CurrentLang` default changed from `"PT"` to `"EN"`.
* `Get-Dict` falls back to the `EN` dictionary (was `PT`) when a language is missing, and its
  built-in fallback table (used if `translations.json` is missing) is now English and mirrors the JSON.
* The language dropdown lists English first; the `$langCodes` array was reordered to match.
* Every string that lived outside the translation dictionary was translated in place: main-window
  labels and buttons, the status bar, the install progress steps, the success dialog, the
  diagnostics dialog, the error/auto-fix dialog (`Get-ErrorDiagnosis`), `MessageBox` prompts,
  folder-browser text, and every `Write-Status` log line. Log-field tags `[CAUSA:]`/`[SOLUCAO:]`
  became `[CAUSE:]`/`[FIX:]`.
* Three regex matches that keyed off Portuguese text were updated so behaviour is unchanged:
  `'DIRECT|Modo 1'` → `'DIRECT|Mode 1'`, `'OPTISCALER|Modo 2'` → `'OPTISCALER|Mode 2'`, and the
  error-classifier patterns (`'Nenhum executavel'`, `'Acesso negado'`, `'nao existe'`,
  `'sendo usado por outro processo'`) now match the new English messages.
* Portuguese and the other eight languages still work from the dropdown; nothing was removed.
* Section comments were translated to English. Inline comments inside function bodies were left
  as they were to keep the diff reviewable.

### 1.2 GUI fixes

These address the two problems observed on first launch: mixed-language text, and clipped or
overlapping text.

* **Encoding damage repaired.** At some point the upstream file was saved through a lossy
  encoding: every accented character and every emoji became a plain space. That produced labels
  like `[ ] INICIAR JOGO` (empty brackets where `⚡` used to be), `DIRET RIO DE INSTALA  O`,
  and missing arrows between the three steps. All affected strings were rewritten with plain
  ASCII markers: `[1-CLICK] INSTALL DLSS 5`, `[>] LAUNCH GAME`, `[<] RESTORE FACTORY`,
  `[FOLDER] OPEN FOLDER`, `[+] SYSTEM DIAGNOSIS`, `[TIP]`, and `→` between steps.
* **Emoji removed from `translations.json`.** The dictionary used colour emoji (`🩺 📁 🟢 🔵 🟣 1️⃣ ▶️ ↩️ ✨ ✅ ⏳`).
  WinForms draws text with GDI, which renders these as boxes, half-glyphs or mismatched widths,
  and they overflowed the fixed-width buttons. They were stripped from all ten languages
  (keycap digits became `[1] [2] [3]`). The three mode cards are already colour-coded by
  `ForeColor`, so no information is lost.
* **DPI scaling.** The script enables Per-Monitor-V2 DPI awareness but never set
  `AutoScaleMode`, so at 125 % / 150 % Windows display scaling the fonts grew while the control
  rectangles stayed at 96-DPI pixel sizes, clipping text. Added
  `$form.AutoScaleDimensions = 96,96` and `$form.AutoScaleMode = Dpi` before the controls are built.
* **Sizing for English captions.** The diagnosis button was widened from 160 px to 190 px and
  moved left to fit `[+] SYSTEM DIAGNOSIS`; the "optimal mode" notice was shortened to
  `Optimal mode auto-selected for this game` so it fits its 318 px right-aligned label; `ReqMode3`
  was tightened so it wraps inside its two-line label.
* **Single source of truth at startup.** `Update-UiLanguage` is now called once after all
  functions are defined (just before the window opens), so every control is populated from the
  dictionary rather than from its hard-coded initial `.Text`. `Update-UiLanguage` also now updates
  `$lblReqText` and `$lblGameStatus`, which previously kept their startup text after a language switch.

### 1.3 Behaviour that did NOT change

Install/uninstall logic, file lists, backup handling, registry reads, game detection, INI
generation, and the payload folder are byte-for-byte identical to upstream. The only functional
line changes are the four regex updates listed in 1.1, each verified to match the new text.

### 1.4 The launcher `.exe`

`1-Click-DLSS5.exe` is a 38 KB .NET wrapper that runs
`powershell -NoProfile -ExecutionPolicy Bypass -STA -File core\1-Click-DLSS5.ps1`. Its three
error dialogs were Portuguese; `src/Launcher.cs` is translated in this branch but the binary was
**not rebuilt**, so those three messages (file-not-found, startup error, critical failure) still
appear in Portuguese if they ever fire. Normal operation never shows them. To rebuild on Windows:

```
"%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /target:winexe /platform:x64 /optimize+ ^
  /win32icon:core\assets\logo.ico /out:1-Click-DLSS5.exe src\Launcher.cs
```

### 1.5 Verification performed

* `[System.Management.Automation.Language.Parser]::ParseFile` on PowerShell 7.4.6: 0 errors
  (the upstream file also parses with 0 errors, so nothing regressed).
* `Get-Dict` executed in isolation: JSON `EN` loads, unknown language falls back to English,
  `PT` still returns Portuguese, and the built-in fallback table returns all 58 keys.
* `translations.json` re-parsed; all 10 languages keep all 58 keys.
* A word-list scan for Portuguese in code lines (excluding comments) returns no hits other than
  the `Jogos` folder name in the drive scanner, which is intentionally kept.
* Files are saved UTF-8 with BOM, as `CONTRIBUTING.md` asks; line endings follow the repo (LF).
* Not verified: a live run of the WinForms GUI (no Windows machine was available). Please open it
  once at your normal display scaling and report anything still clipped.

---

## 2. Publishing and maintaining the fork

### 2.1 Publish

1. On GitHub, fork `reiluisii/1-Click-DLSS5`.
2. Clone your fork and add the review branch from the bundle shipped with these notes:
   ```
   git clone https://github.com/<you>/1-Click-DLSS5.git
   cd 1-Click-DLSS5
   git fetch ..\english-default.bundle english-default:english-default
   git push -u origin english-default
   ```
   Or, without the bundle, apply the patch series: `git am ..\patches\*.patch`.
3. Optionally make it the default branch in the fork's settings, or open a pull request upstream.

### 2.2 Keep it current

Upstream releases often. To rebase the English changes onto a newer upstream:

```
git remote add upstream https://github.com/reiluisii/1-Click-DLSS5.git
git fetch upstream
git rebase upstream/main english-default
```

The commits are small and touch only three files, so conflicts will be limited to strings the
author changed. After any rebase, re-run the two checks in 1.5 (`ParseFile` and the JSON reload)
and run `tools\Verify-Payload.ps1` if the payload folder changed. Any new payload binary must be
re-reviewed before you trust it, and its hash added to `tools\payload-manifest.json`.

### 2.3 Release packaging

The upstream release zip converts files to CRLF and keeps the UTF-8 BOM. If you ship a zip,
either commit with `core.autocrlf=true` on Windows or run `unix2dos` on `*.ps1`/`*.json`;
Windows PowerShell 5.1 reads both fine, so this is cosmetic.

---

## 3. Security review of `1-Click-DLSS5-v2.6.0-release.zip` (2026-09-04)

Scope: static analysis of every file in the release zip (67 files, 479 MB). Method: string and
import inspection of the launcher, a full read of the PowerShell script, PE header / import table /
export analysis of every DLL and EXE with `pefile`, Authenticode signature parsing and digest
verification with `osslsigncode`, and byte-level comparison of duplicated binaries.
No file was executed.

**Summary: no malware was found. The tool does exactly what it says. The risks are in what it
says it does, not in hidden behaviour.**

### 3.1 Launcher (`1-Click-DLSS5.exe`)

38 KB .NET assembly. Contains one code path: locate `core\1-Click-DLSS5.ps1`, prefer
`pwsh.exe` if PowerShell 7 is installed, else `powershell.exe`, and run it with
`-ExecutionPolicy Bypass -STA`. No network, no other process launches. Matches `src/Launcher.cs`.

### 3.2 PowerShell script (`core/1-Click-DLSS5.ps1`, 2,921 lines)

Searched for and found **none** of: `Invoke-WebRequest`, `Invoke-RestMethod`, `WebClient`,
`DownloadString/File`, `Invoke-Expression`, `-EncodedCommand`, `FromBase64String`, sockets,
`schtasks`/`Register-ScheduledTask`, `Run`/`RunOnce` registry keys, `Set-/New-ItemProperty`,
`Add-MpPreference`, `certutil`, `bitsadmin`, `mshta`, `rundll32`, `wscript`, writes to
`%APPDATA%`/`%TEMP%` (other than ReShade's own shader cache path written into an INI), or any
obfuscation. Two small inline C# blocks exist and only call `SetProcessDpiAwarenessContext` and
`SetWindowTheme`.

What it **does** do, all within the selected game folder unless noted:

* Reads (never writes) registry keys for Steam and GOG install paths; parses Steam
  `libraryfolders.vdf` and Epic manifests; scans fixed drives for common game folders.
* Copies files from `core\payload` into the game folder; writes `ReShade.ini`,
  `ReShadePreset.ini`, `OptiScaler.ini`, `dlss5-feed.cfg`, and a `_dlss5_install_state.json`.
* Backs up any file it overwrites to `_DLSS5_Backup` inside the game folder and restores from
  it on uninstall or mode change.
* Auto-Fix: `Stop-Process -Force` on the selected game's process, `attrib -r` on the game folder,
  then reinstalls. This is the most aggressive thing it does and it only targets the chosen game.
* Uninstall uses an explicit allow-list of files it may delete and a deny-list protecting
  vendor runtimes (`nvngx_dlss*.dll` except `dlssnr`, `sl.*.dll` except `sl.dlss_nr`,
  `libxess*.dll`, `ffx_*`, `bink2*`, `steam_api*`, `d3d12core.dll`, and so on).
* Writes a log to `core\1-Click-DLSS5.log` containing OS, CPU and GPU names. It stays local;
  nothing is transmitted.

### 3.3 Payload binaries

| File | Size | Signed by | Digest | Notes |
|---|---|---|---|---|
| `nvngx_dlss.dll` | 58.9 MB | NVIDIA Corporation | matches | Standard DLSS 310.x; also present, identical, inside `streamline.zip` |
| `sl.dlss_nr.dll` | 401 KB | NVIDIA Corporation | matches | Streamline DLSS-NR plugin, linked 2026-08-12 |
| `streamline.zip` → `sl.*.dll`, `nvngx_dlssg.dll` | – | NVIDIA Corporation | all match | Streamline 2.13 set: interposer, common, dlss, dlss_g, nis, pcl, reflex |
| `optiscaler/OptiScaler.dll` | 25.4 MB | SignPath Foundation | matches | Signature URL field: `https://github.com/optiscaler/OptiScaler.git`. Imports `winhttp.dll` (OptiScaler's own update check) |
| `optiscaler/libxess.dll` | 77.8 MB | Intel Corporation | matches | Intel XeSS runtime, Oct 2025 |
| `ReShade_Setup_6.8.0_Addon.exe` | 4.3 MB | ReShade (self-signed, as ReShade always is) | matches | Official add-on installer |
| `dxgi.dll` / `dxgi32.dll` | 5.6 / 4.4 MB | unsigned | – | ReShade 6.8.0 runtime, 500 exports, linked minutes before the installer above. Imports `wininet.dll` (ReShade's effect/update downloader). Consistent with ReShade; not independently verifiable |
| `renodx-dlss5.addon64` | 1.7 MB | unsigned | – | ReShade add-on (2 exports). Imports only kernel32/user32/bcrypt; `GetAsyncKeyState` is used for the F5/F6 hotkeys. Socket-error strings are the MSVC runtime's standard `std::system_category` table, not networking code |
| `feeder/dlss5-feed.addon64` / `.addon32` | 224 / 142 KB | unsigned | – | ReShade add-ons; strings are entirely D3D/Vulkan copy/blit calls and a named pipe `\\.\pipe\dlss5-feed.<pid>` |
| `feeder/host64/dlss5-feed-host64.exe` | 107 KB | unsigned | – | 64-bit helper for 32-bit games; `ConnectNamedPipe` to the pipe above, shared GPU textures. No network imports |
| `feeder/layer-x64|x86/VkLayer_feed_vk*.dll` | 19 / 16 KB | unsigned | – | Minimal Vulkan layers (3 exports), imports kernel32 + CRT only |
| **`nvngx_dlssnr.dll`** | **165.8 MB** | **NVIDIA (stripped)** | **cannot verify** | See 3.4 |

The exact SHA-256 of every file above is recorded in `tools/payload-manifest.json`.

### 3.4 The DLSS-NR model: `nvngx_dlssnr.dll`

This is the file the whole tool exists to install, and it is the one you should think about.

* Version resource: `NVIDIA DLSSNR - DVS PRODUCTION`, FileVersion `310.8.SF.0`, OriginalFilename
  `CL 38718415`, `NGXGpuArchitecture = NVSDK_NGX_GPU_Arch_Blackwell2`, `NGXMinimumDriverVersion = 615.00`,
  linked 2026-08-11.
* DLSS 5 has not been released by NVIDIA. A DLL of this name and size surfaced in an NBA 2K27
  early-access build in late August 2026 (see sources). This is that leaked build, or a
  derivative of it.
* The PE security directory points 10,352 bytes **past the end of the file** and the PE checksum
  is wrong: the NVIDIA Authenticode signature was cut off. The "SF" in the version string and the
  upstream release notes ("patched nvngx_dlssnr.dll ... via ShortFuse") say it was modified to
  run on RTX 20/30/40 cards rather than only Blackwell.
* `streamline.zip` contains a second copy (same link timestamp, FileVersion `310,8,0,0`) that
  still carries a signature block, but the signed digest does **not** match the file: also
  patched. The two copies differ across ~147 MB of the ~166 MB file, so at least one has had its
  embedded model data re-encoded, not just a few bytes flipped.
* Consequences: (a) nobody outside the modding group can say what is in those 166 MB;
  (b) it is leaked, unreleased NVIDIA IP, so distributing it is a legal exposure for whoever
  hosts the fork; (c) it declares a minimum driver (615) that does not yet exist, so it may
  simply fail to load on current drivers regardless of the patch.

### 3.5 Risks that are by design

* **Anti-cheat.** All three modes work by DLL proxying (`dxgi.dll`, `version.dll`) inside the
  game process. Easy Anti-Cheat, BattlEye and Vanguard treat that as tampering. Use only in
  single-player titles. The upstream README advertises "bypassing" EAC wrappers; do not rely on that.
* **Process kill and attribute changes.** Auto-Fix force-terminates the game process and clears
  read-only flags across the whole game folder. Harmless, but be aware it does it without a
  second confirmation.
* **Provenance and hygiene.** The README is marketing copy, the payload manifest inside the zip
  still says v2.5.3, and upstream had not yet published the v2.6.0 assets on the Releases page at
  review time. None of this is malicious; it is a signal to re-check every new release rather than
  trust it.

### 3.6 Re-running the checks yourself

On Windows, from the repository root:

```
powershell -ExecutionPolicy Bypass -File tools\Verify-Payload.ps1
```

It recomputes SHA-256 for all 16 binaries, checks each Authenticode signer with
`Get-AuthenticodeSignature`, and compares against `tools\payload-manifest.json`. A clean run
means you hold the same bytes that were reviewed. It does not, and cannot, make `nvngx_dlssnr.dll`
trustworthy; it only tells you it has not changed since the review.

Other checks that are worth repeating on a new release:

```powershell
# no network / persistence primitives in the script
Select-String -Path core\1-Click-DLSS5.ps1 -Pattern 'Invoke-WebRequest|Invoke-RestMethod|WebClient|DownloadString|Invoke-Expression|EncodedCommand|FromBase64|schtasks|ScheduledTask|CurrentVersion\\Run|Set-ItemProperty|New-ItemProperty'

# script still parses
$e=$null;$t=$null;[System.Management.Automation.Language.Parser]::ParseFile("$PWD\core\1-Click-DLSS5.ps1",[ref]$t,[ref]$e);$e.Count
```

Sources consulted during the review:
[TechPowerUp, DLSS 5 Neural Rendering DLL leak](https://www.techpowerup.com/352026/nvidia-dlss-5-neural-rendering-dll-leak-hints-at-nearby-launch);
[VideoCardz, DLSS 5 DLL found in NBA 2K27](https://videocardz.com/newz/nvidia-dlss-5-neural-rendering-dll-found-in-nba-2k27-early-access-build-file-is-3x-larger-than-dlss-4);
[upstream repository](https://github.com/reiluisii/1-Click-DLSS5) and its
[release notes](https://github.com/reiluisii/1-Click-DLSS5/releases).
