# Changelog — 1 Click DLSS 5

All notable changes, architectural overhauls, and bug fixes for the **1 Click DLSS 5** project are documented in this file.

## [v3.0.1-fix] - 2026-09-05

### 🚑 Emergency Startup Fix (Windows PowerShell 5.1 & Encoding)
- **Resolved First-Launch Crash on Windows 10/11:** Fixed a critical issue where the absence of a UTF-8 Byte Order Mark (BOM) in `.ps1` files caused Windows PowerShell 5.1 (the default built-in PowerShell on Windows) to parse localized Unicode strings as ANSI, resulting in cascading syntax and unexpected token errors upon launching `1-Click-DLSS5.exe`.
- **Enforced Single UTF-8 BOM:** Normalized and sanitized all PowerShell scripts (`core/1-Click-DLSS5.ps1`, `core/engine/*.ps1`, `tools/*.ps1`) with an explicit UTF-8 BOM, guaranteeing flawless parsing across all Windows locales (English, Russian, Portuguese, German, French, Chinese, Japanese, etc.).
- **Enhanced Launcher Detection:** Updated `1-Click-DLSS5.exe` with multi-path detection for modern PowerShell 7 (`pwsh.exe`) alongside built-in Windows PowerShell 5.1, plus UTF-8 error stream decoding.

## [v3.0.0] - 2026-09-05

### 🚀 Major Architectural Refactoring & Stability Overhaul
- **Complete Modular Architecture:** Refactored internal subsystems into a dedicated modular engine (`core/engine/`), improving code maintainability, execution speed, and transactional reliability.
- **Comprehensive Bug Fixes:** Fixed multiple issues across game auto-discovery, API detection heuristics, multi-architecture library injection, and shader compilation.
- **Enhanced Transactional Journal & Rollback:** Upgraded write-ahead transaction manifest (`_DLSS5_Backup\manifest.json`) guaranteeing 100% byte-exact factory uninstallation and preservation of original game files.
- **Forensic Telemetry & Logging:** Centralized comprehensive session logging at `\1-Click-DLSS5\core\1-Click-DLSS5.log` recording hardware parameters, GPU scheduling (HAGS), detection telemetry, and deployment trace for rapid issue diagnostics.

## [v2.7.0-beta] - 2026-09-04

### 🎯 Mode 1 (DIRECT DLSS) Absolute Zero-Overhead Architecture & DLSS-NR Fix
- **Zero-Shader Compilation & Active Purge:**
  - Fixed an issue where shader collections were copied into Mode 1, causing swapchain descriptor thrashing in Direct3D 12 and severely degrading game framerates.
  - Mode 1 now actively removes any residual `reshade-shaders/` folder and `ReShadePreset.ini` from the game directory.
  - Set `PerformanceMode=1`, `NoReloadOnInit=1`, and empty `EffectSearchPaths` in `ReShade.ini` to guarantee zero shader execution and 100% native FPS.
  - Hardcoded `EnableHooks=1` so RenoDX hooks the D3D12/Streamline pipeline properly to capture frame guides.
- **Streamline DLSS-NR Plugin Preservation:**
  - Restored automatic copying of official NVIDIA-signed `sl.dlss_nr.dll` (v2.13.0.0) for titles using NVIDIA Streamline (*Forza Horizon 5/6*, *Cyberpunk 2077*).
  - Fixed pre-launch bug in `Start-GameExecutable` that was deleting `sl.dlss_nr.dll` immediately before launching Streamline titles.

### 🌐 Merged Community Pull Requests (PRs #14, #15, #16, #17, #18, #20)
- **High-DPI Display Scaling Engine (PR #14):**
  - Added `DLSS5DpiQuery` P/Invoke to `GetDpiForSystem`, `Scale-ControlTree`, and `Apply-DpiScaling` dynamically scaling all WinForms windows, dialogs (Success, Error, System Diagnosis), and ListView columns by real monitor DPI (125%, 150%, 200%), eliminating small rendering and text overlaps on 4K displays.
- **True PE Import Table Reader & Stub Filtering (PR #15):**
  - Integrated `[DLSS5PeImports]::GetImportedDlls` reading PE32/PE32+ headers instead of scanning 4MB byte chunks.
  - Filtered out installer, support, redistributable, and backup directories, and ignored small launcher stubs (<1MB) when real binaries (>=5MB) exist (resolves false launcher detection in *GTA IV*).
  - Priority detection using executable name suffixes (`_DX12`, `x64vk`, `_dx11`).
- **Payload Identity Verification Engine (PR #16):**
  - Added `Test-PayloadIdenticalFile` comparing file size and SHA-256 against bundled payload.
  - Prevents our own injected `nvngx_dlss.dll` from triggering a false `NATIVE_DLSS` classification in subsequent scans.
  - Allows `Uninstall-Dlss5` to safely remove injected `nvngx_dlss.dll` while strictly preserving native game files.
- **Single ReShade Proxy & Headless Vulkan Implicit Layer (PR #17):**
  - Fixed dual proxy collision in OpenGL/D3D9 titles where loading both `dxgi.dll` and `opengl32.dll` crashed the private D3D12 feeder device (`DXGI_ERROR_UNSUPPORTED`). Now installs strictly one proxy per API.
  - Added headless Vulkan implicit layer registration via `ReShade_Setup_6.8.0_Addon.exe` and `ReShadeApps.ini` management for native Vulkan games (*DOOM*).
  - Added Steam AppID auto-resolution and launch through `steam://rungameid/` for Steam DRM titles.
- **Windows UI Culture Detection & Unicode Box Fix (PR #18):**
  - Auto-selects the system display language from `Get-UICulture` on first launch while allowing manual override in the selector.
  - Sanitized emojis in `translations.json` and replaced `[⚡]` markers with ASCII `[>]` to prevent square box glyphs (`[]`) on systems with legacy GDI fonts.
- **Payload Verification Tooling (PR #20):**
  - Added `tools/Verify-Payload.ps1` and `tools/payload-manifest.json` for auditing local binaries against reviewed SHA-256 hashes and Authenticode signatures.
- **Native Detection & Injection for 12+ Console Generations:**
  - Added dedicated executable signatures and heuristics for PlayStation 1 (DuckStation, ePSXe, Beetle/Mednafen), PlayStation 2 (PCSX2), PlayStation 3 (RPCS3), PlayStation 4 (shadPS4), PS Vita (Vita3K), Nintendo Switch (Ryujinx, Yuzu, Suyu, Eden, Torzu), Nintendo Wii & GameCube (Dolphin), Nintendo Wii U (Cemu), Nintendo 3DS (Citra, Lime3DS, Azahar), Nintendo DS & GBA (melonDS, DeSmuME, mGBA, No$GBA, VBA), Nintendo Retro (Project64, Snes9x, Mesen, FCEUX, Nestopia), Xbox & Xbox 360 (Xenia, Xenia-Canary, Cxbx-Reloaded), and PSP / Arcade / Multi-System (PPSSPP, Flycast, Redream, RetroArch, MAME, ScummVM).
  - Extended multi-drive scanner to automatically scan `\Emulators`, `\Emuladores`, `\Emu`, `\RetroBat\emulators`, `\LaunchBox\Emulators`, `\Playnite\Emulators`, `%LOCALAPPDATA%\Programs`, `%APPDATA%\rpcs3`, and `ProgramFiles`.

### 🔍 Deep Continuous Hardware & System Telemetry Logging Engine
- **Millisecond Timestamp Precision:**
  - Every entry in `core/1-Click-DLSS5.log` now features high-precision timestamps: `[yyyy-MM-dd HH:mm:ss.fff]`.
- **System Audit Banner on Startup:**
  - Captures full hardware snapshot: Windows caption, display version, build number, machine uptime, elevated admin status, CPU model, physical/logical cores, max clock, dGPU vs iGPU identification, driver version and release date, dedicated VRAM, HAGS state, physical/virtual RAM total and percent free, all storage partitions with filesystem format and free space, and multi-monitor setup with primary display and resolutions.

### 👤 Chronological User Interaction Logging (`[USER]`)
- **Complete In-App Audit Trail:**
  - Added detailed telemetry tracking user clicks in the game library ListView, search box input with filter match counts, manual mode card toggles, language dropdown selections, startup auto-scan checkbox toggles, manual browse dialog interactions, Drag & Drop imports, install button executions, process start PIDs and working directories, and factory restore confirmation decisions.

### 📦 Forensic Installation & Factory Restoration Engine
- **Byte-Level Verification & Anti-Contamination:**
  - Pre-flight write permission verification on target directories.
  - Granular logging of each injected component with source name, target path, and exact byte size.
  - Granular logging of each backed-up original game file with byte size.
  - Strict anti-contamination filter preventing previous DLSS 5 artifacts from being copied into factory backups.
  - Step-by-step restoration telemetry logging each restored file with KB size, each purged artifact with KB size, and cleanup of generated directories (`reshade-shaders`, `host64`, `layer-x64`).
  - Full exception logging with diagnostic error codes, probable cause, actionable fixes, complete stack traces, and tracking of `[1-CLICK AUTO FIX]` usage.

### ⚡ DirectX 12 RHI & Dual-GPU Laptop Compatibility (Issue #9)
- **High-Performance GPU Preference Registration:**
  - Auto-configures the target game executable in Windows DirectX preferences (`HKCU:\Software\Microsoft\DirectX\UserGpuPreferences`) to force dedicated high-performance GPU usage, eliminating the DX12 RHI / adapter selection failure on Windows 11 hybrid laptops.
  - Proactive pre-launch cleanup of conflicting `sl.dlss_nr.dll` files.
  - Pre-launch PE dependency auto-healing for Unreal Engine 5 titles (e.g., *S.T.A.L.K.E.R. 2*).

### 🚀 Non-Blocking Background Library Scanner & UI Language Auto-Detection
- **Zero-Freeze Startup:**
  - Drive scanning moved to background thread with thread-safe UI updates, resolving initial 1-2 minute app freezes on systems with large drives.
  - Persistent cache (`games_cache.json`) for instant library populating on launch.
  - Added "Escanear ao iniciar" / "Scan on startup" checkbox in toolbar.
- **Native OS Language Detection:**
  - Automatically queries Windows UI culture on first startup and configures the interface in the user's native tongue (PT, EN, ES, DE, FR, IT, JA, ZH, RU, KO) with graceful English fallback.

---

## [v2.6.0-release] - 2026-09-03

### 🛡️ Vigilant Game Integrity Engine & Universal Runtime Auto-Healing
- **Permanent Vendor Runtime Protection (`libxess.dll`, `nvngx_dlss.dll`, etc.):**
  - Resolved a critical bug where `Uninstall-Dlss5` or mode transitions could purge `libxess.dll` (Intel XeSS) in titles that natively depend on it (*Forza Horizon 5/6*, *Cyberpunk 2077*, *Shadow of the Tomb Raider*, *Deathloop*).
  - Implemented an absolute deletion blacklist protecting all vendor runtime libraries: `libxess*.dll`, `*xess*.dll`, `*xell*.dll`, `nvngx_dlss*.dll` (except DLSS-NR model), `sl.*.dll` (except DLSS-NR plugin), `amd_fidelityfx_*.dll`, `ffx_*.dll`, `amd_ags_*.dll`, `dxcompiler.dll`, `d3d12core.dll`, `bink2*.dll`, and `steam_api*.dll`.
- **Proactive PE Dependency Scanner & Auto-Healing Engine (`Repair-GameCriticalDependencies`):**
  - Added binary PE Import Table inspection that scans the target game executable for upscaler dependencies.
  - If a game imports `libxess.dll` or `nvngx_dlss.dll` but the library is missing from the directory, the engine automatically restores it from the embedded high-performance payload before any Windows "DLL not found" error can occur.
  - Auto-healing hooks integrated at 4 key points: during installation (`Install-Dlss5`), during uninstallation (`Uninstall-Dlss5`), upon library item selection (`Select-GameInInspector`), and immediately before game boot (`Start-GameExecutable` / `[▶] INICIAR JOGO`).
- **Bidirectional Backup Restoration on Mode Switch:**
  - Cross-mode switching now guarantees that any native file previously replaced by another mode is restored from `_DLSS5_Backup` before installing the new mode.

### 🎨 Prominent Installation Progress Bar & Status Engine
- **In-Line Visual Progress Panel:**
  - Integrated a dedicated, high-visibility 692px progress bar and status panel directly within `$actionPanel` (in the user's primary line of sight).
  - Granular 6-stage milestone tracker (15% -> 35% -> 55% -> 70% -> 85% -> 95% -> 100%) displaying descriptive, real-time operation steps and a high-contrast percentage badge.
  - Interactive button locking (`⏳ INSTALANDO DLSS 5...`) preventing duplicate clicks during deployment.
- **Enhanced Installation Success Modal Dialog (`Show-InstallationSuccessDialog`):**
  - Added modern modal window reporting deployment status, active mode, game executable, and hotkey guide.
  - Dedicated `[▶] Iniciar Jogo Agora` button to launch the game directly from the dialog.

### 🎮 ReShade Shader Suite Integration (Modes 1 & 3)
- **Turnkey Post-Processing Filters:**
  - Replicated battle-tested shaders across Mode 1 (Direct) and Mode 3 (Universal Feeder):
    - **AMD FidelityFX Contrast Adaptive Sharpening (CAS):** Crystal-clear texture acuity and fine edge definition.
    - **Vibrance:** Dynamic, natural color saturation enhancement.
    - **Subpixel Morphological Anti-Aliasing (SMAA) & FXAA:** Ultra-clean edge anti-aliasing.
  - Shaders are deployed pre-configured but default-disabled in `ReShadePreset.ini`, allowing immediate toggle without visual disruption.
- **Global Hotkey Architecture:**
  - `[End]` key: Master toggle to instantly turn all ReShade shaders ON/OFF for real-time A/B visual comparisons.
  - `[Home]` key: Opens the in-game ReShade configuration overlay menu.

### 🌐 UTF-8 BOM Stabilization & Multi-Language Typography
- **Encoding Corruption Fix:**
  - Re-encoded `core/assets/translations.json` and `core/1-Click-DLSS5.ps1` with UTF-8 BOM (`0xEF, 0xBB, 0xBF`), eliminating Windows-1252 code page collisions and corrupted accented characters (`Português`, `Español`, `Français`, `DIRETÓRIO`, `INJEÇÃO`).
  - Switched dictionary loading to `[System.IO.File]::ReadAllText(..., [System.Text.Encoding]::UTF8)`.
  - Restored clean, crisp symbol glyphs across all interactive buttons (`[⚡]`, `[✓]`, `[▶]`, `[↩]`, `[📁]`).

### 🖥️ UI & Dark Theme Polish
- **Eliminated White Horizontal Scrollbar:**
  - Optimized ListView column widths (185px, 90px, 130px = 405px < 432px usable width), completely eliminating the bright white Win32 system scrollbar glitch on dark mode.
  - Hooked `Add_Resize` dynamic autosizing event to seamlessly adjust column widths on window resize and maximize.
  - Applied `uxtheme.dll` `SetWindowTheme("Explorer")` to render sleek dark scrollbars.
- **Streamlined Single-Executable Distribution:**
  - Removed redundant `.bat` and `.vbs` launchers.
  - Unified deployment around the standalone native 64-bit binary `1-Click-DLSS5.exe` with embedded high-res icon and DPI awareness.

### 🧪 Automated Quality Assurance
- **Comprehensive Audit Suite Expanded to 29 Tests (100% PASS):**
  - Added **Test 29**: Validates native runtime integrity, ensuring `libxess.dll` is preserved across Mode 1 installation, uninstallation, and simulated external deletion with auto-healing.

---

## [v2.5.3-release] - 2026-09-02

### 🛡️ Critical Engine Bug Fixes & Architecture Hardening
- **Native Game Streamline Preservation on Factory Reset (`Uninstall-Dlss5`):**
  - Resolved critical issue where `Uninstall-Dlss5` was unconditionally deleting native game `sl.interposer.dll` and `sl.common.dll` in Streamline titles (*The Witcher 3: Complete Edition*, *Cyberpunk 2077*).
  - The uninstaller now strictly purges only files injected by the mod, preserving native game files with 100% integrity.
- **Recursive Directory Purge on Mode Switching (`Install-Dlss5`):**
  - Fixed cross-mode transition cleanup to recursively remove folders (`reshade-shaders`, `host64`, `layer-x64`), preventing orphaned shader files or helper binaries when switching between Feeder, OptiScaler, and Direct modes.
- **Payload Neural Plugin Bundling:**
  - Bundled official `sl.dlss_nr.dll` into `core/payload/` for games utilizing Streamline DLSS-NR plugin architecture.
- **Feeder v0.12.0 ReShade Overlay Synchronization:**
  - Updated `OverlayCollapsed` in `ReShade.ini` to `DLSS 5 Feed 0.12.0@dlss5-feed.addon64`, ensuring proper in-game overlay menu collapse.

### ⚡ Native Compilation & Professional Launcher
- **Native 64-Bit Windows Executable (`1-Click-DLSS5.exe`):**
  - Compiled high-performance C# native executable using `csc.exe` with embedded high-resolution application icon (`logo.ico`) and assembly metadata (`v2.5.3.0`).
  - Completely eliminates console/CMD window flashing during application launch.
  - Added seamless fallback chain in `1-Click-DLSS5.bat` prioritizing the native `.exe`.

### 🎨 Visual & UI/UX Polish (HUD v2)
- **High-DPI Per-Monitor V2 Awareness:**
  - Integrated `SetProcessDpiAwarenessContext(-4)` via P/Invoke to deliver crisp typography and interface scaling across 1080p, 1440p, and 4K displays.
- **Official Application Icon Loading:**
  - Resolved `$script:IconPath` fallback between `assets\icon.ico` and `assets\logo.ico`, ensuring the custom icon appears on the window and Windows taskbar.
- **Drag & Drop Game Folder Support:**
  - Added native Windows Forms drag-and-drop handler allowing users to drag game folders or `.exe` files directly into the window.
- **Dynamic Progress Bar in Footer:**
  - Added visual continuous progress bar in the footer panel during drive scanning.

### 🔍 Deterministic Detection Engine
- **PE Import Table (IAT) Inspection:**
  - Added fast binary inspection of the target executable's PE Import Table to detect graphics APIs (`d3d12.dll`, `d3d11.dll`, `vulkan-1.dll`, `opengl32.dll`) even when no local DirectX DLLs exist in the game directory.
- **Windows Registry Library Auto-Discovery:**
  - Integrated dynamic discovery querying Windows Registry keys for **Steam** (`SteamPath` / `InstallPath`), **Epic Games**, and **GOG Galaxy** across all storage drives.

---

## [v2.5.2-beta] - 2026-09-02

### 🚀 Major Engine Upgrades & DLSS 5 Feeder v0.12.0
- **Feeder Core Upgraded to Official v0.12.0 (Mode 3):**
  - Updated all bundled Feeder binaries (`dlss5-feed.addon64`, `dlss5-feed.addon32`, `host64/dlss5-feed-host64.exe`, and `DLSS5_Feed.fx`) to the latest official v0.12.0 release.
  - **GPU Drain Before Rebuild:** Added command queue draining prior to D3D12 feature recreation, eliminating Device Removal (TDR) crashes.
  - **AMD FSR 1 Expand-Back (EASU + RCAS):** Replaced legacy bilinear stretching with AMD FSR 1 spatial upscaling + sharpening when operating at lower work resolutions.
  - **In-Game Overlay for 32-bit Games:** Added live in-game panel mirroring for 32-bit titles without requiring Alt-Tab.
- **Pristine 100% Native DLAA Clarity (Zero Blurry Text):**
  - Strictly enforced native resolution DLAA profile (`preset=6` and `work_resolution=100`) in `dlss5-feed.cfg`.
  - Preserved the full **LumeniteFX Kernel** suite (`lumenite_Kernel.fx`, `lumenite_TRAA.fx`, headers and blue noise texture) at the top of the execution chain (`DLSS5_MV_PROVIDER=3`).
- **Dynamic Cross-Mode Isolation:**
  - Automatically detects and cleanly purges inactive mode files when switching between Mode 1 (Direct), Mode 2 (OptiScaler), and Mode 3 (Feeder), preventing dual-proxy conflicts (`version.dll` + `dxgi.dll`).
  - Preserves original game file backups across mode changes.
- **Preexisting ReShade Configuration Protection:**
  - Preexisting `ReShade.ini` and `ReShadePreset.ini` are now safely preserved in `_1Click_DLSS5_Backup\` and restored with 100% byte-fidelity on factory reset.
- **Native Game `nvngx_dlss.dll` Integrity Protection (Mode 1):**
  - Mode 1 strictly preserves native game DLSS binaries, preventing hash mismatch flags in third-party launchers (Rockstar Games Launcher in RDR2, EA App, Ubisoft Connect).
- **Universal Launcher & Path Resiliency:**
  - Added standalone `1-Click-DLSS5.bat` launcher in repository root with robust `%~dp0` quote handling.
  - Hardened game drive scanner with bracket `[...]` and non-ASCII character immunity.
  - Added non-invasive runtime Vulkan layer binding (`VK_LAYER_PATH` / `VK_INSTANCE_LAYERS`) without Windows Registry modifications.

---

## [v2.5.1] - 2026-09-02

### 🛡️ Critical Engine Fixes & Game Compatibility
- **Witcher 3 Next-Gen Streamline Protection (Mode 1):**
  - Resolved `Entry Point Not Found: slGetFeatureSettings` crash on startup in *The Witcher 3: Complete Edition*.
  - Mode 1 strictly preserves native game `sl.interposer.dll` and `sl.common.dll` binaries, avoiding DLL version conflicts.
- **Red Dead Redemption 2 & NGX Direct Games (Mode 1):**
  - Fixed `0xBAD00007 / HOOKS ARMED - NO DLSS CREATE SEEN` issue in non-Streamline games like *Red Dead Redemption 2*.
  - Automatically configures `EnableHooks=1` for pure NGX titles.
  - Added smart guidance: RDR2 requires setting the in-game Graphics API to **DirectX 12** (*Settings > Graphics > Advanced > Graphics API = DirectX 12*).
- **Bulletproof 1-Click Factory Restoration:**
  - Guaranteed unconditional removal of proxy DLLs (`dxgi.dll`, `d3d12.dll`, `d3d9.dll`, `opengl32.dll`), add-ons, and shader caches on factory reset.
- **DLSS 5 Feeder Core Updated to v0.12.0 (Mode 3):**
  - Updated bundled Feeder binaries (`dlss5-feed.addon64`, `dlss5-feed.addon32`, `dlss5-feed-host64.exe`, and `DLSS5_Feed.fx`) to the official v0.12.0 release.
  - Preserved 100% native DLAA image clarity (`preset=6` and `work_resolution=100`) with zero text or texture blur.
  - Maintained full LumeniteFX Kernel motion vector estimation (`DLSS5_MV_PROVIDER=3` and `Lumenite_Kernel.fx` execution priority).
  - Integrated GPU drain before teardown to eliminate device-removal crashes during texture rebuilds.
  - Added FSR 1 (EASU + RCAS) expand-back upscaling and sharpness filter for lower work resolutions.
  - Integrated live in-game settings panel mirroring for 32-bit games without needing Alt-Tab.
  - Added dedicated non-intrusive Vulkan layer packages (`layer-x64` / `layer-x86`) and updated uninstaller purge list to ensure 100% clean factory restoration.
- **UI & Documentation Sync:**
  - Integrated 3 dedicated individual interface previews for Modes 1, 2, and 3 in the documentation.


## [v2.5.0-beta] - 2026-09-02

### 🚀 Major Features & Architectural Redesign (HUD v2)
- **🛡️ The Witcher 3 & Streamline Interposer Protection (Mode 1):**
  - Eliminated `Entry Point Not Found: slGetFeatureSettings` startup crashes in *The Witcher 3: Complete Edition* and Streamline games.
  - The installer now strictly preserves the game's native `sl.interposer.dll` and `sl.common.dll`, injecting only ReShade proxy, RenoDX addon, and `nvngx_dlssnr.dll`.

- **🎯 Red Dead Redemption 2 & Non-Streamline NGX Hooking:**
  - Fixed `HOOKS ARMED - NO DLSS CREATE SEEN` / `0xBAD00007` in *Red Dead Redemption 2* and native NGX games.
  - Automatically configures `EnableHooks=1` for non-Streamline games to hook the NVIDIA NGX export directly.
  - Added smart guidance: RDR2 requires setting the in-game Graphics API to **DirectX 12** (*Settings > Graphics > Advanced > Graphics API = DirectX 12*).

- **↩️ Bulletproof 1-Click Factory Restoration:**
  - Restored unconditional, guaranteed purging of proxy DLLs (`dxgi.dll`, `d3d12.dll`, `d3d9.dll`, `opengl32.dll`), addons, and shaders during factory reset, preventing broken game states.
- **✨ Complete UI Overhaul (HUD v2):**
  - Modern, minimalist, high-contrast dark theme built from the ground up for both beginner and advanced users.
  - Streamlined 3-step visual workflow: `[1] Select Game` ➔ `[2] Click Install` ➔ `[3] Launch & Enjoy!`.
  - Removed all duplicate buttons and legacy cluttered options.
  - Interactive mode selection cards with distinct accent colors and contextual in-game requirement instructions.
  - Selected Game Banner displays the extracted high-resolution application icon, real-time injection status, and API badge.

- **⚡ 1-Click Auto-Fix Engine & Smart Diagnosis:**
  - Automated issue resolution assistant: analyzes *What Happened*, *Probable Cause*, and *How to Fix*.
  - `[⚡] 1-CLICK AUTO-FIX` button automatically terminates stuck game processes, clears read-only permission locks (`attrib -r`), and reapplies injection cleanly.
  - Interactive `🩺 SYSTEM DIAGNOSTICS` checklist validating RTX GPU tensor support, directory write access, active game processes, and neural runtime file integrity.

- **🌍 Native 10-Language Support:**
  - Full dynamic real-time language switching without restart for:
    - 🇺🇸 English (EN-US)
    - 🇧🇷 Portuguese (PT-BR)
    - 🇪🇸 Spanish (ES)
    - 🇩🇪 German (DE)
    - 🇫🇷 French (FR)
    - 🇮🇹 Italian (IT)
    - 🇯🇵 Japanese (JA)
    - 🇨🇳 Simplified Chinese (ZH)
    - 🇷🇺 Russian (RU)
    - 🇰🇷 Korean (KO)
  - All localization dictionaries unified in `core/assets/translations.json`.

- **🎮 Instant Game Auto-Discovery & Multi-Platform Scanner:**
  - Fast, non-blocking multi-drive scanner detecting games across **Steam** (`libraryfolders.vdf`), **Epic Games** (`.item` manifests), **GOG**, **Xbox Games**, and **EA App**.
  - Real-time search bar for filtering titles by name or graphics API.

- **⚙️ Universal Graphics API & Architecture Support:**
  - Full native support for **DirectX 12, DirectX 11, DirectX 9, Vulkan, and OpenGL**.
  - Complete support for **32-bit (x86)** and **64-bit (x64)** games via `host64` IPC texture transport.

- **🎯 Critical Fix for Universal Feeder (Mode 3 - 100% Native DLAA):**
  - Resolved DX11 startup crashes and texture blurring (e.g., in *Mafia Definitive Edition*).
  - Integrated **Lumenite Kernel** (`Lumenite_Kernel.fx`) at the head of ReShade's technique chain for accurate optical flow motion vector calculation.
  - Configured `preset=6` in `dlss5-feed.cfg` for maximum frame stability.
  - Added recursive search paths (`\**`) in `ReShade.ini` (`EffectSearchPaths=.
eshade-shaders\Shaders\**`).
  - Calibrated RenoDX neural tone & structure parameters (`NRGlobalTone=0.9`, `NRLocalStructure=0.44`, `NRLocalTone=1.22`, `NRSkinStructure=1.16`).

- **↩️ 100% Clean Factory Restoration:**
  - Smart uninstaller restores original backed-up executables/DLLs and surgically purges all injected files, shaders, and logs.

---

## [v1.5.1] - Hotfix & Multi-Drive Resolver
- Fixed multi-drive Steam library resolution when installed across secondary volumes.
- Added 32-bit PE machine type header detection.
- Added profiles for Final Fantasy X HD Remaster and Falcom / Cold Steel titles.
- Optimized drive scanner with depth-controlled traversal.

## [v1.5.0] - Universal API Detection Engine
- Implemented deterministic graphics API detector for D3D12, D3D11, D3D9, Vulkan, and OpenGL.
- Initial integration of shader suite and luma mask calibration.

## [v1.4.0] - OptiScaler Bridge Mode (Mode 2)
- Added Mode 2 for games with FSR 2/3 or XeSS support, redirecting calls to DLSS-NR via OptiScaler.

## [v1.3.0] - Direct Injection Mode (Mode 1)
- Implemented Mode 1 for native DLSS games using Streamline interposer and RenoDX DLSS-NR addon.

## [v1.2.0] - Multi-Language & Confirmation System
- Introduced bilingual English/Portuguese UI and confirmation dialogs.

## [v1.1.0] - Initial Public Release
- Initial release featuring ReShade + RenoDX DLSS 5 injection.
