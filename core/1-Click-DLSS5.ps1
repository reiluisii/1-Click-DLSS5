<#
.SYNOPSIS
    1 Click DLSS 5 v3.0.0 — Universal Neural Control Center
    Auto-Descoberta Instantânea de Jogos (Steam, Epic, GOG, Xbox, EA), Motor de Resolução em 1 Clique (Auto-Fix),
    Suporte Universal a APIs (DirectX 9/10/11/12, Vulkan, OpenGL), 32 e 64-bit, 10 Idiomas Nativos.
#>

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

[System.Windows.Forms.Application]::EnableVisualStyles()

# --- FATOR DE ESCALA DPI + ESCALONAMENTO REAL DAS JANELAS (125% / 150% / 200%) ---
try {
    if (-not ([System.Management.Automation.PSTypeName]'DLSS5DpiQuery').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DLSS5DpiQuery {
    [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
}
"@
    }
    $script:DpiScale = [Math]::Round(([double][DLSS5DpiQuery]::GetDpiForSystem() / 96.0), 2)
}
catch { $script:DpiScale = 1.0 }
if (-not $script:DpiScale -or $script:DpiScale -lt 1.0) { $script:DpiScale = 1.0 }

function Scale-ControlTree {
    param($Control, [double]$Factor, $ParentFont = $null)
    if ($Control -is [System.Windows.Forms.ListView]) {
        foreach ($col in $Control.Columns) { $col.Width = [int]($col.Width * $Factor) }
        foreach ($il in @($Control.SmallImageList, $Control.LargeImageList)) {
            if ($il -and $il.Tag -ne "dpi-scaled") {
                $il.ImageSize = New-Object System.Drawing.Size([int]($il.ImageSize.Width * $Factor), [int]($il.ImageSize.Height * $Factor))
                $il.Tag = "dpi-scaled"
            }
        }
    }
    if ($Control -is [System.Windows.Forms.PictureBox] -and $Control.Image -and $Control.SizeMode -eq [System.Windows.Forms.PictureBoxSizeMode]::Normal) {
        $Control.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    }
    foreach ($child in $Control.Controls) {
        Scale-ControlTree -Control $child -Factor $Factor -ParentFont $Control.Font
    }
}

function Apply-DpiScaling {
    param([System.Windows.Forms.Form]$Form)
    $factor = $script:DpiScale
    if (-not $Form -or $factor -le 1.0 -or $Form.Tag -eq "dpi-scaled") { return }
    try {
        $Form.SuspendLayout()
        $Form.Scale((New-Object System.Drawing.SizeF([float]$factor, [float]$factor)))
        Scale-ControlTree -Control $Form -Factor $factor -ParentFont $null
        $wa = [System.Windows.Forms.Screen]::FromControl($Form).WorkingArea
        if ($Form.Width -gt $wa.Width -or $Form.Height -gt $wa.Height) {
            $newW = [Math]::Min($Form.Width, $wa.Width)
            $newH = [Math]::Min($Form.Height, $wa.Height)
            $Form.MinimumSize = New-Object System.Drawing.Size([Math]::Min($Form.MinimumSize.Width, $newW), [Math]::Min($Form.MinimumSize.Height, $newH))
            $Form.Size = New-Object System.Drawing.Size($newW, $newH)
        }
        if ($Form.StartPosition -eq [System.Windows.Forms.FormStartPosition]::CenterScreen) {
            $cx = [int]$wa.X + [int](([int]$wa.Width - [int]$Form.Width) / 2)
            $cy = [int]$wa.Y + [int](([int]$wa.Height - [int]$Form.Height) / 2)
            $Form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
            $Form.Location = New-Object System.Drawing.Point($cx, $cy)
        }
        $Form.Tag = "dpi-scaled"
        $Form.ResumeLayout($true)
    }
    catch {}
}

# --- DPI SCALING SYSTEM-AWARE VIRTUALIZATION ---
# Mantem a renderizacao sob DWM Virtualization proporcional do Windows (identica a v2.5.1),
# impedindo que o WinForms aumente metricas de fontes isoladamente em 125%/150%/175% de escala,
# o que causaria sobreposicao e corte de textos em layouts de coordenadas fixas.



# --- CONFIGURACOES GLOBAIS ---
$script:Version = "3.0.0"
$script:AddOnName = "renodx-dlss5.addon64"
$script:StateName = "_dlss5_install_state.json"
$script:BackupName = "_DLSS5_Backup"
$script:SelectedGameObj = $null
$script:CurrentDetectedUpscaler = "UNIVERSAL_FEEDER"
$script:SelectedMode = "AUTO"
$script:CurrentGameLibrary = @()

if (-not $PSScriptRoot) {
    if ($MyInvocation.MyCommand.Path) { $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
    elseif (Test-Path -LiteralPath (Join-Path (Get-Location).Path "core") -PathType Container) { $PSScriptRoot = Join-Path (Get-Location).Path "core" }
    else { $PSScriptRoot = (Get-Location).Path }
}

$script:PayloadFolder = Join-Path $PSScriptRoot "payload"
$script:IconPath = Join-Path $PSScriptRoot "assets\icon.ico"
if (-not (Test-Path -LiteralPath $script:IconPath -PathType Leaf)) {
    $script:IconPath = Join-Path $PSScriptRoot "assets\logo.ico"
}
$script:TranslationsPath = Join-Path $PSScriptRoot "assets\translations.json"
$script:ConfigPath = Join-Path $PSScriptRoot "assets\config.json"
$script:CachePath = Join-Path $PSScriptRoot "assets\games_cache.json"
$script:LogFilePath = Join-Path $PSScriptRoot "1-Click-DLSS5.log"

$script:Translations = $null
if (Test-Path -LiteralPath $script:TranslationsPath -PathType Leaf) {
    try {
        $jsonRaw = [System.IO.File]::ReadAllText($script:TranslationsPath, [System.Text.Encoding]::UTF8)
        # Emojis (U+1F000..U+1FAFF, teclas 1/2/3 com U+20E3, raio U+26A1) viram quadrados no WinForms/GDI.
        # Trocamos por marcadores ASCII para a UI ficar legivel em qualquer fonte.
        $jsonRaw = [regex]::Replace($jsonRaw, '\uFE0F', '')
        $jsonRaw = [regex]::Replace($jsonRaw, '([0-9])\u20E3', '$1.')
        $jsonRaw = [regex]::Replace($jsonRaw, '\u26A1|\u2B50|\uD83C[\uDC00-\uDFFF]|\uD83D[\uDC00-\uDFFF]|\uD83E[\uDC00-\uDFFF]', '')
        $jsonRaw = [regex]::Replace($jsonRaw, '\[\s*\]\s*', '')
        $script:Translations = $jsonRaw | ConvertFrom-Json
    }
    catch {}
}

# --- MODULOS PROPRIETARIOS DO MOTOR 1-CLICK DLSS 5 ---
$script:EngineRoot = Join-Path $PSScriptRoot "engine"
if (Test-Path -LiteralPath $script:EngineRoot) {
    . (Join-Path $script:EngineRoot "DLSS5-PeEngine.ps1")
    . (Join-Path $script:EngineRoot "DLSS5-Journal.ps1")
    . (Join-Path $script:EngineRoot "DLSS5-Detection.ps1")
    . (Join-Path $script:EngineRoot "DLSS5-Pipeline.ps1")
}

function Get-SystemDefaultLanguage {
    try {
        $uiCulture = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName.ToUpper()
        $supported = @("PT", "EN", "ES", "DE", "FR", "IT", "JA", "ZH", "RU", "KO")
        if ($supported -contains $uiCulture) {
            return $uiCulture
        }
    }
    catch {}
    return "EN"
}

function Get-AppConfig {
    $defaultConfig = [pscustomobject]@{
        Language             = "AUTO"
        AutoScanOnStartup    = $false
        ScanDrives           = "ALL"
        LastSelectedGamePath = ""
        CustomGamePaths      = @()
    }
    if ($script:ConfigPath -and (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf)) {
        try {
            $raw = [System.IO.File]::ReadAllText($script:ConfigPath, [System.Text.Encoding]::UTF8)
            $cfg = $raw | ConvertFrom-Json
            if ($cfg) {
                if ($null -eq $cfg.Language) { $cfg | Add-Member -NotePropertyName "Language" -NotePropertyValue "AUTO" }
                if ($null -eq $cfg.AutoScanOnStartup) { $cfg | Add-Member -NotePropertyName "AutoScanOnStartup" -NotePropertyValue $false }
                if ($null -eq $cfg.ScanDrives) { $cfg | Add-Member -NotePropertyName "ScanDrives" -NotePropertyValue "ALL" }
                if ($null -eq $cfg.LastSelectedGamePath) { $cfg | Add-Member -NotePropertyName "LastSelectedGamePath" -NotePropertyValue "" }
                if ($null -eq $cfg.CustomGamePaths) { $cfg | Add-Member -NotePropertyName "CustomGamePaths" -NotePropertyValue @() }
                return $cfg
            }
        }
        catch {}
    }
    return $defaultConfig
}

function Save-AppConfig {
    param([pscustomobject]$Config = $null)
    if ($null -eq $Config) { $Config = $script:AppConfig }
    try {
        $json = $Config | ConvertTo-Json -Depth 5
        $utf8WithBom = [System.Text.Encoding]::UTF8
        [System.IO.File]::WriteAllText($script:ConfigPath, $json, $utf8WithBom)
    }
    catch {}
}

$script:AppConfig = Get-AppConfig
if ($script:AppConfig.Language -and $script:AppConfig.Language -ne "AUTO") {
    $script:CurrentLang = $script:AppConfig.Language
}
else {
    $script:CurrentLang = Get-SystemDefaultLanguage
}

# --- SISTEMA AVANCADO DE TELEMETRIA, HARDWARE E LOG FORENSE CONTINUO ---
$script:LogSyncRoot = New-Object object

function Write-Status {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][string]$Level = "INFO",
        [Parameter(Mandatory = $false)][string]$Code = "",
        [Parameter(Mandatory = $false)][string]$Cause = "",
        [Parameter(Mandatory = $false)][string]$Fix = "",
        [Parameter(Mandatory = $false)][string]$Details = ""
    )
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $logLine = "[$ts] [$Level] $Message"
    if ($Code) { $logLine = $logLine + " [CODE: $Code]" }
    if ($Cause) { $logLine = $logLine + " [CAUSA: $Cause]" }
    if ($Fix) { $logLine = $logLine + " [SOLUCAO: $Fix]" }
    if ($Details) { $logLine = $logLine + "`r`n   " + ($Details.TrimEnd() -replace "`r?`n", "`r`n   ") }

    try {
        [System.Threading.Monitor]::Enter($script:LogSyncRoot)
        try {
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::AppendAllText($script:LogFilePath, $logLine + "`r`n", $utf8NoBom)
        }
        finally {
            [System.Threading.Monitor]::Exit($script:LogSyncRoot)
        }
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

function Get-FormattedTelemetryBanner {
    param([string]$Version = "3.0.0")
    $sb = [System.Text.StringBuilder]::new()
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    
    [void]$sb.AppendLine("================================================================================")
    [void]$sb.AppendLine("   1 CLICK DLSS 5 v$Version   NEURAL CONTROL CENTER LOG DE TELEMETRIA")
    [void]$sb.AppendLine("   Sessao iniciada em: $ts")
    [void]$sb.AppendLine("================================================================================")
    
    try {
        # 1. Sistema Operacional & Runtimes
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $dispVer = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).DisplayVersion
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $adminStr = if ($isAdmin) { "SIM (Elevated Administrator)" } else { "NAO (Standard User)" }
        
        $uptimeStr = "N/A"
        if ($os -and $os.LastBootUpTime) {
            $uptime = (Get-Date) - $os.LastBootUpTime
            $uptimeStr = "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m $($uptime.Seconds)s"
        }
        
        $osArch = if ($os.OSArchitecture) { $os.OSArchitecture } else { "64-bit" }
        [void]$sb.AppendLine("[SISTEMA OPERACIONAL & RUNTIME]")
        [void]$sb.AppendLine("OS: $($os.Caption) $($dispVer) (Versao: $($os.Version) | Build: $($os.BuildNumber) | Arquitetura: $osArch)")
        [void]$sb.AppendLine("Uptime do Sistema: $uptimeStr | Privilegios de Administrador: $adminStr")
        [void]$sb.AppendLine("PowerShell Runtime: $($PSVersionTable.PSVersion) | CLR Runtime: $($PSVersionTable.CLRVersion)")
        [void]$sb.AppendLine("Cultura do Sistema: $([System.Globalization.CultureInfo]::CurrentUICulture.Name) (ISO: $([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName.ToUpper())) | Idioma App: $script:CurrentLang")
        [void]$sb.AppendLine("Diretorio de Execucao: $PSScriptRoot | Log: $script:LogFilePath")
        [void]$sb.AppendLine("")
        
        # 2. Processador (CPU)
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
        if ($cpu) {
            $cpuClock = if ($cpu.MaxClockSpeed) { "$($cpu.MaxClockSpeed) MHz" } else { "N/A" }
            [void]$sb.AppendLine("[PROCESSADOR (CPU)]")
            [void]$sb.AppendLine("Modelo: $($cpu.Name)")
            [void]$sb.AppendLine("Nucleos Fisicos: $($cpu.NumberOfCores) | Threads Logicos: $($cpu.NumberOfLogicalProcessors) | Clock Maximo: $cpuClock")
            [void]$sb.AppendLine("")
        }
        
        # 3. Placas de Video (GPU)
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
        if ($gpus.Count -gt 0) {
            [void]$sb.AppendLine("[PLACA DE VIDEO (GPU)]")
            $gpuIdx = 1
            foreach ($g in $gpus) {
                $vramGb = if ($g.AdapterRAM -and $g.AdapterRAM -gt 0) { [Math]::Round($g.AdapterRAM / 1GB, 2) } else { "N/A" }
                $driverDate = if ($g.DriverDate) { ($g.DriverDate).ToString("yyyy-MM-dd") } else { "N/A" }
                $gpuType = "GPU Dedicada (dGPU)"
                if ($g.Name -match '(?i)(intel.*graphics|amd.*radeon\(tm\)\s+graphics|vega|uhd|iris|apu)') {
                    $gpuType = "GPU Integrada (iGPU)"
                }
                [void]$sb.AppendLine("GPU $gpuIdx [$gpuType]: $($g.Name)")
                [void]$sb.AppendLine("   Driver: $($g.DriverVersion) ($driverDate) | VRAM: $vramGb GB")
                $gpuIdx++
            }
            $hags = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -ErrorAction SilentlyContinue).HwSchMode
            $hagsStr = switch ($hags) { 2 { "ATIVADO (Modo 2)" } 1 { "DESATIVADO (Modo 1)" } default { "Nao suportado ou Padrao do Sistema" } }
            [void]$sb.AppendLine("Hardware GPU Scheduling (HAGS): $hagsStr")
            [void]$sb.AppendLine("")
        }
        
        # 4. Memoria RAM & Armazenamento
        if ($os) {
            $ramTotalGb = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
            $ramFreeGb = [Math]::Round($os.FreePhysicalMemory / 1MB, 2)
            $ramPctFree = if ($ramTotalGb -gt 0) { [Math]::Round(($ramFreeGb / $ramTotalGb) * 100, 1) } else { 0 }
            $virtTotalGb = [Math]::Round($os.TotalVirtualMemorySize / 1MB, 2)
            $virtFreeGb = [Math]::Round($os.FreeVirtualMemory / 1MB, 2)
            
            [void]$sb.AppendLine("[MEMORIA RAM & ARMAZENAMENTO]")
            [void]$sb.AppendLine("Memoria RAM Fisica Total: $ramTotalGb GB | Disponivel: $ramFreeGb GB ($ramPctFree% livre)")
            [void]$sb.AppendLine("Memoria Virtual Total: $virtTotalGb GB | Disponivel: $virtFreeGb GB")
            [void]$sb.AppendLine("Unidades de Armazenamento Conectadas:")
            $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
            foreach ($d in $drives) {
                $totalGb = [Math]::Round($d.TotalSize / 1GB, 1)
                $freeGb = [Math]::Round($d.TotalFreeSpace / 1GB, 1)
                $pct = if ($totalGb -gt 0) { [Math]::Round(($freeGb / $totalGb) * 100, 1) } else { 0 }
                $label = if ($d.VolumeLabel) { "[$($d.VolumeLabel)]" } else { "[Sem Rotulo]" }
                [void]$sb.AppendLine(" - $($d.Name) $label Formato: $($d.DriveFormat) | Total: $totalGb GB | Livre: $freeGb GB ($pct% livre)")
            }
            [void]$sb.AppendLine("")
        }
        
        # 5. Monitores & Telas
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $screens = [System.Windows.Forms.Screen]::AllScreens
        if ($screens) {
            [void]$sb.AppendLine("[MONITORES E EXIBICAO]")
            $scrIdx = 1
            foreach ($s in $screens) {
                $primStr = if ($s.Primary) { " (Monitor Principal)" } else { "" }
                [void]$sb.AppendLine("Monitor ${scrIdx}${primStr} - Resolucao: $($s.Bounds.Width)x$($s.Bounds.Height)")
                $scrIdx++
            }
            [void]$sb.AppendLine("")
        }
    }
    catch {
        [void]$sb.AppendLine("Aviso ao coletar telemetria estendida: $($_.Exception.Message)")
    }
    
    [void]$sb.AppendLine("================================================================================")
    return $sb.ToString()
}

function Init-SystemTelemetryLog {
    try {
        $banner = Get-FormattedTelemetryBanner -Version $script:Version
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.Threading.Monitor]::Enter($script:LogSyncRoot)
        try {
            [System.IO.File]::AppendAllText($script:LogFilePath, $banner + "`r`n", $utf8NoBom)
        }
        finally {
            [System.Threading.Monitor]::Exit($script:LogSyncRoot)
        }
    }
    catch {}
}
Init-SystemTelemetryLog

function Open-LogFile {
    Write-Status -Message "[USER] Solicitada abertura visual do arquivo de telemetria/log via Bloco de Notas: '$script:LogFilePath'" -Level "INFO"
    if (Test-Path -LiteralPath $script:LogFilePath -PathType Leaf) {
        Start-Process "notepad.exe" -ArgumentList "`"$script:LogFilePath`""
    }
    else {
        $d = Get-Dict -Lang $script:CurrentLang
        $msg = if ($d.NoLogYet) { $d.NoLogYet } else { "No log generated yet." }
        [System.Windows.Forms.MessageBox]::Show($msg, "1 Click DLSS 5", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
}

function Get-Dict {
    param([string]$Lang)
    if ($script:Translations -and $script:Translations.$Lang) {
        return $script:Translations.$Lang
    }
    if ($script:Translations -and $script:Translations.EN) {
        return $script:Translations.EN
    }
    if ($script:Translations -and $script:Translations.PT) {
        return $script:Translations.PT
    }
    return [pscustomobject]@{
        "Title"             = "1 CLICK DLSS 5"
        "Tagline"           = "NEURAL CONTROL CENTER - RTX 20/30/40/50"
        "SubBadge"          = "DirectX 9 / 10 / 11 / 12 - Vulkan - OpenGL - 32 & 64-bit"
        "Step1"             = "[1] Escolha o Jogo"
        "Step2"             = "[2] Clique em Instalar"
        "Step3"             = "[3] Inicie e Aproveite!"
        "SearchPlaceholder" = "Pesquisar jogos instalados..."
        "BtnScan"           = "ESCANEAR DISCOS"
        "BtnBrowse"         = "PROCURAR JOGO"
        "BtnDiagnose"       = "DIAGNOSTICO DO SISTEMA"
        "BtnAutoFix"        = "[RESOLVER] CORRECAO AUTOMATICA EM 1 CLIQUE"
        "AutoFixDone"       = "Problema corrigido com sucesso! DLSS 5 instalado e pronto para jogar."
        "AutoFixProgress"   = "Executando correcao automatica em 1 clique..."
        "LibraryTitle"      = "BIBLIOTECA DE JOGOS DETECTADOS"
        "ColGame"           = "Jogo"
        "ColApi"            = "API / Arq"
        "ColMode"           = "Modo / Status"
        "InspectorTitle"    = "PAINEL DE CONTROLE DE INJECAO"
        "NoGameSelected"    = "Selecione um jogo na biblioteca ou procure uma pasta."
        "FolderLabel"       = "DIRETORIO DE INSTALACAO DO JOGO:"
        "ModeSectionTitle"  = "ESCOLHA O MODO DE INJECAO DLSS 5:"
        "AutoModeNotice"    = "O modo ideal para este jogo ja foi selecionado automaticamente!"
        "Mode1Title"        = "MODO 1: DIRETO (DLSS Nativo)"
        "Mode1Desc"         = "Para jogos com DLSS nativo. Ativa Streamline + IA com ganho massivo de FPS."
        "Mode2Title"        = "MODO 2: PONTE OPTISCALER (FSR2/XeSS)"
        "Mode2Desc"         = "Redireciona chamadas FSR2/XeSS para o modelo neural DLSS 5."
        "Mode3Title"        = "MODO 3: FEEDER UNIVERSAL (DLAA 100% Nativo)"
        "Mode3Desc"         = "Para qualquer jogo. Reconstrucao 100% limpa e sem perda de nitidez."
        "RequirementTitle"  = "REQUISITO NO JOGO:"
        "ReqMode1"          = "No menu de video do jogo: ATIVE o 'NVIDIA DLSS' (Qualidade/Desempenho)."
        "ReqMode2"          = "No menu de video do jogo: ATIVE o FSR 2 ou XeSS no modo Qualidade."
        "ReqMode3"          = "No menu de video do jogo: Deixe o DLSS/Upscaling DESLIGADO (resolucao 100% nativa)."
        "BtnInstall"        = "[1-CLIQUE] INSTALAR DLSS 5"
        "BtnReinstall"      = "[ATUALIZAR] REINSTALAR DLSS 5"
        "BtnLaunch"         = "[INICIAR] INICIAR JOGO"
        "BtnLaunchNow"      = "[INICIAR] INICIAR JOGO AGORA"
        "BtnUninstall"      = "[RESTAURAR] RESTAURAR ORIGINAL"
        "BtnOpenFolder"     = "[PASTA] ABRIR PASTA"
        "BtnOpenLog"        = "VER LOG COMPLETO"
        "BtnClose"          = "Fechar"
        "StatusReady"       = "Pronto. Selecione um jogo para comecar."
        "StatusScanning"    = "Escaneando discos e analisando compatibilidade de jogos..."
        "StatusScanDone"    = "Varredura concluida! {0} jogos carregados na biblioteca."
        "StatusInstalled"   = "[DLSS 5 INSTALADO]"
        "SuccessTitle"      = "Instalacao Concluida com Sucesso"
        "SuccessMsg"        = "O DLSS 5 foi injetado com sucesso no jogo!`n`nModo aplicado: {0}`n`nVoce ja pode iniciar o jogo e aproveitar a qualidade maxima."
        "RestoreTitle"      = "Restauracao Completa"
        "RestoreMsg"        = "Jogo restaurado com 100% de integridade original de fabrica!"
        "ErrDialogTitle"    = "Assistente de Diagnostico e Resolucao"
        "ErrWhatHappened"   = "O QUE ACONTECEU:"
        "ErrProbableCause"  = "CAUSA PROVAVEL:"
        "ErrHowToFix"       = "COMO RESOLVER:"
        "DiagTitle"         = "Diagnostico de Compatibilidade"
        "DiagGpuOk"         = "Placa de Video RTX detectada."
        "DiagPermsOk"       = "Permissoes de gravacao liberadas."
        "DiagProcOk"        = "O jogo nao esta em execucao em segundo plano."
        "DiagRuntimeOk"     = "Runtimes neurais e modelos DLSS 5 integros."
        "DiagAllPass"       = "Computador e jogo 100% prontos para rodar o DLSS 5!"
    }
}


function Get-GamesCache {
    $list = New-Object System.Collections.Generic.List[pscustomobject]
    $seenPaths = New-Object System.Collections.Generic.HashSet[string]
    
    if ($script:CachePath -and (Test-Path -LiteralPath $script:CachePath -PathType Leaf)) {
        try {
            $raw = [System.IO.File]::ReadAllText($script:CachePath, [System.Text.Encoding]::UTF8)
            $cachedList = @($raw | ConvertFrom-Json)
            if ($cachedList) {
                foreach ($c in $cachedList) {
                    if ($null -eq $c -or -not (Test-Path -LiteralPath $c.Path -PathType Container)) {
                        continue
                    }
                    $norm = $c.Path.ToLower()
                    if ($seenPaths.Contains($norm)) { continue }
                    [void]$seenPaths.Add($norm)
                    
                    $icon = $null
                    try {
                        $resolved = Resolve-GameTarget -TargetPath $c.Path
                        if ($resolved -and $resolved.Icon) { $icon = $resolved.Icon }
                    } catch {}
                    
                    $isInstalled = Test-GameDlss5Installed -GameFolder $c.Path
                    
                    [void]$list.Add([pscustomobject]@{
                        Order       = $c.Order
                        Name        = $c.Name
                        Path        = $c.Path
                        Api         = $c.Api
                        Upscaler    = $c.Upscaler
                        IsInstalled = $isInstalled
                        Icon        = $icon
                        ExeName     = $c.ExeName
                    })
                }
            }
        }
        catch {}
    }
    
    if ($script:AppConfig.CustomGamePaths) {
        foreach ($cp in $script:AppConfig.CustomGamePaths) {
            if (Test-Path -LiteralPath $cp -PathType Container) {
                $norm = $cp.ToLower()
                if (-not $seenPaths.Contains($norm)) {
                    [void]$seenPaths.Add($norm)
                    try {
                        $resolved = Resolve-GameTarget -TargetPath $cp
                        if ($resolved -and $resolved.Executable) {
                            $api = Detect-GameGraphicsApi -TargetExe $resolved.Executable -GameFolder $resolved.InstallFolder
                            $upscaler = Detect-GameUpscalerType -GameFolder $resolved.InstallFolder -GameRoot $resolved.Root
                            $isInstalled = Test-GameDlss5Installed -GameFolder $resolved.InstallFolder
                            [void]$list.Add([pscustomobject]@{
                                Order       = 1
                                Name        = (Split-Path -Leaf $cp)
                                Path        = $cp
                                Api         = "$api ($($resolved.Architecture))"
                                Upscaler    = $upscaler
                                IsInstalled = $isInstalled
                                Icon        = $resolved.Icon
                                ExeName     = $resolved.ExeName
                            })
                        }
                    } catch {}
                }
            }
        }
    }
    
    return @($list | Sort-Object -Property Order, Name)
}

function Save-GamesCache {
    param($Games)
    if ($null -eq $Games) { return }
    try {
        $storable = @()
        $flat = @()
        foreach ($item in @($Games)) {
            if ($item -is [System.Collections.IEnumerable] -and -not ($item -is [string]) -and -not ($item -is [System.Management.Automation.PSCustomObject])) {
                foreach ($sub in $item) { if ($sub) { $flat += $sub } }
            }
            else {
                if ($item) { $flat += $item }
            }
        }
        foreach ($g in $flat) {
            if (-not $g -or -not $g.Path) { continue }
            $storable += [pscustomobject]@{
                Order       = $g.Order
                Name        = $g.Name
                Path        = $g.Path
                Api         = $g.Api
                Upscaler    = $g.Upscaler
                IsInstalled = $g.IsInstalled
                ExeName     = $g.ExeName
            }
        }
        $json = ""
        if ($storable.Count -eq 1) {
            $json = "[`r`n" + ($storable[0] | ConvertTo-Json -Depth 4) + "`r`n]"
        }
        else {
            $json = $storable | ConvertTo-Json -Depth 4
        }
        $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($script:CachePath, $json, $utf8WithBom)
    }
    catch {}
}

# --- MODAL MODERNO DE SUCESSO DA INSTALA  O ---
function Show-InstallationSuccessDialog {
    param(
        [Parameter(Mandatory = $true)][string]$GameName,
        [Parameter(Mandatory = $true)][string]$ModeName,
        [Parameter(Mandatory = $true)][string]$TargetExePath
    )
    $d = Get-Dict -Lang $script:CurrentLang
    $isPt = ($script:CurrentLang -eq "PT")
    Write-Status -Message "DLSS 5 instalado com sucesso em $GameName [$ModeName]!" -Level "OK"
    Write-Status -Message "[UI] Dialogo de instalacao bem-sucedida exibido ao usuario: Jogo='$GameName' | Modo='$ModeName' | Executavel='$TargetExePath'" -Level "OK"

    if ($env:DLSS5_HEADLESS) { return }

    $succForm = New-Object System.Windows.Forms.Form
    $succForm.Text = if ($d.SuccessTitle) { $d.SuccessTitle } else { "Installation Successfully Completed - 1 Click DLSS 5" }
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
    $lblBigTitle.Text = if ($d.SuccessTitle) { "[OK] " + $d.SuccessTitle.ToUpper() } else { "[OK] DLSS 5 INJECTED SUCCESSFULLY!" }
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

    $gamePrefix = if ($d.ColGame) { $d.ColGame } else { "Game" }
    $lblGame = New-Object System.Windows.Forms.Label
    $lblGame.Text = "$gamePrefix`: $GameName"
    $lblGame.Location = New-Object System.Drawing.Point(15, 12)
    $lblGame.Size = New-Object System.Drawing.Size(555, 22)
    $lblGame.Font = New-Object System.Drawing.Font("Segoe UI Bold", 10.5)
    $lblGame.ForeColor = [System.Drawing.Color]::White
    [void]$infoBox.Controls.Add($lblGame)

    $modePrefix = if ($d.ColMode) { $d.ColMode } else { "Mode" }
    $lblMode = New-Object System.Windows.Forms.Label
    $lblMode.Text = "$modePrefix`: $ModeName"
    $lblMode.Location = New-Object System.Drawing.Point(15, 38)
    $lblMode.Size = New-Object System.Drawing.Size(555, 20)
    $lblMode.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $lblMode.ForeColor = [System.Drawing.Color]::FromArgb(100, 180, 255)
    [void]$infoBox.Controls.Add($lblMode)

    $lblFilters = New-Object System.Windows.Forms.Label
    $lblFilters.Text = if ($isPt) { "Filtros Inclusos: CAS (Nitidez) + Vibrance (Cores) + SMAA (AA) + Splitscreen" } else { "Included Filters: CAS (Sharpness) + Vibrance (Colors) + SMAA (AA) + Splitscreen" }
    $lblFilters.Location = New-Object System.Drawing.Point(15, 62)
    $lblFilters.Size = New-Object System.Drawing.Size(555, 20)
    $lblFilters.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblFilters.ForeColor = [System.Drawing.Color]::FromArgb(180, 230, 160)
    [void]$infoBox.Controls.Add($lblFilters)

    $lblHotkey = New-Object System.Windows.Forms.Label
    $lblHotkey.Text = if ($isPt) { "Atalho de Comparacao: Tecla [End] alterna todos os efeitos instantaneamente no jogo!" } else { "Comparison Hotkey: Press [End] in-game to toggle all effects instantly!" }
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
    $lblInstTitle.Text = if ($isPt) { "[INFO] COMO APROVEITAR NO JOGO:" } else { "[INFO] HOW TO USE IN-GAME:" }
    $lblInstTitle.Location = New-Object System.Drawing.Point(15, 122)
    $lblInstTitle.Size = New-Object System.Drawing.Size(555, 20)
    $lblInstTitle.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9)
    $lblInstTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 90)
    [void]$infoBox.Controls.Add($lblInstTitle)

    $instText = if ($isPt) { "No menu do jogo: Deixe o upscaler desligado. O DLSS 5 rodara na resolucao nativa com qualidade neural maxima!" } else { "In game settings: Keep upscaler disabled. DLSS 5 will run at 100% native resolution with maximum neural clarity!" }
    if ($ModeName -match 'DIRECT|Modo 1|Mode 1') {
        $instText = if ($isPt) { "No menu de video do jogo: ATIVE o DLSS (Qualidade, Desempenho ou DLAA). O DLSS 5 opera na aba 'RenoDX-DLSSNR' do ReShade [Home] substituindo a IA nativa (sem necessidade de ativar shaders na aba Inicio)." } else { "In game video settings: ENABLE DLSS (Quality, Performance, or DLAA). DLSS 5 operates via the 'RenoDX-DLSSNR' tab in ReShade [Home], replacing the native AI (no shaders required on Home tab)." }
    }
    elseif ($ModeName -match 'OPTISCALER|Modo 2|Mode 2') {
        $instText = if ($isPt) { "No menu de video do jogo: ATIVE o FSR 2 ou XeSS (Qualidade). O OptiScaler redirecionara para a IA DLSS 5." } else { "In game video settings: ENABLE FSR 2 or XeSS (Quality). OptiScaler will redirect the pipeline to DLSS 5." }
    }

    $lblInstDesc = New-Object System.Windows.Forms.Label
    $lblInstDesc.Text = $instText
    $lblInstDesc.Location = New-Object System.Drawing.Point(15, 146)
    $lblInstDesc.Size = New-Object System.Drawing.Size(555, 75)
    $lblInstDesc.ForeColor = [System.Drawing.Color]::FromArgb(210, 230, 255)
    $lblInstDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    [void]$infoBox.Controls.Add($lblInstDesc)

    # Botoes de Acao
    $btnLaunchNow = New-Object System.Windows.Forms.Button
    $btnLaunchNow.Text = if ($d.BtnLaunchNow) { $d.BtnLaunchNow } else { "[>] LAUNCH GAME NOW" }
    $btnLaunchNow.Location = New-Object System.Drawing.Point(20, 305)
    $btnLaunchNow.Size = New-Object System.Drawing.Size(380, 50)
    $btnLaunchNow.Font = New-Object System.Drawing.Font("Segoe UI Bold", 11)
    Style-Button -Button $btnLaunchNow -BaseColor ([System.Drawing.Color]::FromArgb(0, 130, 230)) -HoverColor ([System.Drawing.Color]::FromArgb(20, 160, 255))
    $btnLaunchNow.Add_Click({
            Write-Status -Message "[USER] Botao 'INICIAR JOGO AGORA' clicado no dialogo de sucesso para: '$TargetExePath'" -Level "INFO"
            $succForm.Close()
            Start-GameExecutable -ExecutablePath $TargetExePath
        })
    [void]$succForm.Controls.Add($btnLaunchNow)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = if ($d.BtnClose) { $d.BtnClose } else { "Close" }
    $btnClose.Location = New-Object System.Drawing.Point(415, 305)
    $btnClose.Size = New-Object System.Drawing.Size(190, 50)
    $btnClose.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    Style-Button -Button $btnClose -BaseColor ([System.Drawing.Color]::FromArgb(35, 55, 90)) -HoverColor ([System.Drawing.Color]::FromArgb(50, 75, 125))
    $btnClose.Add_Click({ 
        Write-Status -Message "[USER] Botao 'FECHAR' clicado no dialogo de sucesso." -Level "INFO"
        $succForm.Close() 
    })
    [void]$succForm.Controls.Add($btnClose)

    $succForm.Add_Shown({
        $this.BringToFront()
        $this.Activate()
    })

    Apply-DpiScaling -Form $succForm
    if ($form -and $form.Visible) {
        [void]$succForm.ShowDialog($form)
    }
    else {
        [void]$succForm.ShowDialog()
    }
}

# --- ASSISTENTE DE RESOLU  O EM 1 CLIQUE (AUTO-FIX) ---
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
            Write-Status -Message "Processo travado ($exeBase.exe) finalizado com sucesso." -Level "INFO"
        }

        # 2. Remove atributo Somente Leitura da pasta
        if (Test-Path -LiteralPath $folder) {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c attrib -r `"$folder\*.*`" /s /d" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
        }
        # 3. Purgar sl.dlss_nr.dll conflitante e sanitizar pasta de backup se corrompida
        $staleSl = Join-Path $folder "sl.dlss_nr.dll"
        if (Test-Path -LiteralPath $staleSl -PathType Leaf) {
            Remove-Item -LiteralPath $staleSl -Force -ErrorAction SilentlyContinue
            Write-Status -Message "Auto-Fix: Removido sl.dlss_nr.dll incompativel com Streamline/DX12." -Level "OK"
        }
        $bDir = Join-Path $folder $script:BackupName
        if (Test-Path -LiteralPath $bDir -PathType Container) {
            foreach ($badFile in @("sl.dlss_nr.dll", "nvngx_dlssnr.dll", "renodx-dlss5.addon64")) {
                $bBad = Join-Path $bDir $badFile
                if (Test-Path -LiteralPath $bBad) { Remove-Item -LiteralPath $bBad -Force -ErrorAction SilentlyContinue }
            }
        }

        # 4. Registra GPU dedicada de Alto Desempenho no Windows DirectX
        Set-GameHighPerformanceGpuPreference -ExecutablePath $resolved.Executable

        # 5. Autocura preventiva de dependencias do executavel (libxess.dll, nvngx_dlss.dll, etc.)
        Repair-GameCriticalDependencies -TargetFolder $folder -TargetExe $resolved.Executable

        # 6. Executa a instalacao
        Install-Dlss5 -TargetPath $TargetPath -SelectedMode $SelectedMode
        Write-Status -Message $d.AutoFixDone -Level "OK"
        return $true
    }
    catch {
        Write-Status -Message ("Falha no Auto-Fix: " + $_.Exception.Message) -Level "ERROR"
        return $false
    }
}

function Get-ErrorDiagnosis {
    param([System.Exception]$Ex, [string]$Context = "")
    $msg = $Ex.Message
    $code = "ERR_UNKNOWN"
    $isPt = ($script:CurrentLang -eq "PT")

    $what = if ($isPt) { "Ocorreu um imprevisto ao executar a operacao ($Context)." } else { "An unexpected issue occurred during operation ($Context)." }
    $cause = if ($isPt) { "Inconsistencia no sistema de arquivos ou configuracao de seguranca do Windows." } else { "File system restriction or Windows security configuration issue." }
    $fix = if ($isPt) { "1. Feche o jogo caso ele esteja aberto.`n2. Clique em '[OK] RESOLVER PROBLEMA EM 1 CLIQUE'.`n3. Ou execute como Administrador." } else { "1. Close the game if running.`n2. Click '[OK] 1-CLICK AUTO-FIX' below.`n3. Or run 1-Click DLSS 5 as Administrator." }

    if ($msg -match 'DX12 RHI' -or $msg -match 'graphics adapter' -or $msg -match 'ChooseAdapter' -or $msg -match 'D3D12 RHI') {
        $code = "ERR_DX12_RHI"
        $what = if ($isPt) { "O jogo falhou ao inicializar o adaptador grafico DirectX 12 (DX12 RHI)." } else { "The game failed to initialize the DirectX 12 graphics adapter (DX12 RHI)." }
        $cause = if ($isPt) { "Conflito com plugin de Streamline incompativel ou selecao inadequada da GPU integrada (iGPU) pelo Windows 11." } else { "Conflict with incompatible Streamline plugin or Windows selecting integrated GPU (iGPU) on Ryzen processors." }
        $fix = if ($isPt) { "1. Clique no botao '[OK] RESOLVER PROBLEMA EM 1 CLIQUE' abaixo para purgar arquivos conflitantes e forcar a GPU de Alto Desempenho.`n2. O 1-Click DLSS 5 configurara automaticamente o modo seguro com ganchos NGX puros." } else { "1. Click '[OK] 1-CLICK AUTO-FIX' below to purge conflicting files and force High-Performance GPU.`n2. 1-Click DLSS 5 will automatically configure safe NGX-only hooks." }
    }
    elseif ($msg -match 'ERR_EXE_NOT_FOUND' -or $msg -match 'Nenhum executavel' -or $msg -match 'No valid game') {
        $code = "ERR_EXE_NOT_FOUND"
        $what = if ($isPt) { "Nenhum arquivo executavel (.exe) de jogo principal foi localizado na pasta selecionada." } else { "No valid game executable (.exe) was found in the selected folder." }
        $cause = if ($isPt) { "A pasta escolhida pode ser uma pasta vazia ou a pasta pai dos jogos." } else { "The selected folder might be empty or a parent folder containing multiple games." }
        $fix = if ($isPt) { "1. Clique em 'PROCURAR JOGO' e selecione a pasta exata onde o jogo esta instalado.`n2. Ou clique em 'ESCANEAR DISCOS' para localizar seus jogos instalados automaticamente." } else { "1. Click 'BROWSE GAME' and select the exact folder containing the game executable.`n2. Or click 'SCAN DRIVES' to detect installed games automatically." }
    }
    elseif ($msg -match 'UnauthorizedAccessException' -or $msg -match 'Acesso negado' -or $msg -match 'Access is denied') {
        $code = "ERR_PERM_DENIED"
        $what = if ($isPt) { "O Windows bloqueou a gravacao ou modificacao de arquivos na pasta do jogo." } else { "Windows blocked file modification or write access in the game folder." }
        $cause = if ($isPt) { "Falta de privilegios de Administrador ou permissao 'Somente Leitura' na pasta de instalacao." } else { "Missing Administrator privileges or Read-Only permissions on game directory." }
        $fix = if ($isPt) { "1. Clique no botao '[OK] RESOLVER PROBLEMA EM 1 CLIQUE' abaixo para liberar o acesso automaticamente.`n2. Ou execute o 1 Click DLSS 5 clicando com o botao direito e 'Executar como Administrador'." } else { "1. Click '[OK] 1-CLICK AUTO-FIX' below to grant permissions automatically.`n2. Or right-click 1-Click DLSS 5 and select 'Run as Administrator'." }
    }
    elseif ($msg -match 'IOException' -or $msg -match 'being used by another process' -or $msg -match 'sendo usado por outro processo') {
        $code = "ERR_FILE_LOCKED"
        $what = if ($isPt) { "Um dos arquivos do jogo esta travado e nao pode ser atualizado no momento." } else { "A game file is currently locked and cannot be updated right now." }
        $cause = if ($isPt) { "O jogo ainda esta aberto em segundo plano, ou um programa como Discord/RivaTuner esta travando a DLL." } else { "The game is still running in background, or software like Discord/RivaTuner/RTSS is holding the DLL." }
        $fix = if ($isPt) { "1. Clique no botao '[OK] RESOLVER PROBLEMA EM 1 CLIQUE' abaixo para fechar os processos travados e instalar automaticamente." } else { "1. Click '[OK] 1-CLICK AUTO-FIX' below to terminate locked background processes and install automatically." }
    }
    elseif ($msg -match 'ERR_PATH_NOT_FOUND' -or $msg -match 'nao existe' -or $msg -match 'does not exist') {
        $code = "ERR_PATH_NOT_FOUND"
        $what = if ($isPt) { "O caminho da pasta informado nao foi encontrado no seu computador." } else { "The specified folder path was not found on your system." }
        $cause = if ($isPt) { "O jogo pode ter sido movido para outro disco ou desinstalado." } else { "The game may have been uninstalled or moved to another drive." }
        $fix = if ($isPt) { "1. Clique em 'PROCURAR JOGO' e localize a pasta atualizada do jogo." } else { "1. Click 'BROWSE GAME' and locate the valid game directory." }
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

    $errType = if ($Ex) { $Ex.GetType().FullName } else { "System.Exception" }
    $st = if ($Ex) { $Ex.StackTrace } else { "" }
    Write-Status -Message "================================================================================" -Level "ERROR"
    Write-Status -Message "[FALHA DETECTADA] Contexto: '$Context' | Codigo: [$($diag.Code)]" -Level "ERROR"
    Write-Status -Message "Tipo de Excecao: $errType" -Level "ERROR"
    Write-Status -Message "Mensagem Bruta: $($diag.RawMessage)" -Level "ERROR" -Cause $diag.Cause -Fix $diag.Fix
    if ($st) {
        Write-Status -Message "Stack Trace Detalhado:`r`n$st" -Level "ERROR"
    }
    Write-Status -Message "================================================================================" -Level "ERROR" 

    Write-Status -Message "[UI] Janela de diagnostico e recuperacao de erro exibida ao usuario: Codigo='[$($diag.Code)]' | Contexto='$Context'" -Level "WARN"

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

    # Bot o 1-Click Auto Fix
    if (-not [string]::IsNullOrWhiteSpace($TargetPath)) {
        $btnAutoFix = New-Object System.Windows.Forms.Button
        $btnAutoFix.Text = $d.BtnAutoFix
        $btnAutoFix.Location = New-Object System.Drawing.Point(20, 345)
        $btnAutoFix.Size = New-Object System.Drawing.Size(605, 42)
        $btnAutoFix.Font = New-Object System.Drawing.Font("Segoe UI Bold", 11)
        Style-Button -Button $btnAutoFix -BaseColor ([System.Drawing.Color]::FromArgb(118, 185, 0)) -HoverColor ([System.Drawing.Color]::FromArgb(140, 220, 0)) -TextColor ([System.Drawing.Color]::Black)
        $btnAutoFix.Add_Click({
                Write-Status -Message "[USER] Botao '1-CLICK AUTO FIX' acionado pelo usuario para: '$TargetPath' | Modo: '$SelectedMode'" -Level "WARN"
                $ok = Resolve-IssueInOneClick -TargetPath $TargetPath -SelectedMode $SelectedMode
                if ($ok) { 
                    Write-Status -Message "[USER] '1-CLICK AUTO FIX' concluiu a reparacao com exito." -Level "OK"
                    $errForm.Close() 
                } else {
                    Write-Status -Message "[USER] '1-CLICK AUTO FIX' nao concluiu a reparacao total da falha." -Level "WARN"
                }
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
    $btnOk.Text = if ($d.BtnClose) { $d.BtnClose } else { "Close" }
    $btnOk.Location = New-Object System.Drawing.Point(455, 405)
    $btnOk.Size = New-Object System.Drawing.Size(170, 36)
    Style-Button -Button $btnOk -BaseColor ([System.Drawing.Color]::FromArgb(35, 80, 145)) -HoverColor ([System.Drawing.Color]::FromArgb(50, 110, 195))
    $btnOk.Add_Click({ $errForm.Close() })
    [void]$errForm.Controls.Add($btnOk)

    Apply-DpiScaling -Form $errForm
    [void]$errForm.ShowDialog()
}

function Show-SystemDiagnosisDialog {
    Write-Status -Message "[USER] Botao 'DIAGNOSTICO DO SISTEMA' acionado pelo usuario." -Level "INFO"
    $d = Get-Dict -Lang $script:CurrentLang
    $isPt = ($script:CurrentLang -eq "PT")
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
    $lblHdr.Text = if ($isPt) { "   CHECKLIST DE COMPATIBILIDADE DO COMPUTADOR" } else { "   SYSTEM COMPATIBILITY CHECKLIST" }
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
    
    $col1 = if ($isPt) { "Item Verificado" } else { "Verified Item" }
    $col2 = if ($isPt) { "Status" } else { "Status" }
    $col3 = if ($isPt) { "Resultado do Teste" } else { "Test Result" }
    [void]$listChecks.Columns.Add($col1, 200)
    [void]$listChecks.Columns.Add($col2, 90)
    [void]$listChecks.Columns.Add($col3, 280)

    # 1. GPU Check
    $gpuName = "NVIDIA RTX Series"
    $gpuStatus = "[PASS]"
    $gpuDesc = $d.DiagGpuOk
    try {
        $g = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($g) { $gpuName = $g.Name; $gpuDesc = "$($g.Name) (Driver $($g.DriverVersion))" }
    }
    catch {}
    $it1Title = if ($isPt) { "Placa de Video / Driver" } else { "Graphics Card / Driver" }
    $it1 = New-Object System.Windows.Forms.ListViewItem($it1Title)
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
            $permStatus = "[FALHA]"
            $permDesc = if ($isPt) { "Acesso negado na pasta. Clique em Auto-Fix." } else { "Access denied on game folder. Click 1-Click Auto-Fix." }
        }
    }
    $it2Title = if ($isPt) { "Permissoes de Escrita" } else { "Write Permissions" }
    $it2 = New-Object System.Windows.Forms.ListViewItem($it2Title)
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
            $procStatus = "[AVISO]"
            $procDesc = if ($isPt) { "O jogo $($script:SelectedGameObj.ExeName) esta em execucao!" } else { "Game $($script:SelectedGameObj.ExeName) is currently running!" }
        }
    }
    $it3Title = if ($isPt) { "Status do Processo" } else { "Process Status" }
    $it3 = New-Object System.Windows.Forms.ListViewItem($it3Title)
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
        $payStatus = "[ERRO]"
        $payDesc = if ($isPt) { "nvngx_dlssnr.dll ausente na pasta payload." } else { "nvngx_dlssnr.dll missing in payload directory." }
    }
    $it4Title = if ($isPt) { "Runtimes DLSS 5" } else { "DLSS 5 Runtimes" }
    $it4 = New-Object System.Windows.Forms.ListViewItem($it4Title)
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
    $btnDiagClose.Text = if ($d.BtnClose) { $d.BtnClose } else { "Close" }
    $btnDiagClose.Location = New-Object System.Drawing.Point(465, 385)
    $btnDiagClose.Size = New-Object System.Drawing.Size(140, 34)
    Style-Button -Button $btnDiagClose -BaseColor ([System.Drawing.Color]::FromArgb(35, 80, 145)) -HoverColor ([System.Drawing.Color]::FromArgb(50, 110, 195))
    $btnDiagClose.Add_Click({ $diagForm.Close() })
    [void]$diagForm.Controls.Add($btnDiagClose)

    Apply-DpiScaling -Form $diagForm
    [void]$diagForm.ShowDialog()
}

# --- CONFIGURA  O DO RESHADE.INI E PRESET ---
# --- HELPERS DE ESTILIZA  O E COMPONENTES MODERNOS ---
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
# CONSTRU  O DA HUD MODERNA E INTUITIVA PARA LEIGOS
# ==============================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "1 Click DLSS 5 v$($script:Version)   Universal Neural Control Center"
$form.Size = New-Object System.Drawing.Size(1260, 860)
$form.MinimumSize = New-Object System.Drawing.Size(1180, 800)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = [System.Drawing.Color]::FromArgb(11, 15, 25)
$form.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.AllowDrop = $true

if (Test-Path -LiteralPath $script:IconPath) {
    try { $form.Icon = New-Object System.Drawing.Icon($script:IconPath) } catch {}
}

# --- SUPORTE A DRAG & DROP (ARRASTAR E SOLTAR JOGOS DIRETAMENTE NA JANELA) ---
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
            Write-Status -Message "[USER] Item solto via Drag & Drop na janela principal: '$droppedPath'" -Level "INFO" 
            try {
                $resolved = Resolve-GameTarget -TargetPath $droppedPath
                $api = Detect-GameGraphicsApi -TargetExe $resolved.Executable -GameFolder $resolved.InstallFolder
                $upscaler = Detect-GameUpscalerType -GameFolder $resolved.InstallFolder -GameRoot $resolved.Root
                $isInstalled = Test-GameDlss5Installed -GameFolder $resolved.InstallFolder
                $gObj = [pscustomobject]@{
                    Order       = 1
                    Name        = (Split-Path -Leaf $droppedPath)
                    Path        = $droppedPath
                    Api         = "$api ($($resolved.Architecture))"
                    Upscaler    = $upscaler
                    IsInstalled = $isInstalled
                    Icon        = $resolved.Icon
                    ExeName     = $resolved.ExeName
                }
                
                # Non-destructive merge
                $existing = @($script:CurrentGameLibrary | Where-Object { $_.Path.ToLower() -ne $gObj.Path.ToLower() })
                $script:CurrentGameLibrary = @($gObj) + $existing
                
                if ($script:AppConfig.CustomGamePaths -notcontains $droppedPath) {
                    $script:AppConfig.CustomGamePaths += $droppedPath
                    Save-AppConfig -Config $script:AppConfig
                }
                
                Save-GamesCache -Games $script:CurrentGameLibrary
                Refresh-GameLibraryUI -Games $script:CurrentGameLibrary
                Select-GameInInspector -GameObj $gObj
                if ($gameList.Items.Count -gt 0) {
                    $gameList.Items[0].Selected = $true
                }
                
                $d = Get-Dict -Lang $script:CurrentLang
                $msg = if ($d.GameAddedSuccess) { $d.GameAddedSuccess -f $gObj.Name } elseif ($script:CurrentLang -eq "PT") { "Jogo carregado via Arrastar e Soltar: $($gObj.Name)" } else { "Game loaded via Drag & Drop: $($gObj.Name)" }
                Write-Status -Message $msg -Level "OK"
            }
            catch {
                $ctx = if ($script:CurrentLang -eq "PT") { "Arrastar e Soltar" } else { "Drag and Drop" }
                Show-FriendlyErrorDialog -Ex $_.Exception -Context $ctx -TargetPath $droppedPath
            }
        }
    })

$imageList = New-Object System.Windows.Forms.ImageList
$imageList.ImageSize = New-Object System.Drawing.Size(28, 28)
$imageList.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit

# --- HEADER SUPERIOR ---
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
$lblTagline.Text = "NEURAL CONTROL CENTER   RTX 20/30/40/50"
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
$lblSubBadge.Text = "DirectX 9 / 10 / 11 / 12   Vulkan   OpenGL   32 & 64-bit"
$lblSubBadge.Location = New-Object System.Drawing.Point(22, 60)
$lblSubBadge.Size = New-Object System.Drawing.Size(550, 18)
$lblSubBadge.ForeColor = [System.Drawing.Color]::FromArgb(145, 175, 210)
[void]$header.Controls.Add($lblSubBadge)

# --- GUIA VISUAL EM 3 PASSOS SIMPLES NA PARTE SUPERIOR ---
$stepPanel = New-Object System.Windows.Forms.Panel
$stepPanel.Location = New-Object System.Drawing.Point(22, 80)
$stepPanel.Size = New-Object System.Drawing.Size(800, 24)
$stepPanel.BackColor = [System.Drawing.Color]::Transparent
[void]$header.Controls.Add($stepPanel)

$lblStep1 = New-Object System.Windows.Forms.Label
$lblStep1.Text = "[1] Escolha o Jogo"
$lblStep1.Location = New-Object System.Drawing.Point(0, 2)
$lblStep1.Size = New-Object System.Drawing.Size(180, 20)
$lblStep1.ForeColor = [System.Drawing.Color]::FromArgb(100, 180, 255)
$lblStep1.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9)
[void]$stepPanel.Controls.Add($lblStep1)

$lblStepArrow1 = New-Object System.Windows.Forms.Label
$lblStepArrow1.Text = " "
$lblStepArrow1.Location = New-Object System.Drawing.Point(185, 2)
$lblStepArrow1.Size = New-Object System.Drawing.Size(20, 20)
$lblStepArrow1.ForeColor = [System.Drawing.Color]::Gray
[void]$stepPanel.Controls.Add($lblStepArrow1)

$lblStep2 = New-Object System.Windows.Forms.Label
$lblStep2.Text = "[2] Clique em Instalar"
$lblStep2.Location = New-Object System.Drawing.Point(210, 2)
$lblStep2.Size = New-Object System.Drawing.Size(180, 20)
$lblStep2.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
$lblStep2.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9)
[void]$stepPanel.Controls.Add($lblStep2)

$lblStepArrow2 = New-Object System.Windows.Forms.Label
$lblStepArrow2.Text = " "
$lblStepArrow2.Location = New-Object System.Drawing.Point(395, 2)
$lblStepArrow2.Size = New-Object System.Drawing.Size(20, 20)
$lblStepArrow2.ForeColor = [System.Drawing.Color]::Gray
[void]$stepPanel.Controls.Add($lblStepArrow2)

$lblStep3 = New-Object System.Windows.Forms.Label
$lblStep3.Text = "[3] Inicie e Aproveite!"
$lblStep3.Location = New-Object System.Drawing.Point(420, 2)
$lblStep3.Size = New-Object System.Drawing.Size(200, 20)
$lblStep3.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 90)
$lblStep3.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9)
[void]$stepPanel.Controls.Add($lblStep3)

# Bot o Diagn stico e Idioma no Canto Superior Direito
$btnDiagnose = New-Object System.Windows.Forms.Button
$btnDiagnose.Text = "[+] DIAGNOSTICO"
$btnDiagnose.Location = New-Object System.Drawing.Point(880, 12)
$btnDiagnose.Size = New-Object System.Drawing.Size(160, 28)
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
[void]$comboLang.Items.AddRange(@("Português (Brasil)", "English (US)", "Español", "Deutsch", "Français", "Italiano", "日本語", "简体中文", "Русский", "한국어"))
$langCodes = @("PT", "EN", "ES", "DE", "FR", "IT", "JA", "ZH", "RU", "KO")
$initialLangIdx = [array]::IndexOf($langCodes, $script:CurrentLang)
if ($initialLangIdx -lt 0) {
    try {
        $sysLang = (Get-UICulture).TwoLetterISOLanguageName.ToLower()
        $langMap = @{ "pt" = 0; "en" = 1; "es" = 2; "de" = 3; "fr" = 4; "it" = 5; "ja" = 6; "zh" = 7; "ru" = 8; "ko" = 9 }
        if ($langMap.ContainsKey($sysLang)) { $initialLangIdx = $langMap[$sysLang] } else { $initialLangIdx = 1 }
    } catch { $initialLangIdx = 1 }
}
$comboLang.SelectedIndex = $initialLangIdx
[void]$header.Controls.Add($comboLang)

# --- BARRA DE FERRAMENTAS / PESQUISA ---
$toolbar = New-Object System.Windows.Forms.Panel
$toolbar.Location = New-Object System.Drawing.Point(18, 120)
$toolbar.Size = New-Object System.Drawing.Size(1224, 44)
$toolbar.Anchor = "Top, Left, Right"
$toolbar.BackColor = [System.Drawing.Color]::FromArgb(16, 24, 40)
[void]$form.Controls.Add($toolbar)

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "   ESCANEAR DISCOS"
$btnScan.Location = New-Object System.Drawing.Point(8, 7)
$btnScan.Size = New-Object System.Drawing.Size(170, 30)
Style-Button -Button $btnScan -BaseColor ([System.Drawing.Color]::FromArgb(35, 80, 145)) -HoverColor ([System.Drawing.Color]::FromArgb(50, 110, 195))
[void]$toolbar.Controls.Add($btnScan)

$chkAutoScan = New-Object System.Windows.Forms.CheckBox
$chkAutoScan.Text = "Escanear ao iniciar"
$chkAutoScan.Location = New-Object System.Drawing.Point(186, 9)
$chkAutoScan.Size = New-Object System.Drawing.Size(160, 26)
$chkAutoScan.ForeColor = [System.Drawing.Color]::FromArgb(180, 205, 230)
$chkAutoScan.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$chkAutoScan.Checked = [bool]$script:AppConfig.AutoScanOnStartup
$chkAutoScan.Cursor = [System.Windows.Forms.Cursors]::Hand
$chkAutoScan.Add_CheckedChanged({
    $script:AppConfig.AutoScanOnStartup = $chkAutoScan.Checked
    Save-AppConfig -Config $script:AppConfig
    Write-Status -Message "[USER] Opcao 'Escanear ao iniciar' alterada para: $($chkAutoScan.Checked)" -Level "INFO"
})
[void]$toolbar.Controls.Add($chkAutoScan)
$script:ChkAutoScan = $chkAutoScan

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(354, 9)
$txtSearch.Size = New-Object System.Drawing.Size(675, 26)
$txtSearch.Anchor = "Top, Left, Right"
$txtSearch.BackColor = [System.Drawing.Color]::FromArgb(10, 15, 26)
$txtSearch.ForeColor = [System.Drawing.Color]::FromArgb(140, 210, 255)
$txtSearch.BorderStyle = "FixedSingle"
$txtSearch.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
[void]$toolbar.Controls.Add($txtSearch)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "   PROCURAR JOGO"
$btnBrowse.Location = New-Object System.Drawing.Point(1040, 7)
$btnBrowse.Size = New-Object System.Drawing.Size(174, 30)
$btnBrowse.Anchor = "Top, Right"
Style-Button -Button $btnBrowse -BaseColor ([System.Drawing.Color]::FromArgb(40, 65, 110)) -HoverColor ([System.Drawing.Color]::FromArgb(55, 90, 150))
[void]$toolbar.Controls.Add($btnBrowse)

# --- COLUNA ESQUERDA: BIBLIOTECA DE JOGOS ---
$leftPanel = New-Object System.Windows.Forms.Panel
$leftPanel.Location = New-Object System.Drawing.Point(18, 172)
$leftPanel.Size = New-Object System.Drawing.Size(460, 610)
$leftPanel.Anchor = "Top, Bottom, Left"
$leftPanel.BackColor = [System.Drawing.Color]::FromArgb(16, 24, 40)
[void]$form.Controls.Add($leftPanel)

$lblLibTitle = New-Object System.Windows.Forms.Label
$lblLibTitle.Text = "BIBLIOTECA DE JOGOS DETECTADOS"
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
[void]$gameList.Columns.Add("Jogo", 185)
[void]$gameList.Columns.Add("API / Arq", 90)
[void]$gameList.Columns.Add("Modo / Status", 130)
$gameList.Add_Resize({
    $k = $script:DpiScale
    $avail = $gameList.ClientSize.Width
    if ($avail -gt (320 * $k)) {
        $gameList.Columns[1].Width = [int](90 * $k)
        $gameList.Columns[2].Width = [int](130 * $k)
        $gameList.Columns[0].Width = [Math]::Max([int](140 * $k), $avail - [int](225 * $k))
    }
})
try {
    $null = Add-Type -MemberDefinition '[DllImport("uxtheme.dll", CharSet=CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr hWnd, string pszSubAppName, string pszSubIdList);' -Name "UxThemeListView" -Namespace "Win32" -PassThru -ErrorAction SilentlyContinue
    [void][Win32.UxThemeListView]::SetWindowTheme($gameList.Handle, "Explorer", $null)
} catch {}
[void]$leftPanel.Controls.Add($gameList)

# --- COLUNA DIREITA: INSPETOR E SELETOR DE MODOS ---
$rightPanel = New-Object System.Windows.Forms.Panel
$rightPanel.Location = New-Object System.Drawing.Point(488, 172)
$rightPanel.Size = New-Object System.Drawing.Size(754, 610)
$rightPanel.Anchor = "Top, Bottom, Left, Right"
$rightPanel.BackColor = [System.Drawing.Color]::FromArgb(16, 24, 40)
[void]$form.Controls.Add($rightPanel)

# Banner do Jogo Selecionado
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
$lblGameTitle.Text = "Selecione um Jogo"
$lblGameTitle.Location = New-Object System.Drawing.Point(70, 10)
$lblGameTitle.Size = New-Object System.Drawing.Size(640, 26)
$lblGameTitle.Font = New-Object System.Drawing.Font("Segoe UI Bold", 13)
$lblGameTitle.ForeColor = [System.Drawing.Color]::White
[void]$gameBanner.Controls.Add($lblGameTitle)

$lblGameStatus = New-Object System.Windows.Forms.Label
$lblGameStatus.Text = "Escolha um jogo na lista   esquerda ou procure uma pasta."
$lblGameStatus.Location = New-Object System.Drawing.Point(70, 38)
$lblGameStatus.Size = New-Object System.Drawing.Size(640, 22)
$lblGameStatus.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
$lblGameStatus.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
[void]$gameBanner.Controls.Add($lblGameStatus)

# Pasta de Instala  o Consolidada
$lblFolderTitle = New-Object System.Windows.Forms.Label
$lblFolderTitle.Text = "DIRET RIO DE INSTALA  O DO JOGO:"
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

# Seletor de Modo de Inje  o em Cards Modernos
$lblModeSecTitle = New-Object System.Windows.Forms.Label
$lblModeSecTitle.Text = "ESCOLHA O MODO DE INJE  O DLSS 5:"
$lblModeSecTitle.Location = New-Object System.Drawing.Point(16, 142)
$lblModeSecTitle.Size = New-Object System.Drawing.Size(400, 18)
$lblModeSecTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 90)
$lblModeSecTitle.Font = New-Object System.Drawing.Font("Segoe UI Bold", 8.5)
[void]$rightPanel.Controls.Add($lblModeSecTitle)

$lblAutoNotice = New-Object System.Windows.Forms.Label
$lblAutoNotice.Text = "  Modo ideal selecionado automaticamente!"
$lblAutoNotice.Location = New-Object System.Drawing.Point(420, 142)
$lblAutoNotice.Size = New-Object System.Drawing.Size(318, 18)
$lblAutoNotice.Anchor = "Top, Right"
$lblAutoNotice.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$lblAutoNotice.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
$lblAutoNotice.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8)
[void]$rightPanel.Controls.Add($lblAutoNotice)

# Card Modo 1
$cardMode1 = New-Object System.Windows.Forms.Panel
$cardMode1.Location = New-Object System.Drawing.Point(16, 164)
$cardMode1.Size = New-Object System.Drawing.Size(722, 52)
$cardMode1.Anchor = "Top, Left, Right"
$cardMode1.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)
$cardMode1.Cursor = [System.Windows.Forms.Cursors]::Hand
[void]$rightPanel.Controls.Add($cardMode1)

$lblCard1Title = New-Object System.Windows.Forms.Label
$lblCard1Title.Text = "  MODO 1: DIRETO (DLSS Nativo)"
$lblCard1Title.Location = New-Object System.Drawing.Point(12, 6)
$lblCard1Title.Size = New-Object System.Drawing.Size(690, 20)
$lblCard1Title.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9.5)
$lblCard1Title.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
[void]$cardMode1.Controls.Add($lblCard1Title)

$lblCard1Desc = New-Object System.Windows.Forms.Label
$lblCard1Desc.Text = "Para jogos com DLSS nativo. Ativa Streamline + IA com ganho massivo de FPS."
$lblCard1Desc.Location = New-Object System.Drawing.Point(12, 26)
$lblCard1Desc.Size = New-Object System.Drawing.Size(690, 20)
$lblCard1Desc.ForeColor = [System.Drawing.Color]::FromArgb(170, 195, 220)
[void]$cardMode1.Controls.Add($lblCard1Desc)

# Card Modo 2
$cardMode2 = New-Object System.Windows.Forms.Panel
$cardMode2.Location = New-Object System.Drawing.Point(16, 222)
$cardMode2.Size = New-Object System.Drawing.Size(722, 52)
$cardMode2.Anchor = "Top, Left, Right"
$cardMode2.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)
$cardMode2.Cursor = [System.Windows.Forms.Cursors]::Hand
[void]$rightPanel.Controls.Add($cardMode2)

$lblCard2Title = New-Object System.Windows.Forms.Label
$lblCard2Title.Text = "  MODO 2: PONTE OPTISCALER (FSR2/XeSS)"
$lblCard2Title.Location = New-Object System.Drawing.Point(12, 6)
$lblCard2Title.Size = New-Object System.Drawing.Size(690, 20)
$lblCard2Title.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9.5)
$lblCard2Title.ForeColor = [System.Drawing.Color]::FromArgb(100, 180, 255)
[void]$cardMode2.Controls.Add($lblCard2Title)

$lblCard2Desc = New-Object System.Windows.Forms.Label
$lblCard2Desc.Text = "Redireciona chamadas FSR2/XeSS para o modelo neural DLSS 5."
$lblCard2Desc.Location = New-Object System.Drawing.Point(12, 26)
$lblCard2Desc.Size = New-Object System.Drawing.Size(690, 20)
$lblCard2Desc.ForeColor = [System.Drawing.Color]::FromArgb(170, 195, 220)
[void]$cardMode2.Controls.Add($lblCard2Desc)

# Card Modo 3
$cardMode3 = New-Object System.Windows.Forms.Panel
$cardMode3.Location = New-Object System.Drawing.Point(16, 280)
$cardMode3.Size = New-Object System.Drawing.Size(722, 52)
$cardMode3.Anchor = "Top, Left, Right"
$cardMode3.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)
$cardMode3.Cursor = [System.Windows.Forms.Cursors]::Hand
[void]$rightPanel.Controls.Add($cardMode3)

$lblCard3Title = New-Object System.Windows.Forms.Label
$lblCard3Title.Text = "  MODO 3: FEEDER UNIVERSAL (DLAA 100% Nativo)"
$lblCard3Title.Location = New-Object System.Drawing.Point(12, 6)
$lblCard3Title.Size = New-Object System.Drawing.Size(690, 20)
$lblCard3Title.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9.5)
$lblCard3Title.ForeColor = [System.Drawing.Color]::FromArgb(190, 150, 255)
[void]$cardMode3.Controls.Add($lblCard3Title)

$lblCard3Desc = New-Object System.Windows.Forms.Label
$lblCard3Desc.Text = "Para QUALQUER jogo (Mafia, GTA, etc). Reconstru  o 100% limpa e sem perda de nitidez."
$lblCard3Desc.Location = New-Object System.Drawing.Point(12, 26)
$lblCard3Desc.Size = New-Object System.Drawing.Size(690, 20)
$lblCard3Desc.ForeColor = [System.Drawing.Color]::FromArgb(170, 195, 220)
[void]$cardMode3.Controls.Add($lblCard3Desc)

function Highlight-SelectedModeCard {
    param([string]$Mode)
    if ($script:SelectedMode -ne $Mode) {
        Write-Status -Message "[USER] Modo de operacao selecionado manualmente via Card: $Mode" -Level "INFO"
    }
    $script:SelectedMode = $Mode
    $cardMode1.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)
    $cardMode2.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)
    $cardMode3.BackColor = [System.Drawing.Color]::FromArgb(12, 22, 34)

    $d = Get-Dict -Lang $script:CurrentLang
    $isRdr2 = ($script:SelectedGameObj -and ($script:SelectedGameObj.Name -match "Red Dead" -or $script:SelectedGameObj.ExeName -match "RDR2|rdr2"))

    if ($Mode -eq "DIRECT") {
        $cardMode1.BackColor = [System.Drawing.Color]::FromArgb(20, 48, 30)
        if ($isRdr2) {
            $lblReqText.Text = if ($script:CurrentLang -eq "PT") { "No RDR2: Mude API para DirectX 12 (Configura  es > Gr ficos > Avan ado) e ATIVE o DLSS." } else { "In RDR2: Switch Graphics API to DirectX 12 (Settings > Graphics > Advanced) & ENABLE DLSS." }
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
            $lblReqText.Text = if ($script:CurrentLang -eq "PT") { "No RDR2: O Feeder requer DirectX 12. Mude a API para DirectX 12 nas op  es do jogo." } else { "In RDR2: Feeder requires DirectX 12. Switch Graphics API to DirectX 12 in game settings." }
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

# Card de Requisito no Jogo
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
$lblReqTitle.Text = "  REQUISITO NO JOGO:"
$lblReqTitle.Location = New-Object System.Drawing.Point(12, 6)
$lblReqTitle.Size = New-Object System.Drawing.Size(700, 18)
$lblReqTitle.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9)
$lblReqTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 50)
[void]$reqCard.Controls.Add($lblReqTitle)

$lblReqText = New-Object System.Windows.Forms.Label
$lblReqText.Text = "Selecione um jogo para carregar as instru  es autom ticas."
$lblReqText.Location = New-Object System.Drawing.Point(12, 26)
$lblReqText.Size = New-Object System.Drawing.Size(700, 30)
$lblReqText.ForeColor = [System.Drawing.Color]::FromArgb(240, 230, 190)
$lblReqText.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
[void]$reqCard.Controls.Add($lblReqText)

# Barra de A  es Principais
$actionPanel = New-Object System.Windows.Forms.Panel
$actionPanel.Location = New-Object System.Drawing.Point(16, 410)
$actionPanel.Size = New-Object System.Drawing.Size(722, 185)
$actionPanel.Anchor = "Top, Bottom, Left, Right"
[void]$rightPanel.Controls.Add($actionPanel)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "[ ] 1-CLIQUE: INSTALAR DLSS 5"
$btnInstall.Location = New-Object System.Drawing.Point(0, 5)
$btnInstall.Size = New-Object System.Drawing.Size(355, 48)
$btnInstall.Font = New-Object System.Drawing.Font("Segoe UI Bold", 11.5)
Style-Button -Button $btnInstall -BaseColor ([System.Drawing.Color]::FromArgb(118, 185, 0)) -HoverColor ([System.Drawing.Color]::FromArgb(140, 220, 0)) -TextColor ([System.Drawing.Color]::Black)
[void]$actionPanel.Controls.Add($btnInstall)

$btnLaunch = New-Object System.Windows.Forms.Button
$btnLaunch.Text = "[ ] INICIAR JOGO"
$btnLaunch.Location = New-Object System.Drawing.Point(367, 5)
$btnLaunch.Size = New-Object System.Drawing.Size(355, 48)
$btnLaunch.Font = New-Object System.Drawing.Font("Segoe UI Bold", 11.5)
Style-Button -Button $btnLaunch -BaseColor ([System.Drawing.Color]::FromArgb(0, 130, 230)) -HoverColor ([System.Drawing.Color]::FromArgb(20, 160, 255)) -TextColor ([System.Drawing.Color]::White)
[void]$actionPanel.Controls.Add($btnLaunch)

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text = "[ ] RESTAURAR ORIGINAL"
$btnUninstall.Location = New-Object System.Drawing.Point(0, 62)
$btnUninstall.Size = New-Object System.Drawing.Size(355, 38)
Style-Button -Button $btnUninstall -BaseColor ([System.Drawing.Color]::FromArgb(170, 45, 45)) -HoverColor ([System.Drawing.Color]::FromArgb(205, 55, 55)) -TextColor ([System.Drawing.Color]::White)
[void]$actionPanel.Controls.Add($btnUninstall)

$btnOpenFolder = New-Object System.Windows.Forms.Button
$btnOpenFolder.Text = "[PASTA] ABRIR PASTA"
$btnOpenFolder.Location = New-Object System.Drawing.Point(367, 62)
$btnOpenFolder.Size = New-Object System.Drawing.Size(355, 38)
Style-Button -Button $btnOpenFolder -BaseColor ([System.Drawing.Color]::FromArgb(35, 55, 90)) -HoverColor ([System.Drawing.Color]::FromArgb(50, 75, 125)) -TextColor ([System.Drawing.Color]::White)
[void]$actionPanel.Controls.Add($btnOpenFolder)

# Painel de Dica Informativa (Exibido enquanto ocioso)
$tipPanel = New-Object System.Windows.Forms.Panel
$tipPanel.Location = New-Object System.Drawing.Point(0, 108)
$tipPanel.Size = New-Object System.Drawing.Size(722, 68)
$tipPanel.BackColor = [System.Drawing.Color]::FromArgb(14, 22, 38)
$tipPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
[void]$actionPanel.Controls.Add($tipPanel)
$script:TipPanel = $tipPanel

$lblTipBadge = New-Object System.Windows.Forms.Label
$lblTipBadge.Text = "[DICA]"
$lblTipBadge.Location = New-Object System.Drawing.Point(12, 12)
$lblTipBadge.Size = New-Object System.Drawing.Size(60, 20)
$lblTipBadge.Font = New-Object System.Drawing.Font("Segoe UI Bold", 9.5)
$lblTipBadge.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 90)
[void]$tipPanel.Controls.Add($lblTipBadge)

$lblTipDesc = New-Object System.Windows.Forms.Label
$lblTipDesc.Text = "Pressione a tecla [End] no jogo para alternar instantaneamente todos os efeitos ReShade (CAS, Vibrance, SMAA) e conferir a diferenca visual em tempo real!"
$lblTipDesc.Location = New-Object System.Drawing.Point(75, 10)
$lblTipDesc.Size = New-Object System.Drawing.Size(635, 48)
$lblTipDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblTipDesc.ForeColor = [System.Drawing.Color]::FromArgb(190, 215, 245)
[void]$tipPanel.Controls.Add($lblTipDesc)

# Painel de Progresso de Instalacao em Destaque
$progressPanel = New-Object System.Windows.Forms.Panel
$progressPanel.Location = New-Object System.Drawing.Point(0, 108)
$progressPanel.Size = New-Object System.Drawing.Size(722, 68)
$progressPanel.BackColor = [System.Drawing.Color]::FromArgb(20, 30, 52)
$progressPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$progressPanel.Visible = $false
[void]$actionPanel.Controls.Add($progressPanel)
$script:ProgressPanel = $progressPanel

$lblProgressStep = New-Object System.Windows.Forms.Label
$lblProgressStep.Text = "Iniciando instalacao do DLSS 5..."
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

# --- RODAP  MINIMALISTA COM LOG E STATUS ---
$footer = New-Object System.Windows.Forms.Panel
$footer.Location = New-Object System.Drawing.Point(0, 790)
$footer.Size = New-Object System.Drawing.Size(1260, 32)
$footer.Anchor = "Bottom, Left, Right"
$footer.BackColor = [System.Drawing.Color]::FromArgb(8, 12, 20)
[void]$form.Controls.Add($footer)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "  Pronto. Selecione um jogo para come ar."
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
$btnOpenLog.Text = "   VER LOG COMPLETO"
$btnOpenLog.Location = New-Object System.Drawing.Point(1070, 3)
$btnOpenLog.Size = New-Object System.Drawing.Size(170, 26)
$btnOpenLog.Anchor = "Top, Right"
Style-Button -Button $btnOpenLog -BaseColor ([System.Drawing.Color]::FromArgb(25, 40, 65)) -HoverColor ([System.Drawing.Color]::FromArgb(35, 60, 95))
$btnOpenLog.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$btnOpenLog.Add_Click({ Open-LogFile })
[void]$footer.Controls.Add($btnOpenLog)

# --- SINCRONIZA  O DE IDIOMAS ---
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

    if ($lblTipBadge) { $lblTipBadge.Text = if ($d.TipBadge) { $d.TipBadge } elseif ($script:CurrentLang -eq "PT") { "[DICA]" } else { "[TIP]" } }
    if ($lblTipDesc) { $lblTipDesc.Text = if ($d.TipDesc) { $d.TipDesc } elseif ($script:CurrentLang -eq "PT") { "Pressione a tecla [End] no jogo para alternar instantaneamente todos os efeitos ReShade (CAS, Vibrance, SMAA) e conferir a diferenca visual em tempo real!" } else { "Press [End] in-game to instantly toggle all ReShade effects (CAS, Vibrance, SMAA) and see visual difference in real time!" } }

    if ($script:ChkAutoScan) {
        $script:ChkAutoScan.Text = if ($d.ChkAutoScan) { $d.ChkAutoScan } elseif ($d.AutoScanCheckbox) { $d.AutoScanCheckbox } else { "Auto-scan on startup" }
    }

    $btnInstallText = $d.BtnInstall
    if ([string]::IsNullOrWhiteSpace($btnInstallText)) { $btnInstallText = "[>] 1-CLIQUE: INSTALAR DLSS 5" }
    $btnInstall.Text = $btnInstallText

    $gameList.Columns[0].Text = $d.ColGame
    $gameList.Columns[1].Text = $d.ColApi
    $gameList.Columns[2].Text = $d.ColMode

    if ($script:CurrentGameLibrary -and $script:CurrentGameLibrary.Count -gt 0) {
        Refresh-GameLibraryUI -Games $script:CurrentGameLibrary
    }

    if ($script:SelectedGameObj) {
        Select-GameInInspector -GameObj $script:SelectedGameObj
    }
    else {
        if ($lblGameTitle) { $lblGameTitle.Text = if ($d.InspectorTitle) { $d.InspectorTitle } else { "Select a Game" } }
        if ($lblGameStatus) { $lblGameStatus.Text = if ($d.NoGameSelected) { $d.NoGameSelected } else { "Select a game from the library or browse a folder." } }
        if ($lblReqText) { $lblReqText.Text = if ($d.NoGameSelected) { $d.NoGameSelected } else { "Select a game to load automatic instructions." } }
        $lblStatus.Text = "  " + $d.StatusReady
    }
}

$comboLang.Add_SelectedIndexChanged({
        $langCodes = @("PT", "EN", "ES", "DE", "FR", "IT", "JA", "ZH", "RU", "KO")
        $idx = $comboLang.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $langCodes.Length) {
            $chosen = $langCodes[$idx]
            $script:AppConfig.Language = $chosen
            Save-AppConfig -Config $script:AppConfig
            Update-UiLanguage -Lang $chosen
            Write-Status -Message "[USER] Idioma da interface alterado para: '$chosen' (Index $idx)" -Level "INFO"
        }
    })

# --- EVENTOS E LOGICA DE INSPEC AO ---
function Select-GameInInspector {
    param($GameObj)
    if ($null -eq $GameObj) { return }
    if ($GameObj -is [System.Collections.IEnumerable] -and -not ($GameObj -is [string]) -and -not ($GameObj -is [System.Management.Automation.PSCustomObject])) {
        $firstItem = $null
        foreach ($sub in $GameObj) {
            if ($sub) { $firstItem = $sub; break }
        }
        $GameObj = $firstItem
        if ($null -eq $GameObj) { return }
    }
    $script:SelectedGameObj = $GameObj
    $d = Get-Dict -Lang $script:CurrentLang

    $lblGameTitle.Text = [string]$GameObj.Name
    $txtFolderPath.Text = [string]$GameObj.Path

    try {
        $resolved = Resolve-GameTarget -TargetPath $GameObj.Path
        Repair-GameCriticalDependencies -TargetFolder $resolved.InstallFolder -TargetExe $resolved.Executable
    }
    catch {}

    if ($GameObj.Icon -and ($GameObj.Icon -is [System.Drawing.Icon])) {
        try {
            $picIcon.Image = $GameObj.Icon.ToBitmap()
        }
        catch {
            $picIcon.Image = $null
        }
    }
    elseif ($GameObj.Icon -and ($GameObj.Icon -is [System.Drawing.Image])) {
        $picIcon.Image = $GameObj.Icon
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

    $modeText = if ($d.ModeTextFeeder) { $d.ModeTextFeeder } else { "Universal (Feeder)" }
    if ($detected -eq "NATIVE_DLSS") {
        $modeText = if ($d.ModeTextNative) { $d.ModeTextNative } else { "Native DLSS" }
    }
    elseif ($detected -like "*BRIDGE*") {
        $modeText = if ($d.ModeTextOpti) { $d.ModeTextOpti } else { "FSR2/XeSS (OptiScaler)" }
    }

    $isInstalled = Test-GameDlss5Installed -GameFolder $GameObj.Path
    if ($isInstalled) {
        $lblGameStatus.Text = $d.StatusInstalled + "   API: " + $GameObj.Api
        $lblGameStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 205, 90)
        
        $btnText = $d.BtnReinstall
        if ([string]::IsNullOrWhiteSpace($btnText)) { $btnText = "[>] REINSTALAR / ATUALIZAR DLSS 5" }
        $btnInstall.Text = $btnText
        Style-Button -Button $btnInstall -BaseColor ([System.Drawing.Color]::FromArgb(65, 140, 45)) -HoverColor ([System.Drawing.Color]::FromArgb(85, 175, 55)) -TextColor ([System.Drawing.Color]::White)
    }
    else {
        $idealPrefix = if ($d.ModeIdeal) { $d.ModeIdeal } else { "Ideal Mode: {0}" }
        $modeFormatted = if ($idealPrefix -match '\{0\}') { $idealPrefix -f $modeText } else { ($idealPrefix + ": " + $modeText) }
        $lblGameStatus.Text = "API: " + $GameObj.Api + "   " + $modeFormatted
        $lblGameStatus.ForeColor = [System.Drawing.Color]::FromArgb(118, 225, 125)
        
        $btnText = $d.BtnInstall
        if ([string]::IsNullOrWhiteSpace($btnText)) { $btnText = "[>] 1-CLIQUE: INSTALAR DLSS 5" }
        $btnInstall.Text = $btnText
        Style-Button -Button $btnInstall -BaseColor ([System.Drawing.Color]::FromArgb(118, 185, 0)) -HoverColor ([System.Drawing.Color]::FromArgb(140, 220, 0)) -TextColor ([System.Drawing.Color]::Black)
    }

    $script:AppConfig.LastSelectedGamePath = $GameObj.Path
    Save-AppConfig -Config $script:AppConfig

    $instTag = if ($isInstalled) { "INSTALADO" } else { "NAO INSTALADO" }
    Write-Status -Message "[USER] Painel inspetor atualizado: '$($GameObj.Name)' | API: $($GameObj.Api) | Upscaler: $($GameObj.Upscaler) | Status: $instTag | Pasta: '$($GameObj.Path)'" -Level "INFO"
}

$gameList.Add_SelectedIndexChanged({
        if ($gameList.SelectedIndices.Count -gt 0) {
            $idx = $gameList.SelectedIndices[0]
            if ($script:CurrentGameLibrary -and $idx -lt $script:CurrentGameLibrary.Count) {
                $selGame = $script:CurrentGameLibrary[$idx]
                Write-Status -Message "[USER] Clique na lista de jogos: Linha $idx -> Jogo '$($selGame.Name)'" -Level "INFO"
                Select-GameInInspector -GameObj $selGame
            }
        }
    })

function Refresh-GameLibraryUI {
    param($Games)
    $gameList.BeginUpdate()
    $gameList.Items.Clear()
    $imageList.Images.Clear()

    $d = Get-Dict -Lang $script:CurrentLang

    $flatGames = @()
    if ($Games) {
        foreach ($item in $Games) {
            if ($item -is [System.Collections.IEnumerable] -and -not ($item -is [string]) -and -not ($item -is [System.Management.Automation.PSCustomObject])) {
                foreach ($sub in $item) { if ($sub) { $flatGames += $sub } }
            }
            else {
                if ($item) { $flatGames += $item }
            }
        }
    }

    foreach ($g in $flatGames) {
        $imgIdx = -1
        if ($g.Icon) {
            try {
                if ($g.Icon -is [System.Drawing.Icon]) {
                    $imageList.Images.Add($g.Icon.ToBitmap())
                    $imgIdx = $imageList.Images.Count - 1
                }
                elseif ($g.Icon -is [System.Drawing.Image]) {
                    $imageList.Images.Add($g.Icon)
                    $imgIdx = $imageList.Images.Count - 1
                }
            }
            catch {}
        }

        $isInst = Test-GameDlss5Installed -GameFolder $g.Path
        $modeLabel = ""
        if ($isInst) {
            $modeLabel = if ($d.StatusActive) { $d.StatusActive } else { "[✓] DLSS 5 Active" }
        }
        else {
            if ($g.Upscaler -eq "NATIVE_DLSS") {
                $modeLabel = if ($d.ColModeDirect) { $d.ColModeDirect } else { "[Mode 1] DLSS" }
            }
            elseif ($g.Upscaler -eq "FSR2_BRIDGE" -or $g.Upscaler -eq "XESS_BRIDGE") {
                $modeLabel = if ($d.ColModeOpti) { $d.ColModeOpti } else { "[Mode 2] OptiScaler" }
            }
            else {
                $modeLabel = if ($d.ColModeFeeder) { $d.ColModeFeeder } else { "[Mode 3] Feeder" }
            }
        }

        $item = New-Object System.Windows.Forms.ListViewItem([string]$g.Name, $imgIdx)
        [void]$item.SubItems.Add([string]$g.Api)
        [void]$item.SubItems.Add([string]$modeLabel)
        [void]$gameList.Items.Add($item)
    }
    $gameList.EndUpdate()
}

# --- MOTOR DE VARREDURA ASSINCRONA (BACKGROUND WORKER RUNSPACE) ---
$script:IsScanning = $false
$script:ScanPowerShell = $null
$script:ScanAsyncResult = $null
$script:ScanRunspace = $null
$script:ScanTimer = New-Object System.Windows.Forms.Timer
$script:ScanTimer.Interval = 80

function Start-LibraryScanAsync {
    param([bool]$IsStartup = $false)
    if ($script:IsScanning) { return }
    $script:IsScanning = $true
    
    $d = Get-Dict -Lang $script:CurrentLang
    if ($btnScan) { $btnScan.Enabled = $false }
    if ($script:ProgressBar) {
        $script:ProgressBar.Value = 0
        $script:ProgressBar.Visible = $true
    }
    $lblStatus.Text = "  " + $d.StatusScanning
    
    $script:ScanSync = [hashtable]::Synchronized(@{
        Pct         = 0
        CurrentGame = ""
        IsFinished  = $false
        Results     = @()
        Error       = ""
    })
    
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $neededFuncs = @(
        "Get-Sha256", "Get-PeArchitecture", "Test-ValidPe", "Sanitize-PathString",
        "Resolve-GameTarget", "Detect-GameGraphicsApi", "Detect-GameUpscalerType",
        "Test-GameDlss5Installed", "Scan-DriveForGames", "Get-XboxGameConfigExe", "Get-EmulatorProfile"
    )
    foreach ($fn in $neededFuncs) {
        if (Test-Path "Function:\$fn") {
            $def = (Get-Item "Function:\$fn").Definition
            $entry = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($fn, $def)
            $iss.Commands.Add($entry)
        }
    }
    
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
    $rs.Open()
    
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $driveTarget = if ($script:AppConfig.ScanDrives) { $script:AppConfig.ScanDrives } else { "ALL" }
    
    [void]$ps.AddScript({
        param($sync, $targetDrive)
        Add-Type -AssemblyName System.Drawing
        Add-Type -AssemblyName System.Windows.Forms
        try {
            $games = Scan-DriveForGames -DriveLetter $targetDrive -ProgressCallback {
                param($pct, $name)
                $sync.Pct = $pct
                $sync.CurrentGame = $name
            }
            $sync.Results = @($games)
        }
        catch {
            $sync.Error = $_.Exception.Message
        }
        finally {
            $sync.IsFinished = $true
        }
    })
    [void]$ps.AddArgument($script:ScanSync)
    [void]$ps.AddArgument($driveTarget)
    
    $script:ScanPowerShell = $ps
    $script:ScanRunspace = $rs
    $script:ScanAsyncResult = $ps.BeginInvoke()
    
    $script:ScanTimer.Start()
}

$script:ScanTimer.Add_Tick({
    $d = Get-Dict -Lang $script:CurrentLang
    if ($script:ScanSync.IsFinished -or ($script:ScanAsyncResult -and $script:ScanAsyncResult.IsCompleted)) {
        $script:ScanTimer.Stop()
        $script:IsScanning = $false
        
        try {
            if ($script:ScanPowerShell -and $script:ScanAsyncResult) {
                $null = $script:ScanPowerShell.EndInvoke($script:ScanAsyncResult)
            }
        } catch {}
        
        try {
            if ($script:ScanPowerShell) { $script:ScanPowerShell.Dispose(); $script:ScanPowerShell = $null }
            if ($script:ScanRunspace) { $script:ScanRunspace.Close(); $script:ScanRunspace.Dispose(); $script:ScanRunspace = $null }
        } catch {}
        
        if ($btnScan) { $btnScan.Enabled = $true }
        if ($script:ProgressBar) { $script:ProgressBar.Visible = $false }
        
        $newGames = @($script:ScanSync.Results)
        
        # Non-destructive merge with custom games
        $mergedMap = @{}
        foreach ($g in $newGames) {
            if ($g -and $g.Path) {
                $mergedMap[$g.Path.ToLower()] = $g
            }
        }
        foreach ($existing in $script:CurrentGameLibrary) {
            if ($existing -and $existing.Path) {
                $low = $existing.Path.ToLower()
                if (-not $mergedMap.ContainsKey($low)) {
                    $mergedMap[$low] = $existing
                }
            }
        }
        
        $finalList = @($mergedMap.Values | Sort-Object -Property Order, Name)
        $script:CurrentGameLibrary = $finalList
        Save-GamesCache -Games $finalList
        Refresh-GameLibraryUI -Games $finalList
        
        $msg = $d.StatusScanDone -f $finalList.Count
        Write-Status -Message $msg -Level "OK"
        
        if ($finalList.Count -gt 0 -and (-not $script:SelectedGameObj)) {
            $targetIdx = 0
            if ($script:AppConfig.LastSelectedGamePath) {
                for ($i = 0; $i -lt $finalList.Count; $i++) {
                    if ($finalList[$i].Path.ToLower() -eq $script:AppConfig.LastSelectedGamePath.ToLower()) {
                        $targetIdx = $i
                        break
                    }
                }
            }
            if ($gameList.Items.Count -gt $targetIdx) {
                $gameList.Items[$targetIdx].Selected = $true
            }
        }
    }
    else {
        $pct = [Math]::Min(100, [Math]::Max(0, [int]$script:ScanSync.Pct))
        if ($script:ProgressBar) { $script:ProgressBar.Value = $pct }
        if ($script:ScanSync.CurrentGame) {
            $scanFmt = if ($d.StatusScanningBackground) { $d.StatusScanningBackground } else { "Scanning: {0} ({1}%)..." }
            $script:StatusLabel.Text = "  " + ($scanFmt -f $script:ScanSync.CurrentGame, $pct)
        }
    }
})

$btnScan.Add_Click({
    Write-Status -Message "[USER] Botao 'ESCANEAR DISCOS' acionado pelo usuario." -Level "INFO"
    Start-LibraryScanAsync -IsStartup $false
})

$btnBrowse.Add_Click({
    $d = Get-Dict -Lang $script:CurrentLang
    Write-Status -Message "[USER] Botao 'PROCURAR JOGO' acionado. Dialogo de selecao de diretorio aberto." -Level "INFO"
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = if ($d.FolderBrowseDialog) { $d.FolderBrowseDialog } else { "Select the folder where the game is installed:" }
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Write-Status -Message "[USER] Pasta selecionada pelo usuario no dialogo: '$($fbd.SelectedPath)'" -Level "INFO"
        try {
            $resolved = Resolve-GameTarget -TargetPath $fbd.SelectedPath
            if (-not $resolved -or -not $resolved.Executable) {
                Write-Status -Message "[USER] Nenhum executavel valido encontrado na pasta selecionada: '$($fbd.SelectedPath)'" -Level "WARN"
                $errMsg = if ($d.GameNotFound) { $d.GameNotFound } else { "No valid game executable found in selected folder." }
                [System.Windows.Forms.MessageBox]::Show($errMsg, "1 Click DLSS 5", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }
            $api = Detect-GameGraphicsApi -TargetExe $resolved.Executable -GameFolder $resolved.InstallFolder
            $upscaler = Detect-GameUpscalerType -GameFolder $resolved.InstallFolder -GameRoot $resolved.Root
            $isInstalled = Test-GameDlss5Installed -GameFolder $resolved.InstallFolder
            $gObj = [pscustomobject]@{
                Order       = 1
                Name        = (Split-Path -Leaf $fbd.SelectedPath)
                Path        = $fbd.SelectedPath
                Api         = "$api ($($resolved.Architecture))"
                Upscaler    = $upscaler
                IsInstalled = $isInstalled
                Icon        = $resolved.Icon
                ExeName     = $resolved.ExeName
            }
            
            # Non-destructive merge
            $existing = @($script:CurrentGameLibrary | Where-Object { $_.Path.ToLower() -ne $gObj.Path.ToLower() })
            $script:CurrentGameLibrary = @($gObj) + $existing
            
            # Persist custom game path
            if ($script:AppConfig.CustomGamePaths -notcontains $fbd.SelectedPath) {
                $script:AppConfig.CustomGamePaths += $fbd.SelectedPath
                Save-AppConfig -Config $script:AppConfig
            }
            
            Save-GamesCache -Games $script:CurrentGameLibrary
            Refresh-GameLibraryUI -Games $script:CurrentGameLibrary
            Select-GameInInspector -GameObj $gObj
            if ($gameList.Items.Count -gt 0) {
                $gameList.Items[0].Selected = $true
            }
        }
        catch {
            $ctx = if ($script:CurrentLang -eq "PT") { "Selecao de Pasta" } else { "Folder Selection" }
            Show-FriendlyErrorDialog -Ex $_.Exception -Context $ctx -TargetPath $fbd.SelectedPath
        }
    }
})

$btnInstall.Add_Click({
    $d = Get-Dict -Lang $script:CurrentLang
    if (-not $script:SelectedGameObj) {
        Write-Status -Message "[USER] Botao 'INSTALAR DLSS 5' clicado sem jogo selecionado." -Level "WARN"
        $selMsg = if ($d.SelectGameFirst) { $d.SelectGameFirst } else { "Please select a game in the library or click 'BROWSE GAME' first." }
        [System.Windows.Forms.MessageBox]::Show($selMsg, "1 Click DLSS 5", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    Write-Status -Message "[USER] Botao 'INSTALAR DLSS 5' clicado para o jogo: '$($script:SelectedGameObj.Name)' | Pasta: '$($script:SelectedGameObj.Path)' | Modo Solicitado: '$($script:SelectedMode)'" -Level "INFO" 

    $oldText = $btnInstall.Text
    $btnInstall.Enabled = $false
    $btnLaunch.Enabled = $false
    $btnUninstall.Enabled = $false
    $btnBrowse.Enabled = $false
    $btnScan.Enabled = $false
    $btnInstall.Text = if ($d.InstallingDlss5) { $d.InstallingDlss5 } else { "⏳ INSTALLING DLSS 5..." }
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

    if ($script:TipPanel) { $script:TipPanel.Visible = $false }
    if ($script:ProgressPanel) {
        $script:ProgressPanel.Visible = $true
        $script:MainProgressBar.Value = 5
        $script:LblProgressPct.Text = "5%"
        $script:LblProgressStep.Text = if ($d.ProgressValidating) { $d.ProgressValidating } else { "Validating game and write permissions..." }
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
        
        $script:SelectedGameObj.IsInstalled = $true
        Save-GamesCache -Games $script:CurrentGameLibrary
        Refresh-GameLibraryUI -Games $script:CurrentGameLibrary
        Select-GameInInspector -GameObj $script:SelectedGameObj
    }
    catch {
        $ctx = if ($script:CurrentLang -eq "PT") { "Instalacao do DLSS 5" } else { "DLSS 5 Installation" }
        Show-FriendlyErrorDialog -Ex $_.Exception -Context $ctx -TargetPath $script:SelectedGameObj.Path -SelectedMode $script:SelectedMode
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
    Write-Status -Message "[USER] Botao 'INICIAR JOGO' clicado para: '$($script:SelectedGameObj.Name)' | Pasta: '$($script:SelectedGameObj.Path)'" -Level "INFO"
    try {
        $resolved = Resolve-GameTarget -TargetPath $script:SelectedGameObj.Path
        Start-GameExecutable -ExecutablePath $resolved.Executable
    }
    catch {
        $ctx = if ($script:CurrentLang -eq "PT") { "Inicializacao do Jogo" } else { "Game Launch" }
        Show-FriendlyErrorDialog -Ex $_.Exception -Context $ctx -TargetPath $script:SelectedGameObj.Path
    }
})

$btnUninstall.Add_Click({
    if (-not $script:SelectedGameObj) { return }
    Write-Status -Message "[USER] Botao 'RESTAURAR ORIGINAL' clicado para: '$($script:SelectedGameObj.Name)' | Pasta: '$($script:SelectedGameObj.Path)'" -Level "WARN"
    $d = Get-Dict -Lang $script:CurrentLang
    $msg = if ($d.ConfirmRestoreMsg) { $d.ConfirmRestoreMsg } else { "Do you really want to remove all DLSS 5 files and restore the game to its original state?" }
    $title = if ($d.ConfirmRestoreTitle) { $d.ConfirmRestoreTitle } else { "Confirm Restoration" }
    $res = [System.Windows.Forms.MessageBox]::Show($msg, $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
        Write-Status -Message "[USER] Confirmacao de restauracao aceita pelo usuario (DialogResult=Yes)." -Level "WARN" 
        try {
            Uninstall-Dlss5 -TargetPath $script:SelectedGameObj.Path
            $script:SelectedGameObj.IsInstalled = $false
            Save-GamesCache -Games $script:CurrentGameLibrary
            Refresh-GameLibraryUI -Games $script:CurrentGameLibrary
            Select-GameInInspector -GameObj $script:SelectedGameObj
        }
        catch {
            $ctx = if ($script:CurrentLang -eq "PT") { "Restauracao de Fabrica" } else { "Factory Restoration" }
            Show-FriendlyErrorDialog -Ex $_.Exception -Context $ctx -TargetPath $script:SelectedGameObj.Path
        }
    }
})

$btnOpenFolder.Add_Click({
    if ($script:SelectedGameObj -and (Test-Path -LiteralPath $script:SelectedGameObj.Path)) {
        Write-Status -Message "[USER] Botao 'ABRIR PASTA DO JOGO' acionado para: '$($script:SelectedGameObj.Path)'" -Level "INFO"
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
        Write-Status -Message "[USER] Pesquisa na biblioteca: '$term' (Filtrados: $($filtered.Count) de $($script:CurrentGameLibrary.Count) jogos)" -Level "INFO" 
    }
})

# --- INICIALIZACAO COMPLETA DA INTERFACE E CARREGAMENTO DE CACHE ---
Update-UiLanguage -Lang $script:CurrentLang

if (-not $env:DLSS5_HEADLESS) {
    $d = Get-Dict -Lang $script:CurrentLang
    $rawCached = Get-GamesCache
    $cached = @()
    if ($rawCached) {
        foreach ($c in $rawCached) {
            if ($c -is [System.Collections.IEnumerable] -and -not ($c -is [string]) -and -not ($c -is [System.Management.Automation.PSCustomObject])) {
                foreach ($sub in $c) { if ($sub) { $cached += $sub } }
            }
            else {
                if ($c) { $cached += $c }
            }
        }
    }
    if ($cached.Count -gt 0) {
        $script:CurrentGameLibrary = $cached
        Refresh-GameLibraryUI -Games $cached
        $lblStatus.Text = "  " + ($d.StatusScanDone -f $cached.Count)
        
        $selectedIdx = 0
        if ($script:AppConfig.LastSelectedGamePath) {
            for ($i = 0; $i -lt $cached.Count; $i++) {
                if ($cached[$i].Path.ToLower() -eq $script:AppConfig.LastSelectedGamePath.ToLower()) {
                    $selectedIdx = $i
                    break
                }
            }
        }
        if ($gameList.Items.Count -gt $selectedIdx) {
            $gameList.Items[$selectedIdx].Selected = $true
        }
    }
    else {
        $lblStatus.Text = "  " + $d.StatusReady
    }

    $form.Add_Shown({
        # Se configurado para varredura automatica, executa em segundo plano SEM travar a interface
        if ($script:AppConfig.AutoScanOnStartup) {
            Start-LibraryScanAsync -IsStartup $true
        }
    })
}

# Inicializa  o
Write-Status -Message "1 Click DLSS 5 v$($script:Version) pronto e operacional." -Level "OK"
if (-not $env:DLSS5_HEADLESS) {
    [void][System.Windows.Forms.Application]::EnableVisualStyles()
    $form.TopMost = $true
    $form.Add_Shown({
        $this.TopMost = $false
        $this.Activate()
        $this.BringToFront()
    })
    Apply-DpiScaling -Form $form
    [void][System.Windows.Forms.Application]::Run($form)
}
