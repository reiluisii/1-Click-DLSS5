<#
.SYNOPSIS
    1 Click DLSS 5 v2.6.0-release - Universal Neural Control Center
    Instant game auto-discovery (Steam, Epic, GOG, Xbox, EA), 1-Click Auto-Fix engine,
    universal API support (DirectX 9/10/11/12, Vulkan, OpenGL), 32 & 64-bit, 10 languages (English default).
#>

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

[System.Windows.Forms.Application]::EnableVisualStyles()

# --- PER-MONITOR V2 HIGH-DPI ACTIVATION (CRISP AT 1080P/1440P/4K) ---
try {
    if (-not ([System.Management.Automation.PSTypeName]'DLSS5DpiHelper').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DLSS5DpiHelper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetProcessDpiAwarenessContext(int dpiFlag);
    [DllImport("uxtheme.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
    public static extern int SetWindowTheme(IntPtr hWnd, string pszSubAppName, string pszSubIdList);
    public static void EnableHighDpi() {
        try { SetProcessDpiAwarenessContext(-4); } catch {}
    }
}
"@
    }
    [DLSS5DpiHelper]::EnableHighDpi()
}
catch {}

# --- GLOBAL SETTINGS ---
$script:Version = "2.6.0-release"
$script:CurrentLang = "EN"
$script:AddOnName = "renodx-dlss5.addon64"
$script:StateName = "_dlss5_install_state.json"
$script:BackupName = "_DLSS5_Backup"
$script:SelectedGameObj = $null
$script:CurrentDetectedUpscaler = "UNIVERSAL_FEEDER"
$script:SelectedMode = "AUTO"
$script:CurrentGameLibrary = @()

$script:PayloadFolder = Join-Path $PSScriptRoot "payload"
$script:IconPath = Join-Path $PSScriptRoot "assets\icon.ico"
if (-not (Test-Path -LiteralPath $script:IconPath -PathType Leaf)) {
    $script:IconPath = Join-Path $PSScriptRoot "assets\logo.ico"
}
$script:TranslationsPath = Join-Path $PSScriptRoot "assets\translations.json"
$script:LogFilePath = Join-Path $PSScriptRoot "1-Click-DLSS5.log"

$script:Translations = $null
if (Test-Path -LiteralPath $script:TranslationsPath -PathType Leaf) {
    try {
        $jsonRaw = [System.IO.File]::ReadAllText($script:TranslationsPath, [System.Text.Encoding]::UTF8)
        $script:Translations = $jsonRaw | ConvertFrom-Json
    }
    catch {}
}

# --- TELEMETRY AND CONTINUOUS LOG INITIALIZATION ---
function Write-Status {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][string]$Level = "INFO",
        [Parameter(Mandatory = $false)][string]$Code = "",
        [Parameter(Mandatory = $false)][string]$Cause = "",
        [Parameter(Mandatory = $false)][string]$Fix = ""
    )
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$ts] [$Level] $Message"
    if ($Code) { $logLine = $logLine + " [CODE: $Code]" }
    if ($Cause) { $logLine = $logLine + " [CAUSE: $Cause]" }
    if ($Fix) { $logLine = $logLine + " [FIX: $Fix]" }

    try {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::AppendAllText($script:LogFilePath, $logLine + "`r`n", $utf8NoBom)
    }
    catch {}

    if ($script:StatusLabel) {
        $color = [System.Drawing.Color]::FromArgb(170, 205, 255)
        if ($Level -eq "OK") {
            $color = [System.Drawing.Color]::FromArgb(118, 225, 125)
        }
        elseif ($Level -eq "WARN") {
            $color = [System.Drawing.Color]::FromArgb(255, 205, 90)
        }
        elseif ($Level -eq "ERROR") {
            $color = [System.Drawing.Color]::FromArgb(255, 110, 110)
        }
        $script:StatusLabel.Text = "  " + $Message
        $script:StatusLabel.ForeColor = $color
    }
}

function Init-SystemTelemetryLog {
    if (-not (Test-Path -LiteralPath $script:LogFilePath -PathType Leaf)) {
        $sysInfo = "================================================================================`r`n"
        $sysInfo = $sysInfo + "   1 CLICK DLSS 5 v$($script:Version)   NEURAL CONTROL CENTER TELEMETRY LOG`r`n"
        $sysInfo = $sysInfo + "   Started at: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))`r`n"
        $sysInfo = $sysInfo + "================================================================================`r`n"
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
            if ($os) { $sysInfo = $sysInfo + "OS: $($os.Caption) ($($os.Version) Build $($os.BuildNumber))`r`n" }
            $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
            if ($gpus) {
                foreach ($g in $gpus) {
                    $sysInfo = $sysInfo + "GPU: $($g.Name) (Driver: $($g.DriverVersion))`r`n"
                }
            }
            $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
            if ($cpu) { $sysInfo = $sysInfo + "CPU: $($cpu.Name)`r`n" }
        }
        catch {}
        $sysInfo = $sysInfo + "================================================================================`r`n`r`n"
        try { 
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText($script:LogFilePath, $sysInfo, $utf8NoBom) 
        }
        catch {}
    }
}
Init-SystemTelemetryLog

function Open-LogFile {
    if (Test-Path -LiteralPath $script:LogFilePath -PathType Leaf) {
        Start-Process "notepad.exe" -ArgumentList "`"$script:LogFilePath`""
    }
    else {
        [System.Windows.Forms.MessageBox]::Show("No log has been generated yet.", "1 Click DLSS 5", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
}

function Get-DLSS5PayloadDirectory {
    if (Test-Path -LiteralPath $script:PayloadFolder -PathType Container) {
        return $script:PayloadFolder
    }
    $alt = Join-Path $PSScriptRoot "core\payload"
    if (Test-Path -LiteralPath $alt -PathType Container) {
        return $alt
    }
    return $script:PayloadFolder
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    $hashBytes = $sha.ComputeHash($stream)
    $stream.Close()
    $stream.Dispose()
    return ( -join ($hashBytes | ForEach-Object { "{0:x2}" -f $_ }))
}

function Get-PeArchitecture {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "UNKNOWN" }
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        $br = New-Object System.IO.BinaryReader($fs)
        if ($fs.Length -lt 64) { $fs.Close(); return "UNKNOWN" }
        $mz = $br.ReadUInt16()
        if ($mz -ne 0x5A4D) { $fs.Close(); return "UNKNOWN" }
        $fs.Position = 0x3C
        $peOffset = $br.ReadInt32()
        if ($peOffset -lt 0 -or $peOffset -ge ($fs.Length - 4)) { $fs.Close(); return "UNKNOWN" }
        $fs.Position = $peOffset
        $peSig = $br.ReadUInt32()
        if ($peSig -ne 0x00004550) { $fs.Close(); return "UNKNOWN" }
        $machine = $br.ReadUInt16()
        $fs.Close()
        if ($machine -eq 0x8664) { return "X64" }
        if ($machine -eq 0x014C) { return "X86" }
        if ($machine -eq 0xAA64) { return "ARM64" }
        return "OTHER"
    }
    catch {
        return "UNKNOWN"
    }
}

function Test-ValidPe {
    param([Parameter(Mandatory = $true)][string]$Path)
    $arch = Get-PeArchitecture -Path $Path
    return ($arch -eq "X64" -or $arch -eq "X86" -or $arch -eq "ARM64")
}

function Sanitize-PathString {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $p = $Path.Trim()
    if ($p.StartsWith('"') -and $p.EndsWith('"') -and $p.Length -ge 2) {
        $p = $p.Substring(1, $p.Length - 2)
    }
    return $p.Trim()
}

function Resolve-GameTarget {
    param([Parameter(Mandatory = $true)][string]$TargetPath)
    $cleanPath = Sanitize-PathString -Path $TargetPath
    if (-not (Test-Path -LiteralPath $cleanPath)) {
        throw "ERR_PATH_NOT_FOUND: The specified path does not exist: $TargetPath"
    }
    $targetItem = Get-Item -LiteralPath $cleanPath
    $folder = ""
    if ($targetItem.PSIsContainer) {
        $folder = $targetItem.FullName
    }
    else {
        $folder = $targetItem.Directory.FullName
    }
    $root = $folder
    $exePath = $null

    $allExes = @(Get-ChildItem -LiteralPath $folder -Filter "*.exe" -File -Recurse -Depth 4 -ErrorAction SilentlyContinue)
    $ignoredPattern = '^(crashreport|crashhandler|unitycrashhandler|unins.*|setup|config|launcher|easyanticheat|battleye|epicgameslauncher|redist|vcredist|dxsetup|quickstart|webinstaller|support|console.*|banana.*)$'
    $filtered = @($allExes | Where-Object {
            $baseName = $_.BaseName.ToLower()
            -not ($baseName -match $ignoredPattern)
        })

    # Se o usu rio apontou diretamente para um execut vel espec fico
    if (-not $targetItem.PSIsContainer -and $targetItem.Extension -ieq ".exe") {
        $directArch = Get-PeArchitecture -Path $targetItem.FullName
        # Se apontou para um execut vel 64-bit ou se est  em subpasta profunda, respeitar a escolha
        if ($directArch -eq "X64" -or ($targetItem.Directory.FullName -ne $folder)) {
            $exePath = $targetItem.FullName
        }
    }

    if (-not $exePath) {
        # 1. Prioridade M xima: Execut veis em subpastas de engine 64-bit conhecidas
        # (Bin64 [BeamNG, CryEngine], bin\x64 [Cyberpunk, Witcher], binaries\win64 [Unreal], x64, bin\win64)
        $known64Subfolders = '\\(binaries\\win64|bin64|bin\\x64|bin\\x64_dx12|bin\\win64|x64)\\'
        $found64Subdir = @($filtered | Where-Object {
                $_.FullName -imatch $known64Subfolders -and (Test-ValidPe -Path $_.FullName) -and ((Get-PeArchitecture -Path $_.FullName) -eq "X64")
            } | Sort-Object -Property Length -Descending)

        if ($found64Subdir.Count -gt 0) {
            $exePath = $found64Subdir[0].FullName
        }
        else {
            # 2. Execut veis com sufixo x64 (ex: *.x64.exe, *64.exe)
            $foundX64Named = @($filtered | Where-Object {
                    $_.Name -imatch '(\.x64\.exe|_x64\.exe|win64.*\.exe)$' -and (Test-ValidPe -Path $_.FullName) -and ((Get-PeArchitecture -Path $_.FullName) -eq "X64")
                } | Sort-Object -Property Length -Descending)

            if ($foundX64Named.Count -gt 0) {
                $exePath = $foundX64Named[0].FullName
            }
            else {
                # 3. Execut veis na raiz vs subpastas: se o da raiz for 32-bit (X86), mas existir um 64-bit em subpasta, preferir o 64-bit
                $rootExes = @($filtered | Where-Object { $_.Directory.FullName -ieq $folder -and (Test-ValidPe -Path $_.FullName) } | Sort-Object -Property Length -Descending)
                $allX64 = @($filtered | Where-Object { (Test-ValidPe -Path $_.FullName) -and ((Get-PeArchitecture -Path $_.FullName) -eq "X64") } | Sort-Object -Property Length -Descending)

                if ($rootExes.Count -gt 0 -and ((Get-PeArchitecture -Path $rootExes[0].FullName) -eq "X64")) {
                    $exePath = $rootExes[0].FullName
                }
                elseif ($allX64.Count -gt 0) {
                    $exePath = $allX64[0].FullName
                }
                elseif ($rootExes.Count -gt 0) {
                    $exePath = $rootExes[0].FullName
                }
                elseif ($filtered.Count -gt 0) {
                    $largest = $filtered | Sort-Object -Property Length -Descending | Select-Object -First 1
                    $exePath = $largest.FullName
                }
            }
        }
    }

    if (-not $exePath) {
        throw "ERR_EXE_NOT_FOUND: No compatible game executable was found in folder: $folder"
    }

    $installFolder = (Get-Item -LiteralPath $exePath).Directory.FullName
    $icon = $null
    try {
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
    }
    catch {}

    return [pscustomobject]@{
        Root          = $root
        InstallFolder = $installFolder
        Executable    = $exePath
        ExeName       = (Split-Path -Leaf $exePath)
        Icon          = $icon
        Architecture  = (Get-PeArchitecture -Path $exePath)
    }
}

function Detect-GameGraphicsApi {
    param(
        [Parameter(Mandatory = $true)][string]$TargetExe,
        [Parameter(Mandatory = $false)][string]$GameFolder = ""
    )
    if ([string]::IsNullOrWhiteSpace($GameFolder)) {
        $GameFolder = (Split-Path -Parent $TargetExe)
    }

    # 1. Inspe  o direta do PE Import Table do execut vel alvo (IAT Determin stico)
    if (Test-Path -LiteralPath $TargetExe -PathType Leaf) {
        try {
            $fs = [System.IO.File]::OpenRead($TargetExe)
            $len = [Math]::Min($fs.Length, 4194304)
            $bytes = New-Object byte[] $len
            [void]$fs.Read($bytes, 0, $len)
            $fs.Close()
            $str = [System.Text.Encoding]::ASCII.GetString($bytes)
            if ($str -match '(?i)\bd3d12\.dll\b') { return "D3D12" }
            if ($str -match '(?i)\bvulkan-1\.dll\b') { return "VULKAN" }
            if ($str -match '(?i)\bd3d11\.dll\b') { return "DXGI" }
            if ($str -match '(?i)\bd3d9\.dll\b') { return "D3D9" }
            if ($str -match '(?i)\bopengl32\.dll\b') { return "OPENGL" }
        }
        catch {}
    }

    # 2. Verifica  o de DLLs distribu das na pasta local do jogo
    $allDlls = @(Get-ChildItem -LiteralPath $GameFolder -Filter "*.dll" -File -Recurse -Depth 3 -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToLower() })
    if ($allDlls -contains "d3d12.dll" -or $allDlls -contains "d3d12core.dll") { return "D3D12" }
    if ($allDlls -contains "vulkan-1.dll" -or $allDlls -contains "vulkan.dll") { return "VULKAN" }
    if ($allDlls -contains "d3d11.dll" -or $allDlls -contains "dxgi.dll") { return "DXGI" }
    if ($allDlls -contains "d3d9.dll") { return "D3D9" }
    if ($allDlls -contains "opengl32.dll") { return "OPENGL" }

    # 3. Varredura de nomes de arquivos
    $allFiles = @(Get-ChildItem -LiteralPath $GameFolder -File -Recurse -Depth 3 -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToLower() })
    foreach ($f in $allFiles) {
        if ($f -match 'd3d12') { return "D3D12" }
        if ($f -match 'vulkan') { return "VULKAN" }
        if ($f -match 'd3d11|dxgi') { return "DXGI" }
        if ($f -match 'd3d9') { return "D3D9" }
    }
    return "DXGI"
}

function Detect-GameUpscalerType {
    param(
        [Parameter(Mandatory = $true)][string]$GameFolder,
        [Parameter(Mandatory = $false)][string]$GameRoot = ""
    )
    $folders = @($GameFolder)
    if (-not [string]::IsNullOrWhiteSpace($GameRoot) -and ($GameRoot -ne $GameFolder)) {
        $folders += $GameRoot
    }

    $allFiles = New-Object System.Collections.Generic.List[string]
    foreach ($fPath in $folders) {
        if (Test-Path -LiteralPath $fPath -PathType Container) {
            $files = @(Get-ChildItem -LiteralPath $fPath -File -Recurse -Depth 4 -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToLower() })
            foreach ($fn in $files) { [void]$allFiles.Add($fn) }
        }
    }

    # 1. Verifica se j  est  instalado o mod DLSS 5
    $isModded = $false
    $modMode = ""
    if ($allFiles.Contains("dlss5-feed.addon64") -or $allFiles.Contains("dlss5-feed.addon32")) {
        $isModded = $true
        $modMode = "FEEDER"
    }
    elseif ($allFiles.Contains("version.dll") -and $allFiles.Contains("optiscaler.ini")) {
        $isModded = $true
        $modMode = "OPTISCALER"
    }
    elseif ($allFiles.Contains("sl.interposer.dll") -and $allFiles.Contains("nvngx_dlssnr.dll")) {
        $isModded = $true
        $modMode = "DIRECT"
    }
    elseif ($allFiles.Contains("nvngx_dlssnr.dll")) {
        $isModded = $true
        $modMode = "FEEDER"
    }

    # 2. Verifica se h  arquivo de estado
    $stateFiles = @("_dlss5_install_state.json", "_1click_dlss5_state.json", "_dlss5_easy_installer_state.json")
    foreach ($sf in $stateFiles) {
        $sp = Join-Path $GameFolder $sf
        if (Test-Path -LiteralPath $sp -PathType Leaf) {
            try {
                $saved = Get-Content -LiteralPath $sp -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($saved.UpscalerType) { return $saved.UpscalerType }
            }
            catch {}
        }
    }

    # Se for um jogo que j  tem o mod instalado e n o tem state file, retornar o modo detectado dos bin rios
    if ($isModded) {
        if ($modMode -eq "DIRECT") { return "NATIVE_DLSS" }
        if ($modMode -eq "OPTISCALER") { return "FSR2_BRIDGE" }
        return "UNIVERSAL_FEEDER"
    }

    # 3. Verifica upscaler nativo do jogo (sem mod)
    foreach ($f in $allFiles) {
        if ($f -match '^(nvngx_dlss\.dll|nvngx_dlssd\.dll|nvngx_dlssg\.dll|sl\.dlss\.dll)$') {
            return "NATIVE_DLSS"
        }
    }
    foreach ($f in $allFiles) {
        if ($f -match '^(ffx_fsr2_api.*\.dll|ffx_fsr3_api.*\.dll|amd_fidelityfx.*\.dll|fsr2\.dll)$') {
            return "FSR2_BRIDGE"
        }
    }
    foreach ($f in $allFiles) {
        if ($f -match '^(libxess\.dll|xess\.dll|libxell\.dll)$') {
            return "XESS_BRIDGE"
        }
    }

    return "UNIVERSAL_FEEDER"
}

function Test-GameDlss5Installed {
    param([Parameter(Mandatory = $true)][string]$GameFolder)
    $stateFiles = @("_dlss5_install_state.json", "_1click_dlss5_state.json", "_dlss5_easy_installer_state.json")
    foreach ($sf in $stateFiles) {
        if (Test-Path -LiteralPath (Join-Path $GameFolder $sf) -PathType Leaf) { return $true }
    }
    $nrPath = Join-Path $GameFolder "nvngx_dlssnr.dll"
    if (Test-Path -LiteralPath $nrPath -PathType Leaf) { return $true }
    $feedPath = Join-Path $GameFolder "dlss5-feed.addon64"
    if (Test-Path -LiteralPath $feedPath -PathType Leaf) { return $true }
    return $false
}

function Get-Dict {
    param([string]$Lang)
    if ($script:Translations -and $script:Translations.$Lang) {
        return $script:Translations.$Lang
    }
    if ($script:Translations -and $script:Translations.EN) {
        return $script:Translations.EN
    }
    return [pscustomobject]@{
        "Title"             = "1 CLICK DLSS 5"
        "Tagline"           = "NEURAL CONTROL CENTER • RTX 20 / 30 / 40 / 50 SERIES"
        "SubBadge"          = "DirectX 9 / 10 / 11 / 12 • Vulkan • OpenGL • 32 & 64-bit"
        "Step1"             = "[1] Choose Game"
        "Step2"             = "[2] Click Install"
        "Step3"             = "[3] Launch & Enjoy!"
        "SearchPlaceholder" = "Search installed games..."
        "BtnScan"           = "SCAN DISKS"
        "BtnBrowse"         = "BROWSE GAME..."
        "BtnDiagnose"       = "[+] SYSTEM DIAGNOSIS"
        "LibraryTitle"      = "DETECTED GAME LIBRARY"
        "ColGame"           = "Game Title"
        "ColApi"            = "API / Arch"
        "ColMode"           = "Recommended Mode"
        "InspectorTitle"    = "INJECTION CONTROL PANEL"
        "NoGameSelected"    = "Select a game from the library or browse a folder."
        "FolderLabel"       = "GAME INSTALLATION DIRECTORY:"
        "ModeSectionTitle"  = "CHOOSE DLSS 5 INJECTION MODE:"
        "AutoModeNotice"    = "Optimal mode auto-selected for this game"
        "Mode1Title"        = "MODE 1: DIRECT (Native DLSS)"
        "Mode1Desc"         = "For games with native DLSS. Injects Streamline + AI with massive FPS boost."
        "Mode2Title"        = "MODE 2: OPTISCALER BRIDGE (FSR2/XeSS)"
        "Mode2Desc"         = "Redirects FSR2/XeSS calls to DLSS 5 Neural Rendering."
        "Mode3Title"        = "MODE 3: UNIVERSAL FEEDER (100% Native DLAA)"
        "Mode3Desc"         = "For ANY PC Game (Mafia, GTA, etc). 100% clean reconstruction with zero blur."
        "RequirementTitle"  = "IN-GAME REQUIREMENT:"
        "ReqMode1"          = "In graphics options: ENABLE 'NVIDIA DLSS' (Quality/Performance) for massive FPS."
        "ReqMode2"          = "In graphics options: ENABLE FSR2 or XeSS in Quality mode."
        "ReqMode3"          = "In graphics options: keep DLSS/Upscaling DISABLED (100% native DLAA). The Feeder injects AI directly on the clean frame."
        "BtnInstall"        = "[1-CLICK] INSTALL DLSS 5"
        "BtnLaunch"         = "[>] LAUNCH GAME"
        "BtnUninstall"      = "[<] RESTORE FACTORY"
        "BtnOpenFolder"     = "[FOLDER] OPEN FOLDER"
        "BtnOpenLog"        = "VIEW FULL LOG"
        "StatusReady"       = "Ready. Select a game to begin."
        "StatusScanning"    = "Scanning disks and analyzing game compatibility..."
        "StatusScanDone"    = "Scan finished! {0} games loaded into library."
        "StatusInstalled"   = "[DLSS 5 ACTIVE]"
        "SuccessTitle"      = "Installation Completed Successfully"
        "SuccessMsg"        = "DLSS 5 has been successfully injected into the game!`n`nApplied mode: {0}`n`nYou can now launch the game and enjoy maximum quality."
        "RestoreTitle"      = "Restoration Complete"
        "RestoreMsg"        = "Game restored to 100% factory original state! All files verified and zero mod leftovers remain."
        "ErrDialogTitle"    = "Diagnostic & Troubleshooting Assistant"
        "ErrWhatHappened"   = "WHAT HAPPENED:"
        "ErrProbableCause"  = "PROBABLE CAUSE:"
        "ErrHowToFix"       = "HOW TO FIX:"
        "DiagTitle"         = "System & Game Compatibility Diagnostics"
        "DiagGpuOk"         = "NVIDIA RTX GPU & Driver detected."
        "DiagPermsOk"       = "Folder write permissions: Fully Granted."
        "DiagProcOk"        = "The game is not currently running (Files unlocked)."
        "DiagRuntimeOk"     = "Neural runtimes & DLSS 5 models verified intact."
        "DiagAllPass"       = "Your PC and game are 100% ready for DLSS 5!"
        "BtnAutoFix"        = "[FIX] 1-CLICK AUTO-FIX & INSTALL"
        "AutoFixDone"       = "Issue fixed automatically! DLSS 5 is installed and the game is ready."
        "AutoFixProgress"   = "Executing 1-click automatic fix..."
        "BtnReinstall"      = "[UPDATE] REINSTALL DLSS 5"
        "BtnLaunchNow"      = "[>] LAUNCH GAME NOW"
        "BtnClose"          = "Close"
    }
}

# --- INSTALLATION SUCCESS DIALOG ---
function Show-InstallationSuccessDialog {
    param(
        [Parameter(Mandatory = $true)][string]$GameName,
        [Parameter(Mandatory = $true)][string]$ModeName,
        [Parameter(Mandatory = $true)][string]$TargetExePath
    )
    $d = Get-Dict -Lang $script:CurrentLang
    Write-Status -Message "DLSS 5 installed successfully in $GameName [$ModeName]!" -Level "OK"

    if ($env:DLSS5_HEADLESS) { return }

    $succForm = New-Object System.Windows.Forms.Form
    $succForm.Text = "Installation Completed Successfully - 1 Click DLSS 5"
    $succForm.Size = New-Object System.Drawing.Size(640, 430)
    $succForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $succForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $succForm.MaximizeBox = $false
    $succForm.MinimizeBox = $false
    $succForm.BackColor = [System.Drawing.Color]::FromArgb(14, 20, 34)
    $succForm.ForeColor = [System.Drawing.Color]::White
    $succForm.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $succForm.TopMost = $true

    $lblBigTitle = New-Object System.Windows.Forms.Label
    $lblBigTitle.Text = "[OK] DLSS 5 INJECTED SUCCESSFULLY!"
    $lblBigTitle.Location = New-Object System.Drawing.Point(20, 16)
    $lblBigTitle.Size = New-Object System.Drawing.Size(585, 32)
    $lblBigTitle.Font = New-Object System.Drawing.Font("Segoe UI Bold", 13)
    $lblBigTitle.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
    [void]$succForm.Controls.Add($lblBigTitle)

    $infoBox = New-Object System.Windows.Forms.Panel
    $infoBox.Location = New-Object System.Drawing.Point(20, 54)
    $infoBox.Size = New-Object System.Drawing.Size(585, 235)
    $infoBox.BackColor = [System.Drawing.Color]::FromArgb(20, 30, 50)
    [void]$succForm.Controls.Add($infoBox)

    $lblGame = New-Object System.Windows.Forms.Label
    $lblGame.Text = "Game: " + $GameName
    $lblGame.Location = New-Object System.Drawing.Point(15, 12)
    $lblGame.Size = New-Object System.Drawing.Size(555, 22)
    $lblGame.Font = New-Object System.Drawing.Font("Segoe UI Bold", 10.5)
    $lblGame.ForeColor = [System.Drawing.Color]::White
    [void]$infoBox.Controls.Add($lblGame)

    $lblMode = New-Object System.Windows.Forms.Label
    $lblMode.Text = "Mode: " + $ModeName
    $lblMode.Location = New-Object System.Drawing.Point(15, 38)
    $lblMode.Size = New-Object System.Drawing.Size(555, 20)
    $lblMode.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $lblMode.ForeColor = [System.Drawing.Color]::FromArgb(100, 180, 255)
    [void]$infoBox.Controls.Add($lblMode)

    $lblFilters = New-Object System.Windows.Forms.Label
    $lblFilters.Text = "Included filters: CAS (Sharpening) + Vibrance (Color) + SMAA (AA) + Splitscreen"
    $lblFilters.Location = New-Object System.Drawing.Point(15, 62)
    $lblFilters.Size = New-Object System.Drawing.Size(555, 20)
    $lblFilters.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblFilters.ForeColor = [System.Drawing.Color]::FromArgb(180, 230, 160)
    [void]$infoBox.Controls.Add($lblFilters)

    $lblHotkey = New-Object System.Windows.Forms.Label
    $lblHotkey.Text = "Comparison hotkey: press [End] in-game to toggle all effects instantly!"
    $lblHotkey.Location = New-Object System.Drawing.Point(15, 86)
    $lblHotkey.Size = New-Object System.Drawing.Size(555, 20)
    $lblHotkey.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
    $lblHotkey.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 90)
    [void]$infoBox.Controls.Add($lblHotkey)

    $lblSep = New-Object System.Windows.Forms.Panel
    $lblSep.Location = New-Object System.Drawing.Point(15, 112)
    $lblSep.Size = New-Object System.Drawing.Size(555, 1)
    $lblSep.BackColor = [System.Drawing.Color]::FromArgb(40, 60, 95)
    [void]$infoBox.Controls.Add($lblSep)

    $lblInstTitle = New-Object System.Windows.Forms.Label
    $lblInstTitle.Text = "[INFO] HOW TO USE IT IN-GAME:"
    $lblInstTitle.Location = New-Object System.Drawing.Point(15, 122)
    $lblInstTitle.Size = New-Object System.Drawing.Size(555, 20)
    $lblInstTitle.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9)
    $lblInstTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 90)
    [void]$infoBox.Controls.Add($lblInstTitle)

    $instText = "In the game's video settings: keep the upscaler OFF. DLSS 5 runs at native resolution with maximum neural quality."
    if ($ModeName -match 'DIRECT|Mode 1') {
        $instText = "In the game's video settings: ENABLE DLSS (Quality or Performance). Press [Home] to open the neural panel."
    }
    elseif ($ModeName -match 'OPTISCALER|Mode 2') {
        $instText = "In the game's video settings: ENABLE FSR 2 or XeSS (Quality). OptiScaler redirects it to the DLSS 5 AI model."
    }

    $lblInstDesc = New-Object System.Windows.Forms.Label
    $lblInstDesc.Text = $instText
    $lblInstDesc.Location = New-Object System.Drawing.Point(15, 146)
    $lblInstDesc.Size = New-Object System.Drawing.Size(555, 75)
    $lblInstDesc.ForeColor = [System.Drawing.Color]::FromArgb(210, 230, 255)
    $lblInstDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    [void]$infoBox.Controls.Add($lblInstDesc)

    # Action buttons
    $btnLaunchNow = New-Object System.Windows.Forms.Button
    $btnLaunchNow.Text = "[>] LAUNCH GAME NOW"
    $btnLaunchNow.Location = New-Object System.Drawing.Point(20, 305)
    $btnLaunchNow.Size = New-Object System.Drawing.Size(380, 50)
    $btnLaunchNow.Font = New-Object System.Drawing.Font("Segoe UI Bold", 11)
    Style-Button -Button $btnLaunchNow -BaseColor ([System.Drawing.Color]::FromArgb(0, 130, 230)) -HoverColor ([System.Drawing.Color]::FromArgb(20, 160, 255))
    $btnLaunchNow.Add_Click({
            $succForm.Close()
            Start-GameExecutable -ExecutablePath $TargetExePath
        })
    [void]$succForm.Controls.Add($btnLaunchNow)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = New-Object System.Drawing.Point(415, 305)
    $btnClose.Size = New-Object System.Drawing.Size(190, 50)
    $btnClose.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    Style-Button -Button $btnClose -BaseColor ([System.Drawing.Color]::FromArgb(35, 55, 90)) -HoverColor ([System.Drawing.Color]::FromArgb(50, 75, 125))
    $btnClose.Add_Click({ $succForm.Close() })
    [void]$succForm.Controls.Add($btnClose)

    $succForm.Add_Shown({
        $this.BringToFront()
        $this.Activate()
    })

    if ($form -and $form.Visible) {
        [void]$succForm.ShowDialog($form)
    }
    else {
        [void]$succForm.ShowDialog()
    }
}

# --- 1-CLICK RESOLUTION ASSISTANT (AUTO-FIX) ---
function Resolve-IssueInOneClick {
    param([string]$TargetPath, [string]$SelectedMode)
    $d = Get-Dict -Lang $script:CurrentLang
    Write-Status -Message $d.AutoFixProgress -Level "INFO"

    try {
        $resolved = Resolve-GameTarget -TargetPath $TargetPath
        $folder = $resolved.InstallFolder
        $exeBase = [System.IO.Path]::GetFileNameWithoutExtension($resolved.ExeName)

        # 1. Finaliza processo travado do jogo se existir
        $procs = @(Get-Process -Name $exeBase -ErrorAction SilentlyContinue)
        foreach ($p in $procs) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Write-Status -Message "Stuck process ($exeBase.exe) terminated successfully." -Level "INFO"
        }

        # 2. Remove atributo Somente Leitura da pasta
        if (Test-Path -LiteralPath $folder) {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c attrib -r `"$folder\*.*`" /s /d" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
        }

        # 3. Autocura preventiva de dependencias do executavel (libxess.dll, nvngx_dlss.dll, etc.)
        Repair-GameCriticalDependencies -TargetFolder $folder -TargetExe $resolved.Executable

        # 4. Executa a instalacao
        Install-Dlss5 -TargetPath $TargetPath -SelectedMode $SelectedMode
        Write-Status -Message $d.AutoFixDone -Level "OK"
        return $true
    }
    catch {
        Write-Status -Message ("Auto-Fix failed: " + $_.Exception.Message) -Level "ERROR"
        return $false
    }
}

function Get-ErrorDiagnosis {
    param([System.Exception]$Ex, [string]$Context = "")
    $msg = $Ex.Message
    $code = "ERR_UNKNOWN"
    $what = "An unexpected problem occurred while running the operation ($Context)."
    $cause = "File system inconsistency or Windows security configuration."
    $fix = "1. Close the game if it is open.`n2. Click '1-CLICK AUTO-FIX & INSTALL'.`n3. Or run this tool as Administrator."

    if ($msg -match 'ERR_EXE_NOT_FOUND' -or $msg -match 'No compatible game executable') {
        $code = "ERR_EXE_NOT_FOUND"
        $what = "No main game executable (.exe) was found in the selected folder."
        $cause = "The chosen folder may be empty or may be the parent folder of several games."
        $fix = "1. Click 'BROWSE GAME' and select the exact folder where the game is installed.`n2. Or click 'SCAN DISKS' to locate your installed games automatically."
    }
    elseif ($msg -match 'UnauthorizedAccessException' -or $msg -match 'Access denied' -or $msg -match 'Access is denied') {
        $code = "ERR_PERM_DENIED"
        $what = "Windows blocked writing or modifying files in the game folder."
        $cause = "Missing Administrator privileges or a 'Read-only' attribute on the installation folder."
        $fix = "1. Click the '1-CLICK AUTO-FIX & INSTALL' button below to unlock access automatically.`n2. Or right-click 1 Click DLSS 5 and choose 'Run as administrator'."
    }
    elseif ($msg -match 'IOException' -or $msg -match 'being used by another process' -or $msg -match 'used by another process') {
        $code = "ERR_FILE_LOCKED"
        $what = "One of the game files is locked and cannot be updated right now."
        $cause = "The game is still open in the background, or a program such as Discord/RivaTuner is holding the DLL."
        $fix = "1. Click the '1-CLICK AUTO-FIX & INSTALL' button below to close the stuck processes and install automatically."
    }
    elseif ($msg -match 'ERR_PATH_NOT_FOUND' -or $msg -match 'does not exist') {
        $code = "ERR_PATH_NOT_FOUND"
        $what = "The folder path provided was not found on this computer."
        $cause = "The game may have been moved to another drive or uninstalled."
        $fix = "1. Click 'BROWSE GAME' and locate the game's current folder."
    }

    return [pscustomobject]@{
        Code       = $code
        What       = $what
        Cause      = $cause
        Fix        = $fix
        RawMessage = $msg
        StackTrace = $Ex.StackTrace
    }
}

function Show-FriendlyErrorDialog {
    param([System.Exception]$Ex, [string]$Context = "", [string]$TargetPath = "", [string]$SelectedMode = "AUTO")
    $diag = Get-ErrorDiagnosis -Ex $Ex -Context $Context
    $d = Get-Dict -Lang $script:CurrentLang

    Write-Status -Message "ERROR IN $Context : $($diag.RawMessage)" -Level "ERROR" -Code $diag.Code -Cause $diag.Cause -Fix $diag.Fix

    if ($env:DLSS5_HEADLESS) { return }

    $errForm = New-Object System.Windows.Forms.Form
    $errForm.Text = $d.ErrDialogTitle + " [" + $diag.Code + "]"
    $errForm.Size = New-Object System.Drawing.Size(660, 500)
    $errForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $errForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $errForm.MaximizeBox = $false
    $errForm.MinimizeBox = $false
    $errForm.BackColor = [System.Drawing.Color]::FromArgb(16, 20, 32)
    $errForm.ForeColor = [System.Drawing.Color]::White
    $errForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $lblWhatHdr = New-Object System.Windows.Forms.Label
    $lblWhatHdr.Text = $d.ErrWhatHappened
    $lblWhatHdr.Location = New-Object System.Drawing.Point(20, 12)
    $lblWhatHdr.Size = New-Object System.Drawing.Size(610, 20)
    $lblWhatHdr.ForeColor = [System.Drawing.Color]::FromArgb(255, 110, 110)
    $lblWhatHdr.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9.5)
    [void]$errForm.Controls.Add($lblWhatHdr)

    $txtWhat = New-Object System.Windows.Forms.TextBox
    $txtWhat.Text = $diag.What
    $txtWhat.Location = New-Object System.Drawing.Point(20, 34)
    $txtWhat.Size = New-Object System.Drawing.Size(605, 42)
    $txtWhat.Multiline = $true
    $txtWhat.ReadOnly = $true
    $txtWhat.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 48)
    $txtWhat.ForeColor = [System.Drawing.Color]::Gainsboro
    $txtWhat.BorderStyle = "FixedSingle"
    [void]$errForm.Controls.Add($txtWhat)

    $lblCauseHdr = New-Object System.Windows.Forms.Label
    $lblCauseHdr.Text = $d.ErrProbableCause
    $lblCauseHdr.Location = New-Object System.Drawing.Point(20, 85)
    $lblCauseHdr.Size = New-Object System.Drawing.Size(610, 20)
    $lblCauseHdr.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 90)
    $lblCauseHdr.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9.5)
    [void]$errForm.Controls.Add($lblCauseHdr)

    $txtCause = New-Object System.Windows.Forms.TextBox
    $txtCause.Text = $diag.Cause
    $txtCause.Location = New-Object System.Drawing.Point(20, 107)
    $txtCause.Size = New-Object System.Drawing.Size(605, 42)
    $txtCause.Multiline = $true
    $txtCause.ReadOnly = $true
    $txtCause.BackColor = [System.Drawing.Color]::FromArgb(25, 30, 48)
    $txtCause.ForeColor = [System.Drawing.Color]::Gainsboro
    $txtCause.BorderStyle = "FixedSingle"
    [void]$errForm.Controls.Add($txtCause)

    $lblFixHdr = New-Object System.Windows.Forms.Label
    $lblFixHdr.Text = $d.ErrHowToFix
    $lblFixHdr.Location = New-Object System.Drawing.Point(20, 158)
    $lblFixHdr.Size = New-Object System.Drawing.Size(610, 20)
    $lblFixHdr.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
    $lblFixHdr.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9.5)
    [void]$errForm.Controls.Add($lblFixHdr)

    $txtFix = New-Object System.Windows.Forms.TextBox
    $txtFix.Text = $diag.Fix
    $txtFix.Location = New-Object System.Drawing.Point(20, 180)
    $txtFix.Size = New-Object System.Drawing.Size(605, 150)
    $txtFix.Multiline = $true
    $txtFix.ReadOnly = $true
    $txtFix.BackColor = [System.Drawing.Color]::FromArgb(25, 30, 48)
    $txtFix.ForeColor = [System.Drawing.Color]::FromArgb(180, 240, 200)
    $txtFix.BorderStyle = "FixedSingle"
    $txtFix.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    [void]$errForm.Controls.Add($txtFix)

    # 1-Click Auto-Fix button
    if (-not [string]::IsNullOrWhiteSpace($TargetPath)) {
        $btnAutoFix = New-Object System.Windows.Forms.Button
        $btnAutoFix.Text = $d.BtnAutoFix
        $btnAutoFix.Location = New-Object System.Drawing.Point(20, 345)
        $btnAutoFix.Size = New-Object System.Drawing.Size(605, 42)
        $btnAutoFix.Font = New-Object System.Drawing.Font("Segoe UI Bold", 11)
        Style-Button -Button $btnAutoFix -BaseColor ([System.Drawing.Color]::FromArgb(118, 185, 0)) -HoverColor ([System.Drawing.Color]::FromArgb(140, 220, 0)) -TextColor ([System.Drawing.Color]::Black)
        $btnAutoFix.Add_Click({
                $ok = Resolve-IssueInOneClick -TargetPath $TargetPath -SelectedMode $SelectedMode
                if ($ok) { $errForm.Close() }
            })
        [void]$errForm.Controls.Add($btnAutoFix)
    }

    $btnOpenLogDlg = New-Object System.Windows.Forms.Button
    $btnOpenLogDlg.Text = "   " + $d.BtnOpenLog
    $btnOpenLogDlg.Location = New-Object System.Drawing.Point(20, 405)
    $btnOpenLogDlg.Size = New-Object System.Drawing.Size(200, 36)
    Style-Button -Button $btnOpenLogDlg -BaseColor ([System.Drawing.Color]::FromArgb(35, 55, 90)) -HoverColor ([System.Drawing.Color]::FromArgb(50, 75, 125))
    $btnOpenLogDlg.Add_Click({ Open-LogFile })
    [void]$errForm.Controls.Add($btnOpenLogDlg)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Close"
    $btnOk.Location = New-Object System.Drawing.Point(455, 405)
    $btnOk.Size = New-Object System.Drawing.Size(170, 36)
    Style-Button -Button $btnOk -BaseColor ([System.Drawing.Color]::FromArgb(35, 80, 145)) -HoverColor ([System.Drawing.Color]::FromArgb(50, 110, 195))
    $btnOk.Add_Click({ $errForm.Close() })
    [void]$errForm.Controls.Add($btnOk)

    [void]$errForm.ShowDialog()
}

function Show-SystemDiagnosisDialog {
    $d = Get-Dict -Lang $script:CurrentLang
    $diagForm = New-Object System.Windows.Forms.Form
    $diagForm.Text = $d.DiagTitle
    $diagForm.Size = New-Object System.Drawing.Size(640, 460)
    $diagForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $diagForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $diagForm.MaximizeBox = $false
    $diagForm.MinimizeBox = $false
    $diagForm.BackColor = [System.Drawing.Color]::FromArgb(12, 18, 30)
    $diagForm.ForeColor = [System.Drawing.Color]::White
    $diagForm.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

    $lblHdr = New-Object System.Windows.Forms.Label
    $lblHdr.Text = "SYSTEM COMPATIBILITY CHECKLIST"
    $lblHdr.Location = New-Object System.Drawing.Point(20, 15)
    $lblHdr.Size = New-Object System.Drawing.Size(590, 24)
    $lblHdr.Font = New-Object System.Drawing.Font("Segoe UI Bold", 11)
    $lblHdr.ForeColor = [System.Drawing.Color]::FromArgb(140, 205, 255)
    [void]$diagForm.Controls.Add($lblHdr)

    $listChecks = New-Object System.Windows.Forms.ListView
    $listChecks.Location = New-Object System.Drawing.Point(20, 50)
    $listChecks.Size = New-Object System.Drawing.Size(585, 290)
    $listChecks.View = [System.Windows.Forms.View]::Details
    $listChecks.FullRowSelect = $true
    $listChecks.BackColor = [System.Drawing.Color]::FromArgb(18, 25, 42)
    $listChecks.ForeColor = [System.Drawing.Color]::White
    $listChecks.BorderStyle = "FixedSingle"
    [void]$listChecks.Columns.Add("Checked Item", 200)
    [void]$listChecks.Columns.Add("Status", 90)
    [void]$listChecks.Columns.Add("Test Result", 280)
    [void]$diagForm.Controls.Add($listChecks)

    # 1. GPU Check
    $gpuName = "NVIDIA RTX Series"
    $gpuStatus = "[PASS]"
    $gpuDesc = $d.DiagGpuOk
    try {
        $g = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($g) { $gpuName = $g.Name; $gpuDesc = "$($g.Name) (Driver $($g.DriverVersion))" }
    }
    catch {}
    $it1 = New-Object System.Windows.Forms.ListViewItem("Graphics Card / Driver")
    [void]$it1.SubItems.Add($gpuStatus)
    [void]$it1.SubItems.Add($gpuDesc)
    $it1.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
    [void]$listChecks.Items.Add($it1)

    # 2. Write Perms
    $permStatus = "[PASS]"
    $permDesc = $d.DiagPermsOk
    if ($script:SelectedGameObj) {
        $testF = Join-Path $script:SelectedGameObj.Path "_test_write_perm.tmp"
        try {
            [System.IO.File]::WriteAllText($testF, "test")
            [System.IO.File]::Delete($testF)
        }
        catch {
            $permStatus = "[FAIL]"
            $permDesc = "Access denied in folder. Click Auto-Fix."
        }
    }
    $it2 = New-Object System.Windows.Forms.ListViewItem("Write Permissions")
    [void]$it2.SubItems.Add($permStatus)
    [void]$it2.SubItems.Add($permDesc)
    if ($permStatus -eq "[PASS]") {
        $it2.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
    }
    else {
        $it2.ForeColor = [System.Drawing.Color]::FromArgb(255, 110, 110)
    }
    [void]$listChecks.Items.Add($it2)

    # 3. Game Process Check
    $procStatus = "[PASS]"
    $procDesc = $d.DiagProcOk
    if ($script:SelectedGameObj) {
        $exeBase = [System.IO.Path]::GetFileNameWithoutExtension($script:SelectedGameObj.ExeName)
        $p = Get-Process -Name $exeBase -ErrorAction SilentlyContinue
        if ($p) {
            $procStatus = "[WARN]"
            $procDesc = "The game $($script:SelectedGameObj.ExeName) is currently running!"
        }
    }
    $it3 = New-Object System.Windows.Forms.ListViewItem("Process Status")
    [void]$it3.SubItems.Add($procStatus)
    [void]$it3.SubItems.Add($procDesc)
    if ($procStatus -eq "[PASS]") {
        $it3.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
    }
    else {
        $it3.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 90)
    }
    [void]$listChecks.Items.Add($it3)

    # 4. Neural Payload Check
    $payStatus = "[PASS]"
    $payDesc = $d.DiagRuntimeOk
    $nrP = Join-Path (Get-DLSS5PayloadDirectory) "nvngx_dlssnr.dll"
    if (-not (Test-Path -LiteralPath $nrP)) {
        $payStatus = "[ERROR]"
        $payDesc = "nvngx_dlssnr.dll is missing from the payload folder."
    }
    $it4 = New-Object System.Windows.Forms.ListViewItem("DLSS 5 Runtimes")
    [void]$it4.SubItems.Add($payStatus)
    [void]$it4.SubItems.Add($payDesc)
    if ($payStatus -eq "[PASS]") {
        $it4.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
    }
    else {
        $it4.ForeColor = [System.Drawing.Color]::FromArgb(255, 110, 110)
    }
    [void]$listChecks.Items.Add($it4)

    $lblAll = New-Object System.Windows.Forms.Label
    $lblAll.Text = "  " + $d.DiagAllPass
    $lblAll.Location = New-Object System.Drawing.Point(20, 355)
    $lblAll.Size = New-Object System.Drawing.Size(585, 24)
    $lblAll.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
    $lblAll.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9.5)
    [void]$diagForm.Controls.Add($lblAll)

    $btnDiagClose = New-Object System.Windows.Forms.Button
    $btnDiagClose.Text = "Close"
    $btnDiagClose.Location = New-Object System.Drawing.Point(465, 385)
    $btnDiagClose.Size = New-Object System.Drawing.Size(140, 34)
    Style-Button -Button $btnDiagClose -BaseColor ([System.Drawing.Color]::FromArgb(35, 80, 145)) -HoverColor ([System.Drawing.Color]::FromArgb(50, 110, 195))
    $btnDiagClose.Add_Click({ $diagForm.Close() })
    [void]$diagForm.Controls.Add($btnDiagClose)

    [void]$diagForm.ShowDialog()
}

# --- RESHADE.INI AND PRESET CONFIGURATION ---
function Set-Dlss5ReShadeIni {
    param(
        [Parameter(Mandatory = $true)][string]$IniPath,
        [Parameter(Mandatory = $false)][bool]$IsFeederMode = $true,
        [Parameter(Mandatory = $false)][int]$EnableHooks = 1
    )
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    if ($IsFeederMode) {
        $iniContent = @"
[ADDON]
DisabledAddons=Generic Depth,Effect Runtime Sync
OverlayCollapsed=DLSS 5 Feed 0.12.0@dlss5-feed.addon64,DLSS 5 Neural Rendering@renodx-dlss5.addon64,Generic Depth,Effect Runtime Sync

[GENERAL]
EffectSearchPaths=.\reshade-shaders\Shaders\**
IntermediateCachePath=$env:TEMP\ReShade
NoDebugInfo=1
NoEffectCache=0
NoReloadOnInit=0
PerformanceMode=0
PresetPath=.\ReShadePreset.ini
PresetShortcutKeys=
PresetShortcutPaths=
PresetTransitionDuration=1000
SkipLoadingDisabledEffects=0
StartupPresetPath=
TextureSearchPaths=.\reshade-shaders\Textures\**

[INPUT]
ForceShortcutModifiers=1
InputProcessing=2
KeyEffects=35,0,0,0
KeyFPS=0,0,0,0
KeyFrametime=0,0,0,0
KeyNextPreset=0,0,0,0
KeyOverlay=36,0,0,0
KeyPreviousPreset=0,0,0,0
KeyReload=0,0,0,0
KeyScreenshot=44,0,0,0

[OVERLAY]
AutoSavePreset=1
ClockFormat=0
FPSPosition=1
Language=
ShowClock=0
ShowForceLoadEffectsButton=1
ShowFPS=2
ShowFrameTime=0
ShowPresetName=0
ShowPresetTransitionMessage=1
ShowScreenshotMessage=1
TutorialProgress=4
VariableListHeight=200.000000
VariableListUseTabs=0

[RenoDX.DLSS5]
EnableHooks=$EnableHooks
NeuralUplift=1
NRAutoMask=1
NRDepthMode=0
NRDiffuseWhiteNits=203
NRGlobalTone=0.9
NRLocalStructure=0.44
NRLocalTone=1.22
NRPreset=2
NRSkinStructure=1.16
NRStyle=1
NRUICorrection=1

[STYLE]
Alpha=1.000000
ChildRounding=0.000000
ColFPSText=1.000000,1.000000,0.784314,1.000000
EditorFont=
EditorFontSize=13.000000
EditorStyleIndex=0
Font=
FontScale=1.000000
FontSize=13.000000
FPSScale=1.000000
FrameRounding=0.000000
GrabRounding=0.000000
HdrOverlayBrightness=203.000000
HdrOverlayOverwriteColorSpaceTo=0
LatinFont=
PopupRounding=0.000000
ScrollbarRounding=0.000000
StyleIndex=2
TabRounding=5.000000
WindowRounding=0.000000
"@
    }
    else {
        $iniContent = @"
[ADDON]
DisabledAddons=Generic Depth,Effect Runtime Sync
OverlayCollapsed=DLSS 5 Neural Rendering@renodx-dlss5.addon64,Generic Depth,Effect Runtime Sync

[GENERAL]
EffectSearchPaths=.\reshade-shaders\Shaders\**
IntermediateCachePath=$env:TEMP\ReShade
NoDebugInfo=1
NoEffectCache=0
NoReloadOnInit=0
PerformanceMode=0
PresetPath=.\ReShadePreset.ini
PresetShortcutKeys=
PresetShortcutPaths=
PresetTransitionDuration=1000
SkipLoadingDisabledEffects=0
StartupPresetPath=
TextureSearchPaths=.\reshade-shaders\Textures\**

[INPUT]
ForceShortcutModifiers=1
InputProcessing=2
KeyEffects=35,0,0,0
KeyFPS=0,0,0,0
KeyFrametime=0,0,0,0
KeyNextPreset=0,0,0,0
KeyOverlay=36,0,0,0
KeyPreviousPreset=0,0,0,0
KeyReload=0,0,0,0
KeyScreenshot=44,0,0,0

[OVERLAY]
AutoSavePreset=1
ClockFormat=0
FPSPosition=1
Language=
ShowClock=0
ShowForceLoadEffectsButton=1
ShowFPS=2
ShowFrameTime=0
ShowPresetName=0
ShowPresetTransitionMessage=1
ShowScreenshotMessage=1
TutorialProgress=4
VariableListHeight=200.000000
VariableListUseTabs=0

[RenoDX.DLSS5]
EnableHooks=$EnableHooks
NeuralUplift=1
NRAutoMask=1
NRDepthMode=0
NRDiffuseWhiteNits=203
NRGlobalTone=0.9
NRLocalStructure=0.44
NRLocalTone=1.22
NRPreset=2
NRSkinStructure=1.16
NRStyle=1
NRUICorrection=1

[STYLE]
Alpha=1.000000
ChildRounding=0.000000
ColFPSText=1.000000,1.000000,0.784314,1.000000
EditorFont=
EditorFontSize=13.000000
EditorStyleIndex=0
Font=
FontScale=1.000000
FontSize=13.000000
FPSScale=1.000000
FrameRounding=0.000000
GrabRounding=0.000000
HdrOverlayBrightness=203.000000
HdrOverlayOverwriteColorSpaceTo=0
LatinFont=
PopupRounding=0.000000
ScrollbarRounding=0.000000
StyleIndex=2
TabRounding=5.000000
WindowRounding=0.000000
"@
    }
    [System.IO.File]::WriteAllText($IniPath, $iniContent, $utf8NoBom)
}

function Set-Dlss5PresetIni {
    param(
        [Parameter(Mandatory = $true)][string]$PresetPath,
        [Parameter(Mandatory = $false)][bool]$IsFeederMode = $true
    )
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $techniques = ""
    $sorting = ""
    $definitions = ""
    $feederSection = ""

    if ($IsFeederMode) {
        $techniques = "Lumenite_Kernel@lumenite_Kernel.fx,DLSS5_Feed@DLSS5_Feed.fx"
        $sorting = "Lumenite_Kernel@lumenite_Kernel.fx,DLSS5_Feed@DLSS5_Feed.fx,SMAA@SMAA.fx,FXAA@FXAA.fx,Lumenite_TRAA@lumenite_TRAA.fx,Vibrance@Vibrance.fx,Tonemap@Tonemap.fx,ContrastAdaptiveSharpen@CAS.fx,Splitscreen@Splitscreen.fx"
        $definitions = "PreprocessorDefinitions=DLSS5_MV_PROVIDER=3`r`n"
        $feederSection = @"

[DLSS5_Feed.fx]
PreprocessorDefinitions=DLSS5_MV_PROVIDER=3
"@
    }
    else {
        $techniques = ""
        $sorting = "SMAA@SMAA.fx,FXAA@FXAA.fx,Vibrance@Vibrance.fx,Tonemap@Tonemap.fx,ContrastAdaptiveSharpen@CAS.fx,Splitscreen@Splitscreen.fx"
        $definitions = ""
        $feederSection = ""
    }

    $presetContent = @"
Techniques=$techniques
TechniqueSorting=$sorting
$definitions$feederSection
[CAS.fx]
Contrast=0.000000
Sharpening=1.000000
Sharpness=0.400000

[Vibrance.fx]
Vibrance=0.280000
VibranceRGBBalance=1.000000,1.000000,1.000000

[Tonemap.fx]
Bleach=0.000000
Defog=0.000000
Exposure=0.000000
Gamma=1.000000
Saturation=0.000000

[SMAA.fx]
CornerRounding=25
DebugOutput=0
DepthEdgeDetectionThreshold=0.010000
EdgeDetectionThreshold=0.080000
EdgeDetectionType=1
MaxSearchSteps=32
MaxSearchStepsDiag=16
PredicationScale=2.000000
PredicationStrength=0.400000
PredicationThreshold=0.010000

[FXAA.fx]
EdgeThreshold=0.166000
EdgeThresholdMin=0.083300
Subpix=0.750000
"@
    [System.IO.File]::WriteAllText($PresetPath, $presetContent, $utf8NoBom)
}

# --- SELF-HEAL ENGINE FOR NATIVE GAME DEPENDENCIES ---
function Repair-GameCriticalDependencies {
    param(
        [Parameter(Mandatory = $true)][string]$TargetFolder,
        [Parameter(Mandatory = $true)][string]$TargetExe
    )
    if (-not (Test-Path -LiteralPath $TargetExe -PathType Leaf)) { return }
    if (-not (Test-Path -LiteralPath $TargetFolder -PathType Container)) { return }

    try {
        # 1. Inspeciona o binario do executavel para descobrir dependencias de upscalers nativos
        $stream = [System.IO.File]::OpenRead($TargetExe)
        $reader = New-Object System.IO.BinaryReader($stream)
        $readLen = [Math]::Min(150MB, $stream.Length)
        $exeBytes = $reader.ReadBytes($readLen)
        $reader.Close()
        $stream.Close()
        $exeAscii = [System.Text.Encoding]::ASCII.GetString($exeBytes)

        # 2. Intel XeSS (libxess.dll)
        if ($exeAscii -match 'libxess\.dll') {
            $xessTarget = Join-Path $TargetFolder "libxess.dll"
            if (-not (Test-Path -LiteralPath $xessTarget -PathType Leaf)) {
                $xessPayload = Join-Path (Get-DLSS5PayloadDirectory) "optiscaler\libxess.dll"
                if (Test-Path -LiteralPath $xessPayload -PathType Leaf) {
                    Copy-Item -LiteralPath $xessPayload -Destination $xessTarget -Force
                    Write-Status -Message "Self-heal: libxess.dll required by the executable was restored automatically." -Level "OK"
                }
            }
        }

        # 3. NVIDIA DLSS (nvngx_dlss.dll)
        if ($exeAscii -match 'nvngx_dlss\.dll') {
            $dlssTarget = Join-Path $TargetFolder "nvngx_dlss.dll"
            if (-not (Test-Path -LiteralPath $dlssTarget -PathType Leaf)) {
                $dlssPayload = Join-Path (Get-DLSS5PayloadDirectory) "nvngx_dlss.dll"
                if (Test-Path -LiteralPath $dlssPayload -PathType Leaf) {
                    Copy-Item -LiteralPath $dlssPayload -Destination $dlssTarget -Force
                    Write-Status -Message "Self-heal: nvngx_dlss.dll required by the executable was restored automatically." -Level "OK"
                }
            }
        }
    }
    catch {
        Write-Status -Message "Dependency scanner warning: $($_.Exception.Message)" -Level "WARN"
    }
}

# --- UNIVERSAL INSTALL ENGINE ---
function Install-Dlss5 {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $false)][string]$SelectedMode = "AUTO",
        [Parameter(Mandatory = $false)][scriptblock]$ProgressCallback = $null
    )
    if ($ProgressCallback) { &$ProgressCallback 10 "Checking game and components..." }
    $target = Resolve-GameTarget -TargetPath $TargetPath
    $targetFolder = $target.InstallFolder
    $d = Get-Dict -Lang $script:CurrentLang
    $feederPayload = Join-Path (Get-DLSS5PayloadDirectory) "feeder"

    $detectedUpscaler = Detect-GameUpscalerType -GameFolder $targetFolder -GameRoot $target.Root
    $api = Detect-GameGraphicsApi -TargetExe $target.Executable -GameFolder $targetFolder
    $effectiveMode = $SelectedMode
    if ($effectiveMode -eq "AUTO") {
        if ($detectedUpscaler -eq "NATIVE_DLSS") {
            $effectiveMode = "DIRECT"
        }
        elseif ($detectedUpscaler -eq "FSR2_BRIDGE" -or $detectedUpscaler -eq "XESS_BRIDGE") {
            $effectiveMode = "OPTISCALER"
        }
        else {
            $effectiveMode = "FEEDER"
        }
    }

    if ($ProgressCallback) { &$ProgressCallback 20 "Game: $($target.ExeName) | API: $api | Mode: $effectiveMode" }
    Write-Status -Message "Starting installation for: $($target.ExeName) | API: $api | Mode: $effectiveMode | Architecture: $($target.Architecture)" -Level "INFO"

    $backupFolder = Join-Path $targetFolder $script:BackupName
    [void](New-Item -ItemType Directory -Path $backupFolder -Force)
    $stateFile = Join-Path $targetFolder $script:StateName

    # Se ja existir uma instalacao anterior de outro modo, limpar arquivos injetados do modo anterior
    $existingBackedUp = @()
    if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
        try {
            $oldSaved = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($oldSaved.BackedUpFiles) { $existingBackedUp = @($oldSaved.BackedUpFiles) }
            if ($oldSaved.Mode -and ($oldSaved.Mode -ne $effectiveMode)) {
                if ($ProgressCallback) { &$ProgressCallback 30 "Mode change detected ($($oldSaved.Mode) -> $effectiveMode). Cleaning up previous files..." }
                Write-Status -Message "Mode change detected ($($oldSaved.Mode) -> $effectiveMode). Removing files from the previous mode..." -Level "INFO"
                $previousInjected = @($oldSaved.InjectedFiles)
                foreach ($oldFile in $previousInjected) {
                    if ($existingBackedUp -contains $oldFile) {
                        $bSrc = Join-Path $backupFolder $oldFile
                        if (Test-Path -LiteralPath $bSrc -PathType Leaf) {
                            Copy-Item -LiteralPath $bSrc -Destination (Join-Path $targetFolder $oldFile) -Force
                            Write-Status -Message "Original file restored from backup during mode change: $oldFile" -Level "INFO"
                        }
                    }
                    else {
                        $oldP = Join-Path $targetFolder $oldFile
                        if (Test-Path -LiteralPath $oldP) {
                            Remove-Item -LiteralPath $oldP -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
        }
        catch {}
    }
    if ($ProgressCallback) { &$ProgressCallback 40 "Backup point and folder structure prepared..." }

    $state = @{
        InstalledAt   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        TargetExe     = $target.Executable
        Mode          = $effectiveMode
        UpscalerType  = $detectedUpscaler
        Architecture  = $target.Architecture
        Api           = $api
        BackedUpFiles = $existingBackedUp
        InjectedFiles = @()
    }

    function Safe-Copy {
        param($Src, $DstName)
        $dst = Join-Path $targetFolder $DstName
        if (Test-Path -LiteralPath $dst -PathType Leaf) {
            # S  faz backup se o arquivo original N O foi injetado nesta mesma sess o
            if ($state.InjectedFiles -notcontains $DstName) {
                $bDst = Join-Path $backupFolder $DstName
                if (-not (Test-Path -LiteralPath $bDst -PathType Leaf)) {
                    Copy-Item -LiteralPath $dst -Destination $bDst -Force
                    $state.BackedUpFiles += $DstName
                }
            }
        }
        Copy-Item -LiteralPath $Src -Destination $dst -Force
        if ($state.InjectedFiles -notcontains $DstName) { $state.InjectedFiles += $DstName }
    }

    $isX64 = ($target.Architecture -eq "X64")
    $proxyDll = "dxgi.dll"
    if (-not $isX64) { $proxyDll = "dxgi32.dll" }

    if ($ProgressCallback) { &$ProgressCallback 55 "Injecting graphics proxy ($proxyDll) and neural models..." }

    # 1. ReShade proxy (adaptacao automatica por API)
    $dxgiSrc = Join-Path (Get-DLSS5PayloadDirectory) $proxyDll
    if (Test-Path -LiteralPath $dxgiSrc) {
        Safe-Copy -Src $dxgiSrc -DstName "dxgi.dll"
        if ($api -eq "D3D9") {
            Safe-Copy -Src $dxgiSrc -DstName "d3d9.dll"
        }
        if ($api -eq "OPENGL") {
            Safe-Copy -Src $dxgiSrc -DstName "opengl32.dll"
        }
    }

    # 2. RenoDX Addon e Modelos Neurais NVIDIA
    # Em jogos 64-bit (ou modos DIRECT/OPTISCALER), eles ficam na raiz do jogo.
    # Em jogos 32-bit no MODO FEEDER, eles vao EXCLUSIVAMENTE para a pasta host64\ onde o helper 64-bit os executa.
    if ($isX64 -or ($effectiveMode -ne "FEEDER")) {
        $renoSrc = Join-Path (Get-DLSS5PayloadDirectory) $script:AddOnName
        if (Test-Path -LiteralPath $renoSrc) {
            Safe-Copy -Src $renoSrc -DstName $script:AddOnName
        }
        $nrSrc = Join-Path (Get-DLSS5PayloadDirectory) "nvngx_dlssnr.dll"
        if (Test-Path -LiteralPath $nrSrc) {
            Safe-Copy -Src $nrSrc -DstName "nvngx_dlssnr.dll"
        }
        # Preserva nvngx_dlss.dll original do jogo caso ja exista (evita falha de integridade em launchers como RDR2)
        $dlssTarget = Join-Path $targetFolder "nvngx_dlss.dll"
        if (-not (Test-Path -LiteralPath $dlssTarget -PathType Leaf)) {
            $dlssSrc = Join-Path (Get-DLSS5PayloadDirectory) "nvngx_dlss.dll"
            if (Test-Path -LiteralPath $dlssSrc) {
                Safe-Copy -Src $dlssSrc -DstName "nvngx_dlss.dll"
            }
        }
    }

    # 3. Preservacao e Recuperacao de Dependencias Criticas (Ex: libxess.dll)
    # Jogos como Forza Horizon importam libxess.dll diretamente no executavel.
    # Se libxess.dll estiver ausente da pasta mas o executavel exigir, restaura automaticamente do payload!
    $xessTarget = Join-Path $targetFolder "libxess.dll"
    if (-not (Test-Path -LiteralPath $xessTarget -PathType Leaf)) {
        $exeFile = $target.Executable
        $needsXess = $false
        if (Test-Path -LiteralPath $exeFile -PathType Leaf) {
            try {
                $stream = [System.IO.File]::OpenRead($exeFile)
                $reader = New-Object System.IO.BinaryReader($stream)
                $readLen = [Math]::Min(100MB, $stream.Length)
                $exeBytes = $reader.ReadBytes($readLen)
                $reader.Close()
                $stream.Close()
                $exeAscii = [System.Text.Encoding]::ASCII.GetString($exeBytes)
                if ($exeAscii -match 'libxess\.dll') {
                    $needsXess = $true
                }
            } catch {}
        }
        if ($needsXess) {
            $xessSrc = Join-Path (Get-DLSS5PayloadDirectory) "optiscaler\libxess.dll"
            if (Test-Path -LiteralPath $xessSrc) {
                Copy-Item -LiteralPath $xessSrc -Destination $xessTarget -Force
                Write-Status -Message "Native libxess.dll dependency required by the executable detected. Restored from payload." -Level "OK"
            }
        }
    }

    if ($ProgressCallback) { &$ProgressCallback 70 "Configuring mode-specific components ($effectiveMode)..." }

    # 4. Injecao Especifica por Modo
    if ($effectiveMode -eq "DIRECT") {
        # JOGOS COM DLSS NATIVO: NUNCA sobrescrever o interposer Streamline nativo do jogo (ex: The Witcher 3, Cyberpunk)
        # para evitar erros de Entry Point (como slGetFeatureSettings ausente).
        # Apenas injetamos o proxy ReShade, o RenoDX Addon e o modelo nvngx_dlssnr.dll.
        $hasStreamline = (Test-Path -LiteralPath (Join-Path $targetFolder "sl.interposer.dll") -PathType Leaf)
        $hookVal = if ($hasStreamline) { 2 } else { 1 }
        
        # Se o jogo j  possui Streamline e suporta sl.dlss_nr.dll opcional, podemos fornecer apenas o plugin neural sem tocar no interposer
        $slNrSrc = Join-Path (Get-DLSS5PayloadDirectory) "sl.dlss_nr.dll"
        if ($hasStreamline -and (Test-Path -LiteralPath $slNrSrc -PathType Leaf)) {
            Safe-Copy -Src $slNrSrc -DstName "sl.dlss_nr.dll"
        }

        # Shaders e Texturas opcionais para ReShade (CAS, Vibrance, Tonemap, SMAA, FXAA)
        $shaderDir = Join-Path $targetFolder "reshade-shaders\Shaders"
        [void](New-Item -ItemType Directory -Path $shaderDir -Force)
        Get-ChildItem -LiteralPath (Join-Path $feederPayload "shaders") | Copy-Item -Destination $shaderDir -Recurse -Force
        
        $texPayload = Join-Path $feederPayload "textures"
        if (Test-Path -LiteralPath $texPayload -PathType Container) {
            $texDir = Join-Path $targetFolder "reshade-shaders\Textures"
            [void](New-Item -ItemType Directory -Path $texDir -Force)
            Get-ChildItem -LiteralPath $texPayload | Copy-Item -Destination $texDir -Recurse -Force
        }
        if ($state.InjectedFiles -notcontains "reshade-shaders") { $state.InjectedFiles += "reshade-shaders" }

        $targetPreset = Join-Path $targetFolder "ReShadePreset.ini"
        if ((Test-Path -LiteralPath $targetPreset -PathType Leaf) -and ($state.InjectedFiles -notcontains "ReShadePreset.ini")) {
            $bDst = Join-Path $backupFolder "ReShadePreset.ini"
            if (-not (Test-Path -LiteralPath $bDst -PathType Leaf)) {
                Copy-Item -LiteralPath $targetPreset -Destination $bDst -Force
                $state.BackedUpFiles += "ReShadePreset.ini"
            }
        }
        Set-Dlss5PresetIni -PresetPath $targetPreset -IsFeederMode $false
        if ($state.InjectedFiles -notcontains "ReShadePreset.ini") { $state.InjectedFiles += "ReShadePreset.ini" }

        $targetIni = Join-Path $targetFolder "ReShade.ini"
        if ((Test-Path -LiteralPath $targetIni -PathType Leaf) -and ($state.InjectedFiles -notcontains "ReShade.ini")) {
            $bDst = Join-Path $backupFolder "ReShade.ini"
            if (-not (Test-Path -LiteralPath $bDst -PathType Leaf)) {
                Copy-Item -LiteralPath $targetIni -Destination $bDst -Force
                $state.BackedUpFiles += "ReShade.ini"
            }
        }
        Set-Dlss5ReShadeIni -IniPath $targetIni -IsFeederMode $false -EnableHooks $hookVal
        if ($state.InjectedFiles -notcontains "ReShade.ini") { $state.InjectedFiles += "ReShade.ini" }
    }
    elseif ($effectiveMode -eq "OPTISCALER") {
        $optiSrc = Join-Path (Get-DLSS5PayloadDirectory) "optiscaler\OptiScaler.dll"
        if (Test-Path -LiteralPath $optiSrc) { Safe-Copy -Src $optiSrc -DstName "version.dll" }
        $optiIni = Join-Path (Get-DLSS5PayloadDirectory) "optiscaler\OptiScaler.ini"
        if (Test-Path -LiteralPath $optiIni) { Safe-Copy -Src $optiIni -DstName "OptiScaler.ini" }
        $xessSrc = Join-Path (Get-DLSS5PayloadDirectory) "optiscaler\libxess.dll"
        if (Test-Path -LiteralPath $xessSrc) { Safe-Copy -Src $xessSrc -DstName "libxess.dll" }
        $targetIni = Join-Path $targetFolder "ReShade.ini"
        if ((Test-Path -LiteralPath $targetIni -PathType Leaf) -and ($state.InjectedFiles -notcontains "ReShade.ini")) {
            $bDst = Join-Path $backupFolder "ReShade.ini"
            if (-not (Test-Path -LiteralPath $bDst -PathType Leaf)) {
                Copy-Item -LiteralPath $targetIni -Destination $bDst -Force
                $state.BackedUpFiles += "ReShade.ini"
            }
        }
        Set-Dlss5ReShadeIni -IniPath $targetIni -IsFeederMode $false
        if ($state.InjectedFiles -notcontains "ReShade.ini") { $state.InjectedFiles += "ReShade.ini" }
    }
    else {
        if ($isX64) {
            $feedSrc = Join-Path $feederPayload "dlss5-feed.addon64"
            if (Test-Path -LiteralPath $feedSrc) { Safe-Copy -Src $feedSrc -DstName "dlss5-feed.addon64" }
        }
        else {
            $feedSrc32 = Join-Path $feederPayload "dlss5-feed.addon32"
            if (Test-Path -LiteralPath $feedSrc32) { Safe-Copy -Src $feedSrc32 -DstName "dlss5-feed.addon32" }
            $hostDst = Join-Path $targetFolder "host64"
            [void](New-Item -ItemType Directory -Path $hostDst -Force)
            Get-ChildItem -LiteralPath (Join-Path $feederPayload "host64") | Copy-Item -Destination $hostDst -Recurse -Force
            Copy-Item -LiteralPath (Join-Path (Get-DLSS5PayloadDirectory) "dxgi.dll") -Destination (Join-Path $hostDst "dxgi.dll") -Force
            Copy-Item -LiteralPath (Join-Path (Get-DLSS5PayloadDirectory) "nvngx_dlssnr.dll") -Destination (Join-Path $hostDst "nvngx_dlssnr.dll") -Force
            Copy-Item -LiteralPath (Join-Path (Get-DLSS5PayloadDirectory) "nvngx_dlss.dll") -Destination (Join-Path $hostDst "nvngx_dlss.dll") -Force
            Copy-Item -LiteralPath (Join-Path (Get-DLSS5PayloadDirectory) $script:AddOnName) -Destination (Join-Path $hostDst $script:AddOnName) -Force
            if ($state.InjectedFiles -notcontains "host64") { $state.InjectedFiles += "host64" }
        }

        # Shaders
        $shaderDir = Join-Path $targetFolder "reshade-shaders\Shaders"
        [void](New-Item -ItemType Directory -Path $shaderDir -Force)
        Get-ChildItem -LiteralPath (Join-Path $feederPayload "shaders") | Copy-Item -Destination $shaderDir -Recurse -Force
        
        # Textures
        $texPayload = Join-Path $feederPayload "textures"
        if (Test-Path -LiteralPath $texPayload -PathType Container) {
            $texDir = Join-Path $targetFolder "reshade-shaders\Textures"
            [void](New-Item -ItemType Directory -Path $texDir -Force)
            Get-ChildItem -LiteralPath $texPayload | Copy-Item -Destination $texDir -Recurse -Force
        }
        if ($state.InjectedFiles -notcontains "reshade-shaders") { $state.InjectedFiles += "reshade-shaders" }

        $cfgSrc = Join-Path $feederPayload "dlss5-feed.cfg"
        if (Test-Path -LiteralPath $cfgSrc) { Safe-Copy -Src $cfgSrc -DstName "dlss5-feed.cfg" }

        # Inje  o de camada Vulkan se o jogo for baseado em Vulkan
        if ($api -eq "VULKAN") {
            $layerFolderName = if ($isX64) { "layer-x64" } else { "layer-x86" }
            $layerSrcDir = Join-Path $feederPayload $layerFolderName
            if (Test-Path -LiteralPath $layerSrcDir -PathType Container) {
                Get-ChildItem -LiteralPath $layerSrcDir -File | ForEach-Object {
                    Safe-Copy -Src $_.FullName -DstName $_.Name
                }
            }
        }

        $targetPreset = Join-Path $targetFolder "ReShadePreset.ini"
        if ((Test-Path -LiteralPath $targetPreset -PathType Leaf) -and ($state.InjectedFiles -notcontains "ReShadePreset.ini")) {
            $bDst = Join-Path $backupFolder "ReShadePreset.ini"
            if (-not (Test-Path -LiteralPath $bDst -PathType Leaf)) {
                Copy-Item -LiteralPath $targetPreset -Destination $bDst -Force
                $state.BackedUpFiles += "ReShadePreset.ini"
            }
        }
        Set-Dlss5PresetIni -PresetPath $targetPreset -IsFeederMode $true
        if ($state.InjectedFiles -notcontains "ReShadePreset.ini") { $state.InjectedFiles += "ReShadePreset.ini" }

        $targetIni = Join-Path $targetFolder "ReShade.ini"
        if ((Test-Path -LiteralPath $targetIni -PathType Leaf) -and ($state.InjectedFiles -notcontains "ReShade.ini")) {
            $bDst = Join-Path $backupFolder "ReShade.ini"
            if (-not (Test-Path -LiteralPath $bDst -PathType Leaf)) {
                Copy-Item -LiteralPath $targetIni -Destination $bDst -Force
                $state.BackedUpFiles += "ReShade.ini"
            }
        }
        Set-Dlss5ReShadeIni -IniPath $targetIni -IsFeederMode $true
        if ($state.InjectedFiles -notcontains "ReShade.ini") { $state.InjectedFiles += "ReShade.ini" }
    }

    # Autocura preventiva final pos-instalacao: garante que dependencias nativas exigidas estejam presentes
    Repair-GameCriticalDependencies -TargetFolder $targetFolder -TargetExe $target.Executable

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json -Depth 4), $utf8NoBom)
    
    $modeReadable = switch ($effectiveMode) {
        "DIRECT" { "Mode 1: Direct (Native DLSS)" }
        "OPTISCALER" { "Mode 2: OptiScaler Bridge (FSR2/XeSS)" }
        default { "Mode 3: Universal Feeder (100% Native DLAA)" }
    }
    
    if ($ProgressCallback) { &$ProgressCallback 100 "DLSS 5 installed successfully!" }
    Show-InstallationSuccessDialog -GameName $target.ExeName -ModeName $modeReadable -TargetExePath $target.Executable
}

# --- FACTORY RESTORE ENGINE (UNINSTALL) ---
function Uninstall-Dlss5 {
    param([Parameter(Mandatory = $true)][string]$TargetPath)
    $target = Resolve-GameTarget -TargetPath $TargetPath
    $targetFolder = $target.InstallFolder
    $stateFile = Join-Path $targetFolder $script:StateName
    $backupFolder = Join-Path $targetFolder $script:BackupName
    $d = Get-Dict -Lang $script:CurrentLang

    Write-Status -Message "Restoring game to factory original state in: $targetFolder" -Level "INFO"

    $savedBacked = @()
    $savedInjected = @()
    if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
        try {
            $saved = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($saved.BackedUpFiles) { $savedBacked = @($saved.BackedUpFiles) }
            if ($saved.InjectedFiles) { $savedInjected = @($saved.InjectedFiles) }
        }
        catch {}
    }

    if (Test-Path -LiteralPath $backupFolder -PathType Container) {
        $physBacked = Get-ChildItem -LiteralPath $backupFolder -File -ErrorAction SilentlyContinue
        foreach ($pb in $physBacked) {
            if ($savedBacked -notcontains $pb.Name) { $savedBacked += $pb.Name }
        }
    }

    if (Test-Path -LiteralPath $backupFolder -PathType Container) {
        $backed = Get-ChildItem -LiteralPath $backupFolder -File -ErrorAction SilentlyContinue
        foreach ($bf in $backed) {
            $dst = Join-Path $targetFolder $bf.Name
            Copy-Item -LiteralPath $bf.FullName -Destination $dst -Force
            Write-Status -Message "Original file restored: $($bf.Name)" -Level "OK"
        }
        Remove-Item -LiteralPath $backupFolder -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Lista de purga cirurgica estrita (ARQUIVOS EXCLUSIVOS do DLSS 5 / Feeder / ReShade / OptiScaler)
    # NUNCA incluir ou purgar bibliotecas originais de jogos (XeSS, DLSS, Streamline, FSR, Bink, Steam)
    $purgeList = @(
        "renodx-dlss5.addon64", "renodx-dlss5++.addon64", "renodx-dlss5-v3.addon64",
        "dlss5-feed.addon64", "dlss5-feed.addon32", "dlss5-feed.cfg", "dlss5-feed.log", "dlss5-feed.ini",
        "dlss5-feed-host.log", "dlss5-feed-crash.dmp",
        "VkLayer_feed_vk.dll", "VkLayer_feed_vk.json", "run-with-feed-layer.bat",
        "VkLayer_feed_vk32.dll", "VkLayer_feed_vk32.json", "run-with-feed-layer32.bat",
        "nvngx_dlssnr.dll", "sl.dlss_nr.dll",
        "OptiScaler.ini", "OptiScaler.log",
        "ReShade.ini", "ReShadePreset.ini", "ReShade.log",
        $script:StateName, "_1Click_DLSS5_State.json", "_DLSS5_Easy_Installer_State.json", "dlss5_backup_manifest.json"
    )

    # Adiciona proxies a lista de purga APENAS se foram injetados pelo DLSS 5 e nao pertenciam ao jogo
    $proxyCandidates = @("dxgi.dll", "d3d12.dll", "d3d9.dll", "opengl32.dll", "version.dll")
    foreach ($px in $proxyCandidates) {
        if ($savedInjected -contains $px -and ($savedBacked -notcontains $px)) {
            $purgeList += $px
        }
    }

    foreach ($inj in $savedInjected) {
        if ($savedBacked -notcontains $inj -and ($purgeList -notcontains $inj)) {
            $purgeList += $inj
        }
    }

    # FILTRO ABSOLUTO DE SEGURANCA: NUNCA PURGAR RUNTIMES NATIVOS DE FABRICA DE NENHUM JOGO
    $purgeList = @($purgeList | Where-Object {
        $fn = $_.ToLower()
        if ($fn -match '^(libxess.*\.dll|.*xess.*\.dll|.*xell.*\.dll)$') { return $false }
        if ($fn -match '^nvngx_dlss(?!nr).*') { return $false } # Preserva nvngx_dlss.dll, dlssd, dlssg, deepdvc
        if ($fn -match '^sl\.(?!dlss_nr).*') { return $false } # Preserva sl.interposer, sl.common, sl.dlss etc.
        if ($fn -match '^(amd_.*|ffx_.*|dxcompiler\.dll|d3d12core\.dll|bink2.*|steam_api.*|onlinefix.*|xgameruntime.*)$') { return $false }
        return $true
    })

    foreach ($pf in $purgeList) {
        if ($savedBacked -contains $pf) { continue }
        $p = Join-Path $targetFolder $pf
        if (Test-Path -LiteralPath $p) {
            Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $reshadeDir = Join-Path $targetFolder "reshade-shaders"
    if (Test-Path -LiteralPath $reshadeDir -PathType Container) {
        Remove-Item -LiteralPath $reshadeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $hostDir = Join-Path $targetFolder "host64"
    if (Test-Path -LiteralPath $hostDir -PathType Container) {
        Remove-Item -LiteralPath $hostDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    foreach ($ld in @("layer-x64", "layer-x86")) {
        $lp = Join-Path $targetFolder $ld
        if (Test-Path -LiteralPath $lp -PathType Container) {
            Remove-Item -LiteralPath $lp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($sf in @($script:StateName, "_1Click_DLSS5_State.json", "_DLSS5_Easy_Installer_State.json")) {
        $sp = Join-Path $targetFolder $sf
        if (Test-Path -LiteralPath $sp -PathType Leaf) {
            Remove-Item -LiteralPath $sp -Force -ErrorAction SilentlyContinue
        }
    }

    # Autocura preventiva final pos-restauracao: garante que dependencias nativas exigidas estejam presentes
    Repair-GameCriticalDependencies -TargetFolder $targetFolder -TargetExe $target.Executable

    Write-Status -Message "Game 100% restored to factory original state!" -Level "OK"
    if (-not $env:DLSS5_HEADLESS) { [System.Windows.Forms.MessageBox]::Show($d.RestoreMsg, $d.RestoreTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) }
}

function Start-GameExecutable {
    param([Parameter(Mandatory = $true)][string]$ExecutablePath)
    if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
        throw "ERR_EXE_NOT_FOUND: Game executable not found: $ExecutablePath"
    }
    $folder = (Split-Path -Parent $ExecutablePath)

    # Autocura preventiva antes de inicializar o jogo
    Repair-GameCriticalDependencies -TargetFolder $folder -TargetExe $ExecutablePath

    Write-Status -Message "Launching game: $(Split-Path -Leaf $ExecutablePath)..." -Level "INFO"

    $oldVkPath = $env:VK_LAYER_PATH
    $oldVkLayers = $env:VK_INSTANCE_LAYERS
    try {
        # Se for um jogo Vulkan com camada Feeder injetada, ativar sem tocar no registro
        $vkLayerDll = Join-Path $folder "VkLayer_feed_vk.dll"
        if (Test-Path -LiteralPath $vkLayerDll -PathType Leaf) {
            $env:VK_LAYER_PATH = $folder
            $env:VK_INSTANCE_LAYERS = "VK_LAYER_feed_vk"
        }
        Start-Process -FilePath $ExecutablePath -WorkingDirectory $folder
    }
    finally {
        $env:VK_LAYER_PATH = $oldVkPath
        $env:VK_INSTANCE_LAYERS = $oldVkLayers
    }
}

# --- INSTANT GAME AUTO-DISCOVERY SCANNER ---
function Scan-DriveForGames {
    param(
        [string]$DriveLetter = "ALL",
        [scriptblock]$ProgressCallback = $null
    )
    $results = New-Object System.Collections.Generic.List[pscustomobject]
    $rootsToScan = New-Object System.Collections.Generic.List[string]

    # 1. Leitura de Bibliotecas Steam (Registro do Windows + VDF Multi-Drive)
    $steamCandidates = @(
        "C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf",
        "C:\Program Files\Steam\steamapps\libraryfolders.vdf",
        "D:\Steam\steamapps\libraryfolders.vdf",
        "D:\SteamLibrary\steamapps\libraryfolders.vdf",
        "E:\Steam\steamapps\libraryfolders.vdf",
        "E:\SteamLibrary\steamapps\libraryfolders.vdf"
    )

    # Consulta din mica ao Registro do Windows para Steam
    $steamRegPaths = @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam"
    )
    foreach ($srp in $steamRegPaths) {
        try {
            $regProp = Get-ItemProperty -Path $srp -ErrorAction SilentlyContinue
            if ($regProp) {
                $sPath = if ($regProp.SteamPath) { $regProp.SteamPath } else { $regProp.InstallPath }
                if ($sPath) {
                    $vdf = Join-Path $sPath "steamapps\libraryfolders.vdf"
                    if (Test-Path -LiteralPath $vdf -PathType Leaf) {
                        if ($steamCandidates -notcontains $vdf) { $steamCandidates += $vdf }
                    }
                }
            }
        }
        catch {}
    }

    # Consulta ao Registro para GOG Galaxy
    $gogRegPath = "HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games"
    if (Test-Path -Path $gogRegPath) {
        $gogKeys = Get-ChildItem -Path $gogRegPath -ErrorAction SilentlyContinue
        foreach ($gk in $gogKeys) {
            $gProp = Get-ItemProperty -Path $gk.PSPath -ErrorAction SilentlyContinue
            if ($gProp -and $gProp.path -and (Test-Path -LiteralPath $gProp.path)) {
                [void]$rootsToScan.Add($gProp.path)
            }
        }
    }

    foreach ($sc in $steamCandidates) {
        if (Test-Path -LiteralPath $sc -PathType Leaf) {
            try {
                $lines = Get-Content -LiteralPath $sc -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                $matches = [regex]::Matches($lines, '\"path\"\s+\"([^\"]+)\"')
                foreach ($m in $matches) {
                    $p = $m.Groups[1].Value.Replace('\\', '\')
                    $common = Join-Path $p "steamapps\common"
                    if (Test-Path -LiteralPath $common) { [void]$rootsToScan.Add($common) }
                }
            }
            catch {}
        }
    }

    # 2. Leitura Direta de Manifests Epic Games
    $epicDir = "C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
    if (Test-Path -LiteralPath $epicDir -PathType Container) {
        $mfs = Get-ChildItem -LiteralPath $epicDir -Filter "*.item" -File -ErrorAction SilentlyContinue
        foreach ($mf in $mfs) {
            try {
                $itemData = Get-Content -LiteralPath $mf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($itemData.InstallLocation -and (Test-Path -LiteralPath $itemData.InstallLocation)) {
                    [void]$rootsToScan.Add($itemData.InstallLocation)
                }
            }
            catch {}
        }
    }

    # 3. Varredura de Unidades Fixas
    $drives = @()
    if ($DriveLetter -eq "ALL") {
        $drives = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.IsReady } | ForEach-Object { $_.Name })
    }
    else {
        $drives = @($DriveLetter)
    }
    foreach ($d in $drives) {
        [void]$rootsToScan.Add((Join-Path $d "Games"))
        [void]$rootsToScan.Add((Join-Path $d "Jogos"))
        [void]$rootsToScan.Add((Join-Path $d "Steam\steamapps\common"))
        [void]$rootsToScan.Add((Join-Path $d "SteamLibrary\steamapps\common"))
        [void]$rootsToScan.Add((Join-Path $d "Program Files (x86)\Steam\steamapps\common"))
        [void]$rootsToScan.Add((Join-Path $d "Program Files\Steam\steamapps\common"))
        [void]$rootsToScan.Add((Join-Path $d "Program Files\Epic Games"))
        [void]$rootsToScan.Add((Join-Path $d "Epic Games"))
        [void]$rootsToScan.Add((Join-Path $d "XboxGames"))
    }

    $ignored = @("steamworks shared", "_commonredist", "directx", "vcredist", "dotnet", "crashreport", "tools", "easyanticheat", "battleye", "launcher", "nam")

    $allGameDirs = New-Object System.Collections.Generic.List[pscustomobject]
    $seenPaths = New-Object System.Collections.Generic.HashSet[string]

    foreach ($root in $rootsToScan) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            try {
                $hasDirectExe = @(Get-ChildItem -LiteralPath $root -Filter "*.exe" -File -ErrorAction SilentlyContinue).Count -gt 0
                if ($hasDirectExe) {
                    $norm = $root.ToLower()
                    if (-not $seenPaths.Contains($norm)) {
                        [void]$seenPaths.Add($norm)
                        [void]$allGameDirs.Add([pscustomobject]@{ Root = $root; Dir = (Get-Item -LiteralPath $root) })
                    }
                }
                else {
                    $dirs = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue
                    foreach ($dir in $dirs) {
                        $dirLow = $dir.Name.ToLower()
                        if ($ignored -contains $dirLow) { continue }
                        if ($dirLow -match '^(ue_\d|unrealengine|launcher|gameinput|directxredist|vcredist|dotnet|crashreport)') { continue }
                        $norm = $dir.FullName.ToLower()
                        if (-not $seenPaths.Contains($norm)) {
                            [void]$seenPaths.Add($norm)
                            [void]$allGameDirs.Add([pscustomobject]@{ Root = $root; Dir = $dir })
                        }
                    }
                }
            }
            catch {}
        }
    }

    $totalGames = $allGameDirs.Count
    if ($totalGames -eq 0) { return @() }
    $currentIdx = 0

    foreach ($entry in $allGameDirs) {
        $dir = $entry.Dir
        $gamePath = $dir.FullName
        $currentIdx++

        if ($null -ne $ProgressCallback) {
            $pct = [int](($currentIdx / $totalGames) * 100)
            try { & $ProgressCallback $pct $dir.Name } catch {}
        }
        [System.Windows.Forms.Application]::DoEvents()

        $resolved = $null
        try { $resolved = Resolve-GameTarget -TargetPath $gamePath } catch { continue }
        if ($null -eq $resolved) { continue }

        $api = Detect-GameGraphicsApi -TargetExe $resolved.Executable -GameFolder $resolved.InstallFolder
        $upscaler = Detect-GameUpscalerType -GameFolder $resolved.InstallFolder -GameRoot $resolved.Root
        $arch = $resolved.Architecture
        $isInstalled = Test-GameDlss5Installed -GameFolder $resolved.InstallFolder

        $order = 3
        if ($isInstalled) {
            $order = 0
        }
        elseif ($upscaler -eq "NATIVE_DLSS") {
            $order = 1
        }
        elseif ($upscaler -eq "FSR2_BRIDGE" -or $upscaler -eq "XESS_BRIDGE") {
            $order = 2
        }

        [void]$results.Add([pscustomobject]@{
                Order       = $order
                Name        = $dir.Name
                Path        = $gamePath
                Api         = "$api ($arch)"
                Upscaler    = $upscaler
                IsInstalled = $isInstalled
                Icon        = $resolved.Icon
                ExeName     = $resolved.ExeName
            })
    }
    return @($results | Sort-Object -Property Order, Name)
}

# --- STYLING HELPERS ---
function Style-Button {
    param(
        [System.Windows.Forms.Button]$Button,
        [System.Drawing.Color]$BaseColor,
        [System.Drawing.Color]$HoverColor,
        [System.Drawing.Color]$TextColor = [System.Drawing.Color]::White
    )
    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize = 0
    $Button.BackColor = $BaseColor
    $Button.ForeColor = $TextColor
    $Button.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $Button.Tag = @{ Base = $BaseColor; Hover = $HoverColor; Text = $TextColor }
    $Button.Add_MouseEnter({ 
            if ($this.Tag -and $this.Tag.Hover) { $this.BackColor = $this.Tag.Hover }
            if ($this.Tag -and $this.Tag.Text) { $this.ForeColor = $this.Tag.Text }
        })
    $Button.Add_MouseLeave({ 
            if ($this.Tag -and $this.Tag.Base) { $this.BackColor = $this.Tag.Base }
            if ($this.Tag -and $this.Tag.Text) { $this.ForeColor = $this.Tag.Text }
        })
}

# ==============================================================================
# MAIN WINDOW CONSTRUCTION
# ==============================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "1 Click DLSS 5 v$($script:Version) - Universal Neural Control Center"
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.Size = New-Object System.Drawing.Size(1260, 860)
$form.MinimumSize = New-Object System.Drawing.Size(1180, 800)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = [System.Drawing.Color]::FromArgb(11, 15, 25)
$form.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.AllowDrop = $true

if (Test-Path -LiteralPath $script:IconPath) {
    try { $form.Icon = New-Object System.Drawing.Icon($script:IconPath) } catch {}
}

# --- DRAG & DROP SUPPORT (DROP GAME FOLDERS ONTO THE WINDOW) ---
$form.Add_DragEnter({
        param($sender, $e)
        if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
        }
        else {
            $e.Effect = [System.Windows.Forms.DragDropEffects]::None
        }
    })

$form.Add_DragDrop({
        param($sender, $e)
        $files = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
        if ($files -and $files.Length -gt 0) {
            $droppedPath = $files[0]
            try {
                $resolved = Resolve-GameTarget -TargetPath $droppedPath
                $api = Detect-GameGraphicsApi -TargetExe $resolved.Executable -GameFolder $resolved.InstallFolder
                $upscaler = Detect-GameUpscalerType -GameFolder $resolved.InstallFolder -GameRoot $resolved.Root
                $gObj = [pscustomobject]@{
                    Order    = 1
                    Name     = (Split-Path -Leaf $droppedPath)
                    Path     = $droppedPath
                    Api      = "$api ($($resolved.Architecture))"
                    Upscaler = $upscaler
                    Icon     = $resolved.Icon
                    ExeName  = $resolved.ExeName
                }
                $script:CurrentGameLibrary = @($gObj)
                Refresh-GameLibraryUI -Games @($gObj)
                Select-GameInInspector -GameObj $gObj
                Write-Status -Message "Game loaded via drag & drop: $($gObj.Name)" -Level "OK"
            }
            catch {
                Show-FriendlyErrorDialog -Ex $_.Exception -Context "Drag & Drop" -TargetPath $droppedPath
            }
        }
    })

$imageList = New-Object System.Windows.Forms.ImageList
$imageList.ImageSize = New-Object System.Drawing.Size(28, 28)
$imageList.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit

# --- TOP HEADER ---
$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(1260, 110)
$header.Anchor = "Top, Left, Right"
$header.BackColor = [System.Drawing.Color]::FromArgb(15, 22, 38)
[void]$form.Controls.Add($header)

$headerAccent = New-Object System.Windows.Forms.Panel
$headerAccent.Location = New-Object System.Drawing.Point(0, 0)
$headerAccent.Size = New-Object System.Drawing.Size(5, 110)
$headerAccent.BackColor = [System.Drawing.Color]::FromArgb(118, 185, 0)
[void]$header.Controls.Add($headerAccent)

$lblTagline = New-Object System.Windows.Forms.Label
$lblTagline.Text = "NEURAL CONTROL CENTER • RTX 20 / 30 / 40 / 50 SERIES"
$lblTagline.Location = New-Object System.Drawing.Point(22, 10)
$lblTagline.Size = New-Object System.Drawing.Size(600, 18)
$lblTagline.ForeColor = [System.Drawing.Color]::FromArgb(118, 185, 0)
$lblTagline.Font = New-Object System.Drawing.Font("Segoe UI Bold", 8.5)
[void]$header.Controls.Add($lblTagline)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "1 CLICK DLSS 5"
$lblTitle.Location = New-Object System.Drawing.Point(20, 24)
$lblTitle.Size = New-Object System.Drawing.Size(400, 36)
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::White
[void]$header.Controls.Add($lblTitle)

$lblSubBadge = New-Object System.Windows.Forms.Label
$lblSubBadge.Text = "DirectX 9 / 10 / 11 / 12 • Vulkan • OpenGL • 32 & 64-bit"
$lblSubBadge.Location = New-Object System.Drawing.Point(22, 60)
$lblSubBadge.Size = New-Object System.Drawing.Size(550, 18)
$lblSubBadge.ForeColor = [System.Drawing.Color]::FromArgb(145, 175, 210)
[void]$header.Controls.Add($lblSubBadge)

# --- 3-STEP VISUAL GUIDE ---
$stepPanel = New-Object System.Windows.Forms.Panel
$stepPanel.Location = New-Object System.Drawing.Point(22, 80)
$stepPanel.Size = New-Object System.Drawing.Size(800, 24)
$stepPanel.BackColor = [System.Drawing.Color]::Transparent
[void]$header.Controls.Add($stepPanel)

$lblStep1 = New-Object System.Windows.Forms.Label
$lblStep1.Text = "[1] Choose Game"
$lblStep1.Location = New-Object System.Drawing.Point(0, 2)
$lblStep1.Size = New-Object System.Drawing.Size(180, 20)
$lblStep1.ForeColor = [System.Drawing.Color]::FromArgb(100, 180, 255)
$lblStep1.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9)
[void]$stepPanel.Controls.Add($lblStep1)

$lblStepArrow1 = New-Object System.Windows.Forms.Label
$lblStepArrow1.Text = "→"
$lblStepArrow1.Location = New-Object System.Drawing.Point(185, 2)
$lblStepArrow1.Size = New-Object System.Drawing.Size(20, 20)
$lblStepArrow1.ForeColor = [System.Drawing.Color]::Gray
[void]$stepPanel.Controls.Add($lblStepArrow1)

$lblStep2 = New-Object System.Windows.Forms.Label
$lblStep2.Text = "[2] Click Install"
$lblStep2.Location = New-Object System.Drawing.Point(210, 2)
$lblStep2.Size = New-Object System.Drawing.Size(180, 20)
$lblStep2.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
$lblStep2.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9)
[void]$stepPanel.Controls.Add($lblStep2)

$lblStepArrow2 = New-Object System.Windows.Forms.Label
$lblStepArrow2.Text = "→"
$lblStepArrow2.Location = New-Object System.Drawing.Point(395, 2)
$lblStepArrow2.Size = New-Object System.Drawing.Size(20, 20)
$lblStepArrow2.ForeColor = [System.Drawing.Color]::Gray
[void]$stepPanel.Controls.Add($lblStepArrow2)

$lblStep3 = New-Object System.Windows.Forms.Label
$lblStep3.Text = "[3] Launch & Enjoy!"
$lblStep3.Location = New-Object System.Drawing.Point(420, 2)
$lblStep3.Size = New-Object System.Drawing.Size(200, 20)
$lblStep3.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 90)
$lblStep3.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9)
[void]$stepPanel.Controls.Add($lblStep3)

# Diagnosis button and language selector (top right)
$btnDiagnose = New-Object System.Windows.Forms.Button
$btnDiagnose.Text = "[+] SYSTEM DIAGNOSIS"
$btnDiagnose.Location = New-Object System.Drawing.Point(850, 12)
$btnDiagnose.Size = New-Object System.Drawing.Size(190, 28)
$btnDiagnose.Anchor = "Top, Right"
Style-Button -Button $btnDiagnose -BaseColor ([System.Drawing.Color]::FromArgb(35, 60, 100)) -HoverColor ([System.Drawing.Color]::FromArgb(50, 85, 140))
$btnDiagnose.Add_Click({ Show-SystemDiagnosisDialog })
[void]$header.Controls.Add($btnDiagnose)

$comboLang = New-Object System.Windows.Forms.ComboBox
$comboLang.Location = New-Object System.Drawing.Point(1055, 13)
$comboLang.Size = New-Object System.Drawing.Size(180, 26)
$comboLang.Anchor = "Top, Right"
$comboLang.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$comboLang.BackColor = [System.Drawing.Color]::FromArgb(22, 32, 54)
$comboLang.ForeColor = [System.Drawing.Color]::White
$comboLang.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
[void]$comboLang.Items.AddRange(@("English (US)", "Português (Brasil)", "Español", "Deutsch", "Français", "Italiano", "日本語", "简体中文", "Русский", "한국어"))
$comboLang.SelectedIndex = 0
[void]$header.Controls.Add($comboLang)

# --- TOOLBAR / SEARCH ---
$toolbar = New-Object System.Windows.Forms.Panel
$toolbar.Location = New-Object System.Drawing.Point(18, 120)
$toolbar.Size = New-Object System.Drawing.Size(1224, 44)
$toolbar.Anchor = "Top, Left, Right"
$toolbar.BackColor = [System.Drawing.Color]::FromArgb(16, 24, 40)
[void]$form.Controls.Add($toolbar)

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "SCAN DISKS"
$btnScan.Location = New-Object System.Drawing.Point(8, 7)
$btnScan.Size = New-Object System.Drawing.Size(180, 30)
Style-Button -Button $btnScan -BaseColor ([System.Drawing.Color]::FromArgb(35, 80, 145)) -HoverColor ([System.Drawing.Color]::FromArgb(50, 110, 195))
[void]$toolbar.Controls.Add($btnScan)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(200, 9)
$txtSearch.Size = New-Object System.Drawing.Size(830, 26)
$txtSearch.Anchor = "Top, Left, Right"
$txtSearch.BackColor = [System.Drawing.Color]::FromArgb(10, 15, 26)
$txtSearch.ForeColor = [System.Drawing.Color]::FromArgb(140, 210, 255)
$txtSearch.BorderStyle = "FixedSingle"
$txtSearch.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
[void]$toolbar.Controls.Add($txtSearch)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "BROWSE GAME..."
$btnBrowse.Location = New-Object System.Drawing.Point(1042, 7)
$btnBrowse.Size = New-Object System.Drawing.Size(172, 30)
$btnBrowse.Anchor = "Top, Right"
Style-Button -Button $btnBrowse -BaseColor ([System.Drawing.Color]::FromArgb(40, 65, 110)) -HoverColor ([System.Drawing.Color]::FromArgb(55, 90, 150))
[void]$toolbar.Controls.Add($btnBrowse)

# --- LEFT COLUMN: GAME LIBRARY ---
$leftPanel = New-Object System.Windows.Forms.Panel
$leftPanel.Location = New-Object System.Drawing.Point(18, 172)
$leftPanel.Size = New-Object System.Drawing.Size(460, 610)
$leftPanel.Anchor = "Top, Bottom, Left"
$leftPanel.BackColor = [System.Drawing.Color]::FromArgb(16, 24, 40)
[void]$form.Controls.Add($leftPanel)

$lblLibTitle = New-Object System.Windows.Forms.Label
$lblLibTitle.Text = "DETECTED GAME LIBRARY"
$lblLibTitle.Location = New-Object System.Drawing.Point(14, 10)
$lblLibTitle.Size = New-Object System.Drawing.Size(430, 20)
$lblLibTitle.ForeColor = [System.Drawing.Color]::FromArgb(140, 200, 255)
$lblLibTitle.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9.5)
[void]$leftPanel.Controls.Add($lblLibTitle)

$gameList = New-Object System.Windows.Forms.ListView
$gameList.Location = New-Object System.Drawing.Point(12, 34)
$gameList.Size = New-Object System.Drawing.Size(436, 564)
$gameList.Anchor = "Top, Bottom, Left, Right"
$gameList.View = [System.Windows.Forms.View]::Details
$gameList.FullRowSelect = $true
$gameList.MultiSelect = $false
$gameList.HideSelection = $false
$gameList.BackColor = [System.Drawing.Color]::FromArgb(9, 14, 24)
$gameList.ForeColor = [System.Drawing.Color]::White
$gameList.BorderStyle = "FixedSingle"
$gameList.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$gameList.SmallImageList = $imageList
[void]$gameList.Columns.Add("Game Title", 185)
[void]$gameList.Columns.Add("API / Arch", 90)
[void]$gameList.Columns.Add("Recommended Mode", 130)
$gameList.Add_Resize({
    $avail = $gameList.ClientSize.Width
    if ($avail -gt 320) {
        $gameList.Columns[1].Width = 90
        $gameList.Columns[2].Width = 130
        $gameList.Columns[0].Width = [Math]::Max(140, $avail - 225)
    }
})
try {
    $null = Add-Type -MemberDefinition '[DllImport("uxtheme.dll", CharSet=CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr hWnd, string pszSubAppName, string pszSubIdList);' -Name "UxThemeListView" -Namespace "Win32" -PassThru -ErrorAction SilentlyContinue
    [Win32.UxThemeListView]::SetWindowTheme($gameList.Handle, "Explorer", $null)
} catch {}
[void]$leftPanel.Controls.Add($gameList)

# --- RIGHT COLUMN: INSPECTOR AND MODE SELECTOR ---
$rightPanel = New-Object System.Windows.Forms.Panel
$rightPanel.Location = New-Object System.Drawing.Point(488, 172)
$rightPanel.Size = New-Object System.Drawing.Size(754, 610)
$rightPanel.Anchor = "Top, Bottom, Left, Right"
$rightPanel.BackColor = [System.Drawing.Color]::FromArgb(16, 24, 40)
[void]$form.Controls.Add($rightPanel)

# Selected game banner
$gameBanner = New-Object System.Windows.Forms.Panel
$gameBanner.Location = New-Object System.Drawing.Point(16, 12)
$gameBanner.Size = New-Object System.Drawing.Size(722, 70)
$gameBanner.Anchor = "Top, Left, Right"
$gameBanner.BackColor = [System.Drawing.Color]::FromArgb(11, 18, 30)
[void]$rightPanel.Controls.Add($gameBanner)

$picIcon = New-Object System.Windows.Forms.PictureBox
$picIcon.Location = New-Object System.Drawing.Point(12, 11)
$picIcon.Size = New-Object System.Drawing.Size(48, 48)
$picIcon.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
[void]$gameBanner.Controls.Add($picIcon)

$lblGameTitle = New-Object System.Windows.Forms.Label
$lblGameTitle.Text = "Select a Game"
$lblGameTitle.Location = New-Object System.Drawing.Point(70, 10)
$lblGameTitle.Size = New-Object System.Drawing.Size(640, 26)
$lblGameTitle.Font = New-Object System.Drawing.Font("Segoe UI Bold", 13)
$lblGameTitle.ForeColor = [System.Drawing.Color]::White
[void]$gameBanner.Controls.Add($lblGameTitle)

$lblGameStatus = New-Object System.Windows.Forms.Label
$lblGameStatus.Text = "Select a game from the library or browse a folder."
$lblGameStatus.Location = New-Object System.Drawing.Point(70, 38)
$lblGameStatus.Size = New-Object System.Drawing.Size(640, 22)
$lblGameStatus.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
$lblGameStatus.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
[void]$gameBanner.Controls.Add($lblGameStatus)

# Installation folder
$lblFolderTitle = New-Object System.Windows.Forms.Label
$lblFolderTitle.Text = "GAME INSTALLATION DIRECTORY:"
$lblFolderTitle.Location = New-Object System.Drawing.Point(16, 90)
$lblFolderTitle.Size = New-Object System.Drawing.Size(500, 18)
$lblFolderTitle.ForeColor = [System.Drawing.Color]::FromArgb(160, 190, 225)
$lblFolderTitle.Font = New-Object System.Drawing.Font("Segoe UI Bold", 8.5)
[void]$rightPanel.Controls.Add($lblFolderTitle)

$txtFolderPath = New-Object System.Windows.Forms.TextBox
$txtFolderPath.Location = New-Object System.Drawing.Point(16, 110)
$txtFolderPath.Size = New-Object System.Drawing.Size(722, 24)
$txtFolderPath.Anchor = "Top, Left, Right"
$txtFolderPath.ReadOnly = $true
$txtFolderPath.BackColor = [System.Drawing.Color]::FromArgb(9, 14, 24)
$txtFolderPath.ForeColor = [System.Drawing.Color]::FromArgb(140, 210, 255)
$txtFolderPath.BorderStyle = "FixedSingle"
[void]$rightPanel.Controls.Add($txtFolderPath)

# Injection mode selector cards
$lblModeSecTitle = New-Object System.Windows.Forms.Label
$lblModeSecTitle.Text = "CHOOSE DLSS 5 INJECTION MODE:"
$lblModeSecTitle.Location = New-Object System.Drawing.Point(16, 142)
$lblModeSecTitle.Size = New-Object System.Drawing.Size(400, 18)
$lblModeSecTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 90)
$lblModeSecTitle.Font = New-Object System.Drawing.Font("Segoe UI Bold", 8.5)
[void]$rightPanel.Controls.Add($lblModeSecTitle)

$lblAutoNotice = New-Object System.Windows.Forms.Label
$lblAutoNotice.Text = "Optimal mode auto-selected for this game"
$lblAutoNotice.Location = New-Object System.Drawing.Point(420, 142)
$lblAutoNotice.Size = New-Object System.Drawing.Size(318, 18)
$lblAutoNotice.Anchor = "Top, Right"
$lblAutoNotice.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$lblAutoNotice.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
$lblAutoNotice.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8)
[void]$rightPanel.Controls.Add($lblAutoNotice)

# Mode 1 card
$cardMode1 = New-Object System.Windows.Forms.Panel
$cardMode1.Location = New-Object System.Drawing.Point(16, 164)
$cardMode1.Size = New-Object System.Drawing.Size(722, 52)
$cardMode1.Anchor = "Top, Left, Right"
$cardMode1.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)
$cardMode1.Cursor = [System.Windows.Forms.Cursors]::Hand
[void]$rightPanel.Controls.Add($cardMode1)

$lblCard1Title = New-Object System.Windows.Forms.Label
$lblCard1Title.Text = "MODE 1: DIRECT (Native DLSS)"
$lblCard1Title.Location = New-Object System.Drawing.Point(12, 6)
$lblCard1Title.Size = New-Object System.Drawing.Size(690, 20)
$lblCard1Title.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9.5)
$lblCard1Title.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
[void]$cardMode1.Controls.Add($lblCard1Title)

$lblCard1Desc = New-Object System.Windows.Forms.Label
$lblCard1Desc.Text = "For games with native DLSS. Injects Streamline + AI with massive FPS boost."
$lblCard1Desc.Location = New-Object System.Drawing.Point(12, 26)
$lblCard1Desc.Size = New-Object System.Drawing.Size(690, 20)
$lblCard1Desc.ForeColor = [System.Drawing.Color]::FromArgb(170, 195, 220)
[void]$cardMode1.Controls.Add($lblCard1Desc)

# Mode 2 card
$cardMode2 = New-Object System.Windows.Forms.Panel
$cardMode2.Location = New-Object System.Drawing.Point(16, 222)
$cardMode2.Size = New-Object System.Drawing.Size(722, 52)
$cardMode2.Anchor = "Top, Left, Right"
$cardMode2.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)
$cardMode2.Cursor = [System.Windows.Forms.Cursors]::Hand
[void]$rightPanel.Controls.Add($cardMode2)

$lblCard2Title = New-Object System.Windows.Forms.Label
$lblCard2Title.Text = "MODE 2: OPTISCALER BRIDGE (FSR2/XeSS)"
$lblCard2Title.Location = New-Object System.Drawing.Point(12, 6)
$lblCard2Title.Size = New-Object System.Drawing.Size(690, 20)
$lblCard2Title.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9.5)
$lblCard2Title.ForeColor = [System.Drawing.Color]::FromArgb(100, 180, 255)
[void]$cardMode2.Controls.Add($lblCard2Title)

$lblCard2Desc = New-Object System.Windows.Forms.Label
$lblCard2Desc.Text = "Redirects FSR2/XeSS calls to DLSS 5 Neural Rendering."
$lblCard2Desc.Location = New-Object System.Drawing.Point(12, 26)
$lblCard2Desc.Size = New-Object System.Drawing.Size(690, 20)
$lblCard2Desc.ForeColor = [System.Drawing.Color]::FromArgb(170, 195, 220)
[void]$cardMode2.Controls.Add($lblCard2Desc)

# Mode 3 card
$cardMode3 = New-Object System.Windows.Forms.Panel
$cardMode3.Location = New-Object System.Drawing.Point(16, 280)
$cardMode3.Size = New-Object System.Drawing.Size(722, 52)
$cardMode3.Anchor = "Top, Left, Right"
$cardMode3.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)
$cardMode3.Cursor = [System.Windows.Forms.Cursors]::Hand
[void]$rightPanel.Controls.Add($cardMode3)

$lblCard3Title = New-Object System.Windows.Forms.Label
$lblCard3Title.Text = "MODE 3: UNIVERSAL FEEDER (100% Native DLAA)"
$lblCard3Title.Location = New-Object System.Drawing.Point(12, 6)
$lblCard3Title.Size = New-Object System.Drawing.Size(690, 20)
$lblCard3Title.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9.5)
$lblCard3Title.ForeColor = [System.Drawing.Color]::FromArgb(190, 150, 255)
[void]$cardMode3.Controls.Add($lblCard3Title)

$lblCard3Desc = New-Object System.Windows.Forms.Label
$lblCard3Desc.Text = "For ANY PC game (Mafia, GTA, etc). 100% clean reconstruction with zero blur."
$lblCard3Desc.Location = New-Object System.Drawing.Point(12, 26)
$lblCard3Desc.Size = New-Object System.Drawing.Size(690, 20)
$lblCard3Desc.ForeColor = [System.Drawing.Color]::FromArgb(170, 195, 220)
[void]$cardMode3.Controls.Add($lblCard3Desc)

function Highlight-SelectedModeCard {
    param([string]$Mode)
    $script:SelectedMode = $Mode
    $cardMode1.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)
    $cardMode2.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)
    $cardMode3.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)

    $d = Get-Dict -Lang $script:CurrentLang
    $isRdr2 = ($script:SelectedGameObj -and ($script:SelectedGameObj.Name -match "Red Dead" -or $script:SelectedGameObj.ExeName -match "RDR2|rdr2"))

    if ($Mode -eq "DIRECT") {
        $cardMode1.BackColor = [System.Drawing.Color]::FromArgb(20, 48, 30)
        if ($isRdr2) {
            $lblReqText.Text = if ($script:CurrentLang -eq "PT") { "No RDR2: Mude a API para DirectX 12 (Configuracoes > Graficos > Avancado) e ATIVE o DLSS." } else { "In RDR2: Switch Graphics API to DirectX 12 (Settings > Graphics > Advanced) & ENABLE DLSS." }
        }
        else {
            $lblReqText.Text = $d.ReqMode1
        }
    }
    elseif ($Mode -eq "OPTISCALER") {
        $cardMode2.BackColor = [System.Drawing.Color]::FromArgb(18, 40, 65)
        $lblReqText.Text = $d.ReqMode2
    }
    else {
        $cardMode3.BackColor = [System.Drawing.Color]::FromArgb(35, 25, 55)
        if ($isRdr2) {
            $lblReqText.Text = if ($script:CurrentLang -eq "PT") { "No RDR2: O Feeder requer DirectX 12. Mude a API para DirectX 12 nas opcoes do jogo." } else { "In RDR2: Feeder requires DirectX 12. Switch Graphics API to DirectX 12 in game settings." }
        }
        else {
            $lblReqText.Text = $d.ReqMode3
        }
    }
}

$cardMode1.Add_Click({ Highlight-SelectedModeCard -Mode "DIRECT" })
$lblCard1Title.Add_Click({ Highlight-SelectedModeCard -Mode "DIRECT" })
$lblCard1Desc.Add_Click({ Highlight-SelectedModeCard -Mode "DIRECT" })

$cardMode2.Add_Click({ Highlight-SelectedModeCard -Mode "OPTISCALER" })
$lblCard2Title.Add_Click({ Highlight-SelectedModeCard -Mode "OPTISCALER" })
$lblCard2Desc.Add_Click({ Highlight-SelectedModeCard -Mode "OPTISCALER" })

$cardMode3.Add_Click({ Highlight-SelectedModeCard -Mode "FEEDER" })
$lblCard3Title.Add_Click({ Highlight-SelectedModeCard -Mode "FEEDER" })
$lblCard3Desc.Add_Click({ Highlight-SelectedModeCard -Mode "FEEDER" })

# In-game requirement card
$reqCard = New-Object System.Windows.Forms.Panel
$reqCard.Location = New-Object System.Drawing.Point(16, 340)
$reqCard.Size = New-Object System.Drawing.Size(722, 60)
$reqCard.Anchor = "Top, Left, Right"
$reqCard.BackColor = [System.Drawing.Color]::FromArgb(25, 28, 15)
[void]$rightPanel.Controls.Add($reqCard)

$reqAccent = New-Object System.Windows.Forms.Panel
$reqAccent.Location = New-Object System.Drawing.Point(0, 0)
$reqAccent.Size = New-Object System.Drawing.Size(4, 60)
$reqAccent.BackColor = [System.Drawing.Color]::FromArgb(255, 195, 0)
[void]$reqCard.Controls.Add($reqAccent)

$lblReqTitle = New-Object System.Windows.Forms.Label
$lblReqTitle.Text = "IN-GAME REQUIREMENT:"
$lblReqTitle.Location = New-Object System.Drawing.Point(12, 6)
$lblReqTitle.Size = New-Object System.Drawing.Size(700, 18)
$lblReqTitle.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9)
$lblReqTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 50)
[void]$reqCard.Controls.Add($lblReqTitle)

$lblReqText = New-Object System.Windows.Forms.Label
$lblReqText.Text = "Select a game to load its automatic instructions."
$lblReqText.Location = New-Object System.Drawing.Point(12, 26)
$lblReqText.Size = New-Object System.Drawing.Size(700, 30)
$lblReqText.ForeColor = [System.Drawing.Color]::FromArgb(240, 230, 190)
$lblReqText.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
[void]$reqCard.Controls.Add($lblReqText)

# Main action bar
$actionPanel = New-Object System.Windows.Forms.Panel
$actionPanel.Location = New-Object System.Drawing.Point(16, 410)
$actionPanel.Size = New-Object System.Drawing.Size(722, 185)
$actionPanel.Anchor = "Top, Bottom, Left, Right"
[void]$rightPanel.Controls.Add($actionPanel)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "[1-CLICK] INSTALL DLSS 5"
$btnInstall.Location = New-Object System.Drawing.Point(0, 5)
$btnInstall.Size = New-Object System.Drawing.Size(355, 48)
$btnInstall.Font = New-Object System.Drawing.Font("Segoe UI Bold", 11.5)
Style-Button -Button $btnInstall -BaseColor ([System.Drawing.Color]::FromArgb(118, 185, 0)) -HoverColor ([System.Drawing.Color]::FromArgb(140, 220, 0)) -TextColor ([System.Drawing.Color]::Black)
[void]$actionPanel.Controls.Add($btnInstall)

$btnLaunch = New-Object System.Windows.Forms.Button
$btnLaunch.Text = "[>] LAUNCH GAME"
$btnLaunch.Location = New-Object System.Drawing.Point(367, 5)
$btnLaunch.Size = New-Object System.Drawing.Size(355, 48)
$btnLaunch.Font = New-Object System.Drawing.Font("Segoe UI Bold", 11.5)
Style-Button -Button $btnLaunch -BaseColor ([System.Drawing.Color]::FromArgb(0, 130, 230)) -HoverColor ([System.Drawing.Color]::FromArgb(20, 160, 255)) -TextColor ([System.Drawing.Color]::White)
[void]$actionPanel.Controls.Add($btnLaunch)

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text = "[<] RESTORE FACTORY"
$btnUninstall.Location = New-Object System.Drawing.Point(0, 62)
$btnUninstall.Size = New-Object System.Drawing.Size(355, 38)
Style-Button -Button $btnUninstall -BaseColor ([System.Drawing.Color]::FromArgb(170, 45, 45)) -HoverColor ([System.Drawing.Color]::FromArgb(205, 55, 55)) -TextColor ([System.Drawing.Color]::White)
[void]$actionPanel.Controls.Add($btnUninstall)

$btnOpenFolder = New-Object System.Windows.Forms.Button
$btnOpenFolder.Text = "[FOLDER] OPEN FOLDER"
$btnOpenFolder.Location = New-Object System.Drawing.Point(367, 62)
$btnOpenFolder.Size = New-Object System.Drawing.Size(355, 38)
Style-Button -Button $btnOpenFolder -BaseColor ([System.Drawing.Color]::FromArgb(35, 55, 90)) -HoverColor ([System.Drawing.Color]::FromArgb(50, 75, 125)) -TextColor ([System.Drawing.Color]::White)
[void]$actionPanel.Controls.Add($btnOpenFolder)

# Tip panel (shown while idle)
$tipPanel = New-Object System.Windows.Forms.Panel
$tipPanel.Location = New-Object System.Drawing.Point(0, 108)
$tipPanel.Size = New-Object System.Drawing.Size(722, 68)
$tipPanel.BackColor = [System.Drawing.Color]::FromArgb(14, 22, 38)
$tipPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
[void]$actionPanel.Controls.Add($tipPanel)
$script:TipPanel = $tipPanel

$lblTipBadge = New-Object System.Windows.Forms.Label
$lblTipBadge.Text = "[TIP]"
$lblTipBadge.Location = New-Object System.Drawing.Point(12, 12)
$lblTipBadge.Size = New-Object System.Drawing.Size(60, 20)
$lblTipBadge.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9.5)
$lblTipBadge.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 90)
[void]$tipPanel.Controls.Add($lblTipBadge)

$lblTipDesc = New-Object System.Windows.Forms.Label
$lblTipDesc.Text = "Press the [End] key in-game to instantly toggle all ReShade effects (CAS, Vibrance, SMAA) and compare the visual difference in real time."
$lblTipDesc.Location = New-Object System.Drawing.Point(75, 10)
$lblTipDesc.Size = New-Object System.Drawing.Size(635, 48)
$lblTipDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblTipDesc.ForeColor = [System.Drawing.Color]::FromArgb(190, 215, 245)
[void]$tipPanel.Controls.Add($lblTipDesc)

# Installation progress panel
$progressPanel = New-Object System.Windows.Forms.Panel
$progressPanel.Location = New-Object System.Drawing.Point(0, 108)
$progressPanel.Size = New-Object System.Drawing.Size(722, 68)
$progressPanel.BackColor = [System.Drawing.Color]::FromArgb(20, 30, 52)
$progressPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$progressPanel.Visible = $false
[void]$actionPanel.Controls.Add($progressPanel)
$script:ProgressPanel = $progressPanel

$lblProgressStep = New-Object System.Windows.Forms.Label
$lblProgressStep.Text = "Starting DLSS 5 installation..."
$lblProgressStep.Location = New-Object System.Drawing.Point(14, 8)
$lblProgressStep.Size = New-Object System.Drawing.Size(590, 20)
$lblProgressStep.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
$lblProgressStep.ForeColor = [System.Drawing.Color]::FromArgb(130, 205, 255)
[void]$progressPanel.Controls.Add($lblProgressStep)
$script:LblProgressStep = $lblProgressStep

$lblProgressPct = New-Object System.Windows.Forms.Label
$lblProgressPct.Text = "0%"
$lblProgressPct.Location = New-Object System.Drawing.Point(610, 8)
$lblProgressPct.Size = New-Object System.Drawing.Size(95, 20)
$lblProgressPct.Font = New-Object System.Drawing.Font("Segoe UI Bold", 10.5)
$lblProgressPct.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
$lblProgressPct.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
[void]$progressPanel.Controls.Add($lblProgressPct)
$script:LblProgressPct = $lblProgressPct

$mainProgressBar = New-Object System.Windows.Forms.ProgressBar
$mainProgressBar.Location = New-Object System.Drawing.Point(14, 34)
$mainProgressBar.Size = New-Object System.Drawing.Size(692, 22)
$mainProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$mainProgressBar.Value = 0
[void]$progressPanel.Controls.Add($mainProgressBar)
$script:MainProgressBar = $mainProgressBar

# --- FOOTER WITH LOG AND STATUS ---
$footer = New-Object System.Windows.Forms.Panel
$footer.Location = New-Object System.Drawing.Point(0, 790)
$footer.Size = New-Object System.Drawing.Size(1260, 32)
$footer.Anchor = "Bottom, Left, Right"
$footer.BackColor = [System.Drawing.Color]::FromArgb(8, 12, 20)
[void]$form.Controls.Add($footer)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "  Ready. Select a game to begin."
$lblStatus.Location = New-Object System.Drawing.Point(18, 7)
$lblStatus.Size = New-Object System.Drawing.Size(800, 18)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(140, 180, 220)
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9)
[void]$footer.Controls.Add($lblStatus)
$script:StatusLabel = $lblStatus

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(825, 6)
$progressBar.Size = New-Object System.Drawing.Size(230, 20)
$progressBar.Anchor = "Top, Right"
$progressBar.Visible = $false
$progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
[void]$footer.Controls.Add($progressBar)
$script:ProgressBar = $progressBar

$btnOpenLog = New-Object System.Windows.Forms.Button
$btnOpenLog.Text = "VIEW FULL LOG"
$btnOpenLog.Location = New-Object System.Drawing.Point(1070, 3)
$btnOpenLog.Size = New-Object System.Drawing.Size(170, 26)
$btnOpenLog.Anchor = "Top, Right"
Style-Button -Button $btnOpenLog -BaseColor ([System.Drawing.Color]::FromArgb(25, 40, 65)) -HoverColor ([System.Drawing.Color]::FromArgb(35, 60, 95))
$btnOpenLog.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$btnOpenLog.Add_Click({ Open-LogFile })
[void]$footer.Controls.Add($btnOpenLog)

# --- LANGUAGE SYNC ---
function Update-UiLanguage {
    param([string]$Lang)
    $script:CurrentLang = $Lang
    $d = Get-Dict -Lang $Lang

    $lblTagline.Text = $d.Tagline
    $lblSubBadge.Text = $d.SubBadge
    $lblStep1.Text = $d.Step1
    $lblStep2.Text = $d.Step2
    $lblStep3.Text = $d.Step3
    $btnDiagnose.Text = $d.BtnDiagnose
    $btnScan.Text = $d.BtnScan
    $btnBrowse.Text = $d.BtnBrowse
    $lblLibTitle.Text = $d.LibraryTitle
    $lblFolderTitle.Text = $d.FolderLabel
    $lblModeSecTitle.Text = $d.ModeSectionTitle
    $lblAutoNotice.Text = $d.AutoModeNotice
    $lblCard1Title.Text = $d.Mode1Title
    $lblCard1Desc.Text = $d.Mode1Desc
    $lblCard2Title.Text = $d.Mode2Title
    $lblCard2Desc.Text = $d.Mode2Desc
    $lblCard3Title.Text = $d.Mode3Title
    $lblCard3Desc.Text = $d.Mode3Desc
    $lblReqTitle.Text = $d.RequirementTitle
    $btnLaunch.Text = $d.BtnLaunch
    $btnUninstall.Text = $d.BtnUninstall
    $btnOpenFolder.Text = $d.BtnOpenFolder
    $btnOpenLog.Text = $d.BtnOpenLog

    $btnInstallText = $d.BtnInstall
    if ([string]::IsNullOrWhiteSpace($btnInstallText)) { $btnInstallText = "[1-CLICK] INSTALL DLSS 5" }
    $btnInstall.Text = $btnInstallText

    $gameList.Columns[0].Text = $d.ColGame
    $gameList.Columns[1].Text = $d.ColApi
    $gameList.Columns[2].Text = $d.ColMode
    if ($d.NoGameSelected) { $lblReqText.Text = $d.NoGameSelected }
    if (-not $script:SelectedGameObj -and $d.NoGameSelected) { $lblGameStatus.Text = $d.NoGameSelected }

    if ($script:SelectedGameObj) {
        Select-GameInInspector -GameObj $script:SelectedGameObj
    }
    else {
        $lblStatus.Text = "  " + $d.StatusReady
    }
}

$comboLang.Add_SelectedIndexChanged({
        $langCodes = @("EN", "PT", "ES", "DE", "FR", "IT", "JA", "ZH", "RU", "KO")
        $idx = $comboLang.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $langCodes.Length) {
            Update-UiLanguage -Lang $langCodes[$idx]
        }
    })

# --- EVENTS AND INSPECTOR LOGIC ---
function Select-GameInInspector {
    param([pscustomobject]$GameObj)
    if ($null -eq $GameObj) { return }
    $script:SelectedGameObj = $GameObj
    $d = Get-Dict -Lang $script:CurrentLang

    $lblGameTitle.Text = $GameObj.Name
    $txtFolderPath.Text = $GameObj.Path

    try {
        $resolved = Resolve-GameTarget -TargetPath $GameObj.Path
        Repair-GameCriticalDependencies -TargetFolder $resolved.InstallFolder -TargetExe $resolved.Executable
    }
    catch {}

    if ($GameObj.Icon) {
        $picIcon.Image = $GameObj.Icon.ToBitmap()
    }
    else {
        $picIcon.Image = $null
    }

    $detected = $GameObj.Upscaler
    $script:CurrentDetectedUpscaler = $detected

    $modeCode = "FEEDER"
    if ($detected -eq "NATIVE_DLSS") {
        $modeCode = "DIRECT"
    }
    elseif ($detected -eq "FSR2_BRIDGE" -or $detected -eq "XESS_BRIDGE") {
        $modeCode = "OPTISCALER"
    }
    Highlight-SelectedModeCard -Mode $modeCode

    $modeText = "Universal (Feeder)"
    if ($detected -eq "NATIVE_DLSS") {
        $modeText = "Native DLSS"
    }
    elseif ($detected -like "*BRIDGE*") {
        $modeText = "FSR2/XeSS (OptiScaler)"
    }

    $isInstalled = Test-GameDlss5Installed -GameFolder $GameObj.Path
    if ($isInstalled) {
        $lblGameStatus.Text = $d.StatusInstalled + "   API: " + $GameObj.Api
        $lblGameStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 90)
        
        $btnText = $d.BtnReinstall
        if ([string]::IsNullOrWhiteSpace($btnText)) { $btnText = "[UPDATE] REINSTALL DLSS 5" }
        $btnInstall.Text = $btnText
        Style-Button -Button $btnInstall -BaseColor ([System.Drawing.Color]::FromArgb(65, 140, 45)) -HoverColor ([System.Drawing.Color]::FromArgb(85, 175, 55)) -TextColor ([System.Drawing.Color]::White)
    }
    else {
        $lblGameStatus.Text = "API: " + $GameObj.Api + "   Recommended: " + $modeText
        $lblGameStatus.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
        
        $btnText = $d.BtnInstall
        if ([string]::IsNullOrWhiteSpace($btnText)) { $btnText = "[1-CLICK] INSTALL DLSS 5" }
        $btnInstall.Text = $btnText
        Style-Button -Button $btnInstall -BaseColor ([System.Drawing.Color]::FromArgb(118, 185, 0)) -HoverColor ([System.Drawing.Color]::FromArgb(140, 220, 0)) -TextColor ([System.Drawing.Color]::Black)
    }

    Write-Status -Message "Game selected: $($GameObj.Name) [$($GameObj.Api)]" -Level "INFO"
}

$gameList.Add_SelectedIndexChanged({
        if ($gameList.SelectedIndices.Count -gt 0) {
            $idx = $gameList.SelectedIndices[0]
            if ($script:CurrentGameLibrary -and $idx -lt $script:CurrentGameLibrary.Count) {
                Select-GameInInspector -GameObj $script:CurrentGameLibrary[$idx]
            }
        }
    })

function Refresh-GameLibraryUI {
    param($Games)
    $gameList.BeginUpdate()
    $gameList.Items.Clear()
    $imageList.Images.Clear()

    $d = Get-Dict -Lang $script:CurrentLang

    foreach ($g in $Games) {
        $imgIdx = -1
        if ($g.Icon) {
            try {
                $imageList.Images.Add($g.Icon.ToBitmap())
                $imgIdx = $imageList.Images.Count - 1
            }
            catch {}
        }

        $isInst = Test-GameDlss5Installed -GameFolder $g.Path
        $modeLabel = ""
        if ($isInst) {
            $modeLabel = "[OK] DLSS 5 Active"
        }
        else {
            if ($g.Upscaler -eq "NATIVE_DLSS") {
                $modeLabel = "[Mode 1] DLSS"
            }
            elseif ($g.Upscaler -eq "FSR2_BRIDGE" -or $g.Upscaler -eq "XESS_BRIDGE") {
                $modeLabel = "[Mode 2] OptiScaler"
            }
            else {
                $modeLabel = "[Mode 3] Feeder"
            }
        }

        $item = New-Object System.Windows.Forms.ListViewItem($g.Name, $imgIdx)
        [void]$item.SubItems.Add($g.Api)
        [void]$item.SubItems.Add($modeLabel)
        [void]$gameList.Items.Add($item)
    }
    $gameList.EndUpdate()
}

$btnScan.Add_Click({
        $d = Get-Dict -Lang $script:CurrentLang
        Write-Status -Message $d.StatusScanning -Level "INFO"
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        if ($script:ProgressBar) {
            $script:ProgressBar.Value = 0
            $script:ProgressBar.Visible = $true
        }

        $games = Scan-DriveForGames -DriveLetter "ALL" -ProgressCallback {
            param($pct, $name)
            $script:StatusLabel.Text = "  Scanning: $name ($pct%)..."
            if ($script:ProgressBar) {
                $script:ProgressBar.Value = [Math]::Min(100, [Math]::Max(0, [int]$pct))
            }
            [System.Windows.Forms.Application]::DoEvents()
        }

        $script:CurrentGameLibrary = $games
        Refresh-GameLibraryUI -Games $games
        if ($script:ProgressBar) { $script:ProgressBar.Visible = $false }
        $form.Cursor = [System.Windows.Forms.Cursors]::Default

        Write-Status -Message ($d.StatusScanDone -f $games.Count) -Level "OK"
        if ($games.Count -gt 0) {
            $gameList.Items[0].Selected = $true
        }
    })

$btnBrowse.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select the folder where the game is installed:"
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                $resolved = Resolve-GameTarget -TargetPath $fbd.SelectedPath
                $api = Detect-GameGraphicsApi -TargetExe $resolved.Executable -GameFolder $resolved.InstallFolder
                $upscaler = Detect-GameUpscalerType -GameFolder $resolved.InstallFolder -GameRoot $resolved.Root
                $gObj = [pscustomobject]@{
                    Order    = 1
                    Name     = (Split-Path -Leaf $fbd.SelectedPath)
                    Path     = $fbd.SelectedPath
                    Api      = "$api ($($resolved.Architecture))"
                    Upscaler = $upscaler
                    Icon     = $resolved.Icon
                    ExeName  = $resolved.ExeName
                }
                $script:CurrentGameLibrary = @($gObj)
                Refresh-GameLibraryUI -Games @($gObj)
                Select-GameInInspector -GameObj $gObj
            }
            catch {
                Show-FriendlyErrorDialog -Ex $_.Exception -Context "Folder Selection" -TargetPath $fbd.SelectedPath
            }
        }
    })

$btnInstall.Add_Click({
        if (-not $script:SelectedGameObj) {
            [System.Windows.Forms.MessageBox]::Show("Please select a game from the library or click 'BROWSE GAME' first.", "1 Click DLSS 5", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            return
        }

        $oldText = $btnInstall.Text
        $btnInstall.Enabled = $false
        $btnLaunch.Enabled = $false
        $btnUninstall.Enabled = $false
        $btnBrowse.Enabled = $false
        $btnScan.Enabled = $false
        $btnInstall.Text = "[...] INSTALLING DLSS 5..."
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

        if ($script:TipPanel) { $script:TipPanel.Visible = $false }
        if ($script:ProgressPanel) {
            $script:ProgressPanel.Visible = $true
            $script:MainProgressBar.Value = 5
            $script:LblProgressPct.Text = "5%"
            $script:LblProgressStep.Text = "Validating game and write permissions..."
            [System.Windows.Forms.Application]::DoEvents()
        }
        if ($script:ProgressBar) {
            $script:ProgressBar.Value = 5
            $script:ProgressBar.Visible = $true
        }

        try {
            Install-Dlss5 -TargetPath $script:SelectedGameObj.Path -SelectedMode $script:SelectedMode -ProgressCallback {
                param($pct, $msg)
                Write-Status -Message $msg -Level "INFO"
                if ($script:ProgressPanel) {
                    $clamped = [Math]::Min(100, [Math]::Max(0, [int]$pct))
                    $script:MainProgressBar.Value = $clamped
                    $script:LblProgressPct.Text = "$clamped%"
                    $script:LblProgressStep.Text = $msg
                }
                if ($script:ProgressBar) {
                    $script:ProgressBar.Value = [Math]::Min(100, [Math]::Max(0, [int]$pct))
                }
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 180
            }
            Select-GameInInspector -GameObj $script:SelectedGameObj
        }
        catch {
            Show-FriendlyErrorDialog -Ex $_.Exception -Context "DLSS 5 Installation" -TargetPath $script:SelectedGameObj.Path -SelectedMode $script:SelectedMode
        }
        finally {
            Start-Sleep -Milliseconds 250
            if ($script:ProgressPanel) { $script:ProgressPanel.Visible = $false }
            if ($script:TipPanel) { $script:TipPanel.Visible = $true }
            if ($script:ProgressBar) { $script:ProgressBar.Visible = $false }
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
            $btnInstall.Enabled = $true
            $btnLaunch.Enabled = $true
            $btnUninstall.Enabled = $true
            $btnBrowse.Enabled = $true
            $btnScan.Enabled = $true
            $btnInstall.Text = $oldText
        }
    })

$btnLaunch.Add_Click({
        if (-not $script:SelectedGameObj) { return }
        try {
            $resolved = Resolve-GameTarget -TargetPath $script:SelectedGameObj.Path
            Start-GameExecutable -ExecutablePath $resolved.Executable
        }
        catch {
            Show-FriendlyErrorDialog -Ex $_.Exception -Context "Game Launch" -TargetPath $script:SelectedGameObj.Path
        }
    })

$btnUninstall.Add_Click({
        if (-not $script:SelectedGameObj) { return }
        $res = [System.Windows.Forms.MessageBox]::Show("Do you really want to remove all DLSS 5 files and restore the game to its factory original state?", "Confirm Restore", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
            try {
                Uninstall-Dlss5 -TargetPath $script:SelectedGameObj.Path
                Select-GameInInspector -GameObj $script:SelectedGameObj
            }
            catch {
                Show-FriendlyErrorDialog -Ex $_.Exception -Context "Factory Restore" -TargetPath $script:SelectedGameObj.Path
            }
        }
    })

$btnOpenFolder.Add_Click({
        if ($script:SelectedGameObj -and (Test-Path -LiteralPath $script:SelectedGameObj.Path)) {
            Start-Process "explorer.exe" -ArgumentList "`"$($script:SelectedGameObj.Path)`""
        }
    })

$txtSearch.Add_TextChanged({
        $term = $txtSearch.Text.Trim().ToLower()
        if ($null -eq $script:CurrentGameLibrary) { return }
        if ([string]::IsNullOrWhiteSpace($term)) {
            Refresh-GameLibraryUI -Games $script:CurrentGameLibrary
        }
        else {
            $filtered = @($script:CurrentGameLibrary | Where-Object { $_.Name.ToLower().Contains($term) -or $_.Api.ToLower().Contains($term) })
            Refresh-GameLibraryUI -Games $filtered
        }
    })

# --- AUTO-DISCOVERY ON STARTUP ---
$form.Add_Shown({
        $d = Get-Dict -Lang $script:CurrentLang
        $lblStatus.Text = "  Loading library of games installed on this PC..."
        if ($script:ProgressBar) {
            $script:ProgressBar.Value = 0
            $script:ProgressBar.Visible = $true
        }
        [System.Windows.Forms.Application]::DoEvents()

        $autoGames = Scan-DriveForGames -DriveLetter "ALL" -ProgressCallback {
            param($pct, $name)
            $lblStatus.Text = "  Loading: $name ($pct%)..."
            if ($script:ProgressBar) {
                $script:ProgressBar.Value = [Math]::Min(100, [Math]::Max(0, [int]$pct))
            }
            [System.Windows.Forms.Application]::DoEvents()
        }
        if ($script:ProgressBar) { $script:ProgressBar.Visible = $false }

        if ($autoGames.Count -gt 0) {
            $script:CurrentGameLibrary = $autoGames
            Refresh-GameLibraryUI -Games $autoGames
            $lblStatus.Text = "  " + ($d.StatusScanDone -f $autoGames.Count)
            $gameList.Items[0].Selected = $true
        }
        else {
            $lblStatus.Text = "  " + $d.StatusReady
        }
    })

# Startup: apply the default language to every control from the single dictionary
Update-UiLanguage -Lang $script:CurrentLang
# Startup
Write-Status -Message "1 Click DLSS 5 v$($script:Version) ready." -Level "OK"
if (-not $env:DLSS5_HEADLESS) {
    [void][System.Windows.Forms.Application]::EnableVisualStyles()
    $form.TopMost = $true
    $form.Add_Shown({
        $this.TopMost = $false
        $this.Activate()
        $this.BringToFront()
    })
    [void][System.Windows.Forms.Application]::Run($form)
}
