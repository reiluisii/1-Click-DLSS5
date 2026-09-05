# ==============================================================================
# 1 Click DLSS 5 — Neural Deployment, Injection Pipeline & Uninstallation Engine
# ==============================================================================

if (-not (Get-Command "Write-Status" -ErrorAction SilentlyContinue)) {
    function Write-Status {
        param([string]$Message, [string]$Level = "INFO")
        $col = switch ($Level) {
            "OK"   { "Green" }
            "WARN" { "Yellow" }
            "ERR"  { "Red" }
            default{ "Gray" }
        }
        Write-Host "[$Level] $Message" -ForegroundColor $col
    }
}

function Get-DLSS5PayloadDirectory {
    $base = Split-Path -Parent $PSScriptRoot
    $cand = Join-Path $base "payload"
    if (Test-Path -LiteralPath $cand) { return $cand }
    $alt = Join-Path $PSScriptRoot "payload"
    if (Test-Path -LiteralPath $alt) { return $alt }
    return $cand
}

function Set-Dlss5ReShadePresetIni {
    param(
        [Parameter(Mandatory = $true)][string]$PresetPath,
        [Parameter(Mandatory = $false)][int]$Provider = 3
    )
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $providerTechnique = if ($Provider -eq 3) { "Lumenite_Kernel@lumenite_Kernel.fx" } else { "vort_MotionEffects@vort_Motion.fx" }
    $requiredTechniques = "$providerTechnique,DLSS5_Feed@DLSS5_Feed.fx"

    if (Test-Path -LiteralPath $PresetPath -PathType Leaf) {
        try {
            $text = [System.IO.File]::ReadAllText($PresetPath, [System.Text.Encoding]::UTF8)
            if ($text -match '(?m)^Techniques=') {
                $text = [regex]::Replace($text, '(?m)^Techniques=.*$', "Techniques=$requiredTechniques")
            } else {
                $text = "Techniques=$requiredTechniques`r`n" + $text
            }
            if ($text -match '(?m)^TechniqueSorting=') {
                $text = [regex]::Replace($text, '(?m)^TechniqueSorting=.*$', "TechniqueSorting=$requiredTechniques")
            } else {
                $text = "TechniqueSorting=$requiredTechniques`r`n" + $text
            }
            if ($text -match '(?m)^PreprocessorDefinitions=') {
                $text = [regex]::Replace($text, '(?m)^PreprocessorDefinitions=.*$', "PreprocessorDefinitions=DLSS5_MV_PROVIDER=$Provider")
            } else {
                $text = "PreprocessorDefinitions=DLSS5_MV_PROVIDER=$Provider`r`n" + $text
            }
            if ($text -notmatch '\[DLSS5_Feed\.fx\]') {
                $text += @"

[DLSS5_Feed.fx]
PreprocessorDefinitions=DLSS5_MV_PROVIDER=$Provider
"@
            }
            [System.IO.File]::WriteAllText($PresetPath, $text, $utf8NoBom)
            return
        } catch {}
    }

    $presetContent = @"
Techniques=$requiredTechniques
TechniqueSorting=$requiredTechniques
PreprocessorDefinitions=DLSS5_MV_PROVIDER=$Provider

[DLSS5_Feed.fx]
PreprocessorDefinitions=DLSS5_MV_PROVIDER=$Provider
"@
    [System.IO.File]::WriteAllText($PresetPath, $presetContent, $utf8NoBom)
}

function Set-Dlss5ReShadeIni {
    param(
        [Parameter(Mandatory = $true)][string]$IniPath,
        [Parameter(Mandatory = $false)][bool]$IsFeederMode = $true,
        [Parameter(Mandatory = $false)][int]$EnableHooks = 1
    )
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    if (Test-Path -LiteralPath $IniPath -PathType Leaf) {
        # Modificacao cirurgica segura de ReShade.ini pre-existente
        try {
            $text = [System.IO.File]::ReadAllText($IniPath, [System.Text.Encoding]::UTF8)
            
            # 1. Garante que DisabledAddons nao desative RenoDX DLSS 5 nem DLSS 5 Feed
            if ($text -match '^DisabledAddons=(.*)$') {
                $disabledList = $matches[1].Split(',') | Where-Object { 
                    $t = $_.Trim().ToLower()
                    $t -and ($t -notmatch 'renodx-dlss5') -and ($t -notmatch 'dlss5-feed')
                }
                $text = [regex]::Replace($text, '(?m)^DisabledAddons=.*$', "DisabledAddons=$($disabledList -join ',')")
            }

            if ($IsFeederMode) {
                # 2. Assegura busca recursiva de Shaders e Texturas
                if ($text -match '(?m)^EffectSearchPaths=') {
                    $text = [regex]::Replace($text, '(?m)^EffectSearchPaths=.*$', 'EffectSearchPaths=.\reshade-shaders\Shaders\**')
                } elseif ($text -match '\[GENERAL\]') {
                    $text = [regex]::Replace($text, '(?m)\[GENERAL\]', "[GENERAL]`r`nEffectSearchPaths=.\\reshade-shaders\\Shaders\\**")
                }
                if ($text -match '(?m)^TextureSearchPaths=') {
                    $text = [regex]::Replace($text, '(?m)^TextureSearchPaths=.*$', 'TextureSearchPaths=.\reshade-shaders\Textures\**')
                } elseif ($text -match '\[GENERAL\]') {
                    $text = [regex]::Replace($text, '(?m)\[GENERAL\]', "[GENERAL]`r`nTextureSearchPaths=.\\reshade-shaders\\Textures\\**")
                }
                # 3. Define PreprocessorDefinitions do Feeder
                if ($text -match '(?m)^PreprocessorDefinitions=') {
                    $text = [regex]::Replace($text, '(?m)^PreprocessorDefinitions=.*$', 'PreprocessorDefinitions=DLSS5_MV_PROVIDER=3')
                } elseif ($text -match '\[GENERAL\]') {
                    $text = [regex]::Replace($text, '(?m)\[GENERAL\]', "[GENERAL]`r`nPreprocessorDefinitions=DLSS5_MV_PROVIDER=3")
                }
                # 4. Define PresetPath
                if ($text -match '(?m)^PresetPath=') {
                    $text = [regex]::Replace($text, '(?m)^PresetPath=.*$', 'PresetPath=.\ReShadePreset.ini')
                } elseif ($text -match '\[GENERAL\]') {
                    $text = [regex]::Replace($text, '(?m)\[GENERAL\]', "[GENERAL]`r`nPresetPath=.\\ReShadePreset.ini")
                }
                # 5. AddonPath
                if ($text -match '(?m)^AddonPath=') {
                    $text = [regex]::Replace($text, '(?m)^AddonPath=.*$', 'AddonPath=.\')
                } elseif ($text -match '\[ADDON\]') {
                    $text = [regex]::Replace($text, '(?m)\[ADDON\]', "[ADDON]`r`nAddonPath=.\\")
                }
            }

            # 6. Atualiza ou adiciona secao [RenoDX.DLSS5]
            if ($text -match '\[RenoDX\.DLSS5\]') {
                $text = [regex]::Replace($text, '(?m)^EnableHooks=\d+', "EnableHooks=$EnableHooks")
                if ($IsFeederMode) {
                    if ($text -match '(?m)^NREnableUpscaling=') {
                        $text = [regex]::Replace($text, '(?m)^NREnableUpscaling=.*$', "NREnableUpscaling=0")
                    } else {
                        $text = [regex]::Replace($text, '(?m)\[RenoDX\.DLSS5\]', "[RenoDX.DLSS5]`r`nNREnableUpscaling=0")
                    }
                    if ($text -match '(?m)^NeuralUplift=') {
                        $text = [regex]::Replace($text, '(?m)^NeuralUplift=.*$', "NeuralUplift=1")
                    }
                }
            } else {
                $extraFeeder = if ($IsFeederMode) { "`r`nNREnableUpscaling=0" } else { "" }
                $text += @"

[RenoDX.DLSS5]
EnableHooks=$EnableHooks
NeuralUplift=1$extraFeeder
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
"@
            }
            [System.IO.File]::WriteAllText($IniPath, $text, $utf8NoBom)
            return
        } catch {}
    }

    # Template novo caso nao exista
    if ($IsFeederMode) {
        $iniContent = @"
[ADDON]
AddonPath=.\
DisabledAddons=Generic Depth,Effect Runtime Sync
OverlayCollapsed=DLSS 5 Feed 0.12.0@dlss5-feed.addon64,DLSS 5 Neural Rendering@renodx-dlss5.addon64,Generic Depth,Effect Runtime Sync

[GENERAL]
EffectSearchPaths=.\reshade-shaders\Shaders\**
IntermediateCachePath=$env:TEMP\ReShade
NoDebugInfo=1
NoEffectCache=0
NoReloadOnInit=0
PerformanceMode=0
PreprocessorDefinitions=DLSS5_MV_PROVIDER=3
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
FPSPosition=1
ShowForceLoadEffectsButton=1
ShowFPS=2
TutorialProgress=4

[RenoDX.DLSS5]
EnableHooks=$EnableHooks
NeuralUplift=1
NREnableUpscaling=0
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
"@
    } else {
        $iniContent = @"
[ADDON]
DisabledAddons=Generic Depth,Effect Runtime Sync

[GENERAL]
EffectSearchPaths=
TextureSearchPaths=
NoReloadOnInit=1
PerformanceMode=0
SkipLoadingDisabledEffects=1

[INPUT]
ForceShortcutModifiers=1
InputProcessing=0
KeyOverlay=36,0,0,0

[OVERLAY]
TutorialProgress=4

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
"@
    }
    [System.IO.File]::WriteAllText($IniPath, $iniContent, $utf8NoBom)
}

function Set-GameHighPerformanceGpuPreference {
    param([Parameter(Mandatory = $true)][string]$ExecutablePath)
    try {
        $regKey = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
        if (-not (Test-Path $regKey)) {
            [void](New-Item -Path $regKey -Force)
        }
        Set-ItemProperty -Path $regKey -Name $ExecutablePath -Value "GpuPreference=2;" -Type String -Force -ErrorAction SilentlyContinue
    } catch {}
}

function Install-Dlss5 {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $false)][string]$SelectedMode = "AUTO",
        [Parameter(Mandatory = $false)][scriptblock]$ProgressCallback = $null
    )
    if ($ProgressCallback) { &$ProgressCallback 10 "Iniciando verificacao de integridade e requisitos..." }
    $target = Resolve-GameTarget -TargetPath $TargetPath
    $targetFolder = $target.InstallFolder

    # Salvaguarda 1: Processos fechados
    Assert-GameClosedSafetyCheck -GameFolder $targetFolder -TargetExe $target.Executable

    # Salvaguarda 2: Permissao de escrita
    if (-not (Test-DirectoryWritable -Folder $targetFolder)) {
        throw "ERR_NO_WRITE_ACCESS: Sem permissao de gravacao na pasta do jogo. Execute como Administrador."
    }

    # Salvaguarda 3: Inspecao de Anti-Cheat
    if (Test-AntiCheatRisk -GameFolder $targetFolder) {
        Write-Status -Message "ALERTA DE ANTI-CHEAT: Detectado modulo de protecao anti-cheat oficial na pasta do jogo. A injecao pode ser bloqueada." -Level "WARN"
    }

    $payloadDir = Get-DLSS5PayloadDirectory
    $detectedUpscaler = Detect-GameUpscalerType -GameFolder $targetFolder -GameRoot $target.Root
    $api = Detect-GameGraphicsApi -TargetExe $target.Executable -GameFolder $targetFolder
    $isX64 = ($target.Architecture -eq "X64")
    $bitness = if ($isX64) { 64 } else { 32 }

    $effectiveMode = $SelectedMode
    if ($effectiveMode -eq "AUTO") {
        if ($detectedUpscaler -eq "NATIVE_DLSS") { $effectiveMode = "DIRECT" }
        elseif ($detectedUpscaler -eq "FSR2_BRIDGE" -or $detectedUpscaler -eq "XESS_BRIDGE") { $effectiveMode = "OPTISCALER" }
        else { $effectiveMode = "FEEDER" }
    }

    if ($ProgressCallback) { &$ProgressCallback 25 "Jogo: $($target.ExeName) | API: $api | Modo: $effectiveMode" }
    Write-Status -Message "================================================================================" -Level "INFO"
    Write-Status -Message "[INSTALACAO] Alvo: $($target.ExeName) | Modo: $effectiveMode | API: $api ($bitness-bit)" -Level "INFO"

    $exeRel = Get-Dlss5RelativePath -BasePath $targetFolder -TargetPath $target.Executable
    $manifest = Init-Dlss5Manifest -GameFolder $targetFolder -ExeRel $exeRel -Route $effectiveMode -Api $api -Bitness $bitness

    # Helper interno para copiar e rastrear
    $safeCopyInternal = {
        param($src, $dstPath, $kind)
        Track-FileBeforeWrite -GameFolder $targetFolder -Manifest $manifest -TargetPath $dstPath -Kind $kind | Out-Null
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $dstPath) -Force)
        Copy-Item -LiteralPath $src -Destination $dstPath -Force
        Write-Status -Message "[INJECAO] $(Split-Path -Leaf $dstPath) instalado ($kind)" -Level "OK"
    }

    if ($ProgressCallback) { &$ProgressCallback 45 "Configurando proxy grafico e bibliotecas neurais..." }

    # Rota DIRECT (DLSS Nativo)
    if ($effectiveMode -eq "DIRECT") {
        $hookVal = 2
        $staleSlNr = Join-Path $targetFolder "sl.dlss_nr.dll"
        if (Test-Path -LiteralPath $staleSlNr -PathType Leaf) {
            Remove-Item -LiteralPath $staleSlNr -Force -ErrorAction SilentlyContinue
        }

        # 1. nvngx_dlss.dll: Compara versao com payload
        $payloadDlss = Join-Path $payloadDir "nvngx_dlss.dll"
        if (Test-Path -LiteralPath $payloadDlss) {
            $payloadVer = [DLSS5PeEngine]::GetFileVersion($payloadDlss)
            $existingDlssFiles = @(Get-ChildItem -LiteralPath $targetFolder -Filter "nvngx_dlss.dll" -File -Recurse -Depth 4 -ErrorAction SilentlyContinue)
            if ($existingDlssFiles.Count -gt 0) {
                foreach ($exDlss in $existingDlssFiles) {
                    $curVer = [DLSS5PeEngine]::GetFileVersion($exDlss.FullName)
                    if ([DLSS5PeEngine]::CompareVersions($payloadVer, $curVer) -gt 0) {
                        &$safeCopyInternal $payloadDlss $exDlss.FullName "runtime"
                        Write-Status -Message "[UPGRADE] Atualizado nvngx_dlss.dll: $curVer -> $payloadVer" -Level "OK"
                    } else {
                        Write-Status -Message "[CHECK] nvngx_dlss.dll ja esta na versao mais recente ($curVer)." -Level "INFO"
                    }
                }
            } else {
                $targetDlss = Join-Path $targetFolder "nvngx_dlss.dll"
                &$safeCopyInternal $payloadDlss $targetDlss "runtime"
            }
        }

        # 2. nvngx_dlssnr.dll (Modelo Neural de Reconstrucao)
        $payloadNr = Join-Path $payloadDir "nvngx_dlssnr.dll"
        if (Test-Path -LiteralPath $payloadNr) {
            $destNr = Join-Path $targetFolder "nvngx_dlssnr.dll"
            &$safeCopyInternal $payloadNr $destNr "runtime"
        }

        # 3. RenoDX Addon DLSS 5
        $payloadAddon = Join-Path $payloadDir "renodx-dlss5.addon64"
        if (Test-Path -LiteralPath $payloadAddon) {
            $destAddon = Join-Path $targetFolder "renodx-dlss5.addon64"
            &$safeCopyInternal $payloadAddon $destAddon "addon"
        }

        # 4. Proxy ReShade com suporte a Addons
        $proxyName = if ($api -eq "D3D9") { "d3d9.dll" } elseif ($api -eq "OPENGL") { "opengl32.dll" } else { "dxgi.dll" }
        $proxyTarget = Join-Path $targetFolder $proxyName
        $hasWorkingAddonReShade = [DLSS5PeEngine]::IsAddonReShade($proxyTarget)
        if ($hasWorkingAddonReShade) {
            Write-Status -Message "[RESHADE] ReShade com suporte a add-ons ja presente ($proxyName). Preservando configuracao." -Level "INFO"
        } else {
            $proxyDllName = if ($isX64) { "dxgi.dll" } else { "dxgi32.dll" }
            $proxySrc = Join-Path $payloadDir $proxyDllName
            if (Test-Path -LiteralPath $proxySrc) {
                &$safeCopyInternal $proxySrc $proxyTarget "reshade"
                $manifest.reshade.installedByUs = $true
                $manifest.reshade.file = $proxyName
            }
        }

        # 5. Higienizacao e configuracao de ReShade.ini
        $staleShaders = Join-Path $targetFolder "reshade-shaders"
        if (Test-Path -LiteralPath $staleShaders) {
            Remove-Item -LiteralPath $staleShaders -Recurse -Force -ErrorAction SilentlyContinue
        }
        $stalePreset = Join-Path $targetFolder "ReShadePreset.ini"
        if (Test-Path -LiteralPath $stalePreset) {
            Remove-Item -LiteralPath $stalePreset -Force -ErrorAction SilentlyContinue
        }

        $targetIni = Join-Path $targetFolder "ReShade.ini"
        Track-FileBeforeWrite -GameFolder $targetFolder -Manifest $manifest -TargetPath $targetIni -Kind "config" | Out-Null
        Set-Dlss5ReShadeIni -IniPath $targetIni -IsFeederMode $false -EnableHooks $hookVal
        Set-GameHighPerformanceGpuPreference -ExecutablePath $target.Executable
    }
    elseif ($effectiveMode -eq "OPTISCALER") {
        # Rota OPTISCALER
        $optiDir = Join-Path $payloadDir "optiscaler"
        $optiDll = Join-Path $optiDir "OptiScaler.dll"
        $hookName = if ($api -eq "VULKAN") { "winmm.dll" } else { "dxgi.dll" }
        $destHook = Join-Path $targetFolder $hookName

        if (Test-Path -LiteralPath $optiDll) { &$safeCopyInternal $optiDll $destHook "optiscaler" }
        $optiIni = Join-Path $optiDir "OptiScaler.ini"
        if (Test-Path -LiteralPath $optiIni) {
            $destIni = Join-Path $targetFolder "OptiScaler.ini"
            &$safeCopyInternal $optiIni $destIni "config"
        }
        $optiXess = Join-Path $optiDir "libxess.dll"
        if (Test-Path -LiteralPath $optiXess) {
            $destXess = Join-Path $targetFolder "libxess.dll"
            &$safeCopyInternal $optiXess $destXess "runtime"
        }
        $payloadNr = Join-Path $payloadDir "nvngx_dlssnr.dll"
        if (Test-Path -LiteralPath $payloadNr) {
            &$safeCopyInternal $payloadNr (Join-Path $targetFolder "nvngx_dlssnr.dll") "runtime"
            &$safeCopyInternal $payloadNr (Join-Path $targetFolder "nvngx.dll_dlssnr.dll") "runtime"
        }
    }
    else {
        # Rota FEEDER (Universal para DX11/12/Vulkan/OpenGL)
        $feederDir = Join-Path $payloadDir "feeder"
        if ($isX64) {
            $feedAddon = Join-Path $feederDir "dlss5-feed.addon64"
            if (Test-Path -LiteralPath $feedAddon) { &$safeCopyInternal $feedAddon (Join-Path $targetFolder "dlss5-feed.addon64") "feeder" }
            $payloadAddon = Join-Path $payloadDir "renodx-dlss5.addon64"
            if (Test-Path -LiteralPath $payloadAddon) { &$safeCopyInternal $payloadAddon (Join-Path $targetFolder "renodx-dlss5.addon64") "addon" }
            $payloadNr = Join-Path $payloadDir "nvngx_dlssnr.dll"
            if (Test-Path -LiteralPath $payloadNr) { &$safeCopyInternal $payloadNr (Join-Path $targetFolder "nvngx_dlssnr.dll") "runtime" }
            $payloadDlss = Join-Path $payloadDir "nvngx_dlss.dll"
            if (Test-Path -LiteralPath $payloadDlss) { &$safeCopyInternal $payloadDlss (Join-Path $targetFolder "nvngx_dlss.dll") "runtime" }
        } else {
            $feedAddon32 = Join-Path $feederDir "dlss5-feed.addon32"
            if (Test-Path -LiteralPath $feedAddon32) { &$safeCopyInternal $feedAddon32 (Join-Path $targetFolder "dlss5-feed.addon32") "feeder" }
            $hostDir = Join-Path $targetFolder "host64"
            [void](New-Item -ItemType Directory -Path $hostDir -Force)
            $hostExe = Join-Path $feederDir "host64\dlss5-feed-host64.exe"
            if (Test-Path -LiteralPath $hostExe) { &$safeCopyInternal $hostExe (Join-Path $hostDir "dlss5-feed-host64.exe") "feeder" }
            &$safeCopyInternal (Join-Path $payloadDir "renodx-dlss5.addon64") (Join-Path $hostDir "renodx-dlss5.addon64") "addon"
            &$safeCopyInternal (Join-Path $payloadDir "nvngx_dlssnr.dll") (Join-Path $hostDir "nvngx_dlssnr.dll") "runtime"
            &$safeCopyInternal (Join-Path $payloadDir "nvngx_dlss.dll") (Join-Path $hostDir "nvngx_dlss.dll") "runtime"
            &$safeCopyInternal (Join-Path $payloadDir "dxgi.dll") (Join-Path $hostDir "dxgi.dll") "reshade"
            $hostIni = Join-Path $hostDir "ReShade.ini"
            Track-FileBeforeWrite -GameFolder $targetFolder -Manifest $manifest -TargetPath $hostIni -Kind "config" | Out-Null
            Set-Dlss5ReShadeIni -IniPath $hostIni -IsFeederMode $false -EnableHooks 2
        }

        # Shaders e Texturas (Copia recursiva preservando subpastas como 'include\')
        $shaderSrc = Join-Path $feederDir "shaders"
        $shaderDst = Join-Path $targetFolder "reshade-shaders\Shaders"
        if (Test-Path -LiteralPath $shaderSrc) {
            [void](New-Item -ItemType Directory -Path $shaderDst -Force)
            Get-ChildItem -LiteralPath $shaderSrc -File -Recurse | ForEach-Object {
                $relSub = Get-Dlss5RelativePath -BasePath $shaderSrc -TargetPath $_.FullName
                $targetFile = Join-Path $shaderDst $relSub
                &$safeCopyInternal $_.FullName $targetFile "feeder"
            }
        }
        $texSrc = Join-Path $feederDir "textures"
        $texDst = Join-Path $targetFolder "reshade-shaders\Textures"
        if (Test-Path -LiteralPath $texSrc) {
            [void](New-Item -ItemType Directory -Path $texDst -Force)
            Get-ChildItem -LiteralPath $texSrc -File -Recurse | ForEach-Object {
                $relSub = Get-Dlss5RelativePath -BasePath $texSrc -TargetPath $_.FullName
                $targetFile = Join-Path $texDst $relSub
                &$safeCopyInternal $_.FullName $targetFile "feeder"
            }
        }

        $cfgSrc = Join-Path $feederDir "dlss5-feed.cfg"
        if (Test-Path -LiteralPath $cfgSrc) { &$safeCopyInternal $cfgSrc (Join-Path $targetFolder "dlss5-feed.cfg") "config" }

        # ReShade Proxy para Feeder
        $proxyName = if ($api -eq "D3D9") { "d3d9.dll" } elseif ($api -eq "OPENGL") { "opengl32.dll" } else { "dxgi.dll" }
        $proxyTarget = Join-Path $targetFolder $proxyName
        $proxyDllName = if ($isX64) { "dxgi.dll" } else { "dxgi32.dll" }
        $proxySrc = Join-Path $payloadDir $proxyDllName
        if (Test-Path -LiteralPath $proxySrc) {
            &$safeCopyInternal $proxySrc $proxyTarget "reshade"
            $manifest.reshade.installedByUs = $true
            $manifest.reshade.file = $proxyName
        }

        $targetIni = Join-Path $targetFolder "ReShade.ini"
        Track-FileBeforeWrite -GameFolder $targetFolder -Manifest $manifest -TargetPath $targetIni -Kind "config" | Out-Null
        Set-Dlss5ReShadeIni -IniPath $targetIni -IsFeederMode $true -EnableHooks 2

        $presetIni = Join-Path $targetFolder "ReShadePreset.ini"
        Track-FileBeforeWrite -GameFolder $targetFolder -Manifest $manifest -TargetPath $presetIni -Kind "config" | Out-Null
        Set-Dlss5ReShadePresetIni -PresetPath $presetIni -Provider 3
    }

    # Salva o manifesto ativo final
    Save-Dlss5Manifest -GameFolder $targetFolder -Manifest $manifest

    if ($ProgressCallback) { &$ProgressCallback 100 "Instalacao do DLSS 5 concluida com sucesso!" }
    Write-Status -Message "[OK] 1-Click DLSS 5 instalado com sucesso para '$($target.ExeName)'." -Level "OK"
    return $true
}

function Uninstall-Dlss5 {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $false)][scriptblock]$LogCallback = $null
    )
    $target = Resolve-GameTarget -TargetPath $TargetPath
    $targetFolder = $target.InstallFolder

    # Salvaguarda: Processo fechado
    Assert-GameClosedSafetyCheck -GameFolder $targetFolder -TargetExe $target.Executable

    Write-Status -Message "================================================================================" -Level "INFO"
    Write-Status -Message "[RESTAURACAO] Iniciando restauracao de fabrica em: '$targetFolder'" -Level "INFO"

    # Restaura atraves do motor de journal transacional
    try {
        Restore-Dlss5Originals -GameFolder $targetFolder -LogCallback {
            param($msg, $lvl)
            Write-Status -Message "[RESTAURACAO] $msg" -Level $lvl
        }
    } catch {
        Write-Status -Message "[AVISO] Fallback de restauracao manual: $($_.Exception.Message)" -Level "WARN"
    }

    # Limpeza adicional de sobras
    $purgeList = @(
        "renodx-dlss5.addon64", "dlss5-feed.addon64", "dlss5-feed.addon32", "dlss5-feed.cfg",
        "nvngx_dlssnr.dll", "sl.dlss_nr.dll", "OptiScaler.ini", "OptiScaler.log",
        "dlss5-feed.log", "dlss5-feed.ini", "dlss5-feed-host.log"
    )
    foreach ($item in $purgeList) {
        $p = Join-Path $targetFolder $item
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($sub in @("reshade-shaders", "host64")) {
        $sp = Join-Path $targetFolder $sub
        if (Test-Path -LiteralPath $sp -PathType Container) {
            Remove-Item -LiteralPath $sp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Status -Message "[OK] Restauracao de fabrica concluida com sucesso para '$($target.ExeName)'." -Level "OK"
    return $true
}

function Get-SteamAppId {
    param([Parameter(Mandatory = $true)][string]$ExecutablePath)
    try {
        $gameDir = Split-Path -Parent $ExecutablePath
        $cur = Get-Item -LiteralPath $gameDir -ErrorAction SilentlyContinue
        while ($cur -and $cur.FullName -ne $cur.Root.FullName) {
            if ($cur.Name -ieq "steamapps") {
                $manifests = Get-ChildItem -LiteralPath $cur.FullName -Filter "appmanifest_*.acf" -File -ErrorAction SilentlyContinue
                foreach ($mf in $manifests) {
                    $txt = Get-Content -LiteralPath $mf.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                    if ($txt -match '"appid"\s+"(\d+)"' -and $txt -match [regex]::Escape((Split-Path -Leaf $gameDir))) {
                        return $matches[1]
                    }
                }
                break
            }
            $cur = $cur.Parent
        }
    } catch {}
    return $null
}

function Start-GameExecutable {
    param([Parameter(Mandatory = $true)][string]$ExecutablePath)
    if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
        throw "Executavel nao encontrado: $ExecutablePath"
    }

    $appId = Get-SteamAppId -ExecutablePath $ExecutablePath
    if ($appId) {
        Write-Status -Message "[EXECUCAO] Detectado jogo da Steam (AppID: $appId). Iniciando via protocolo Steam..." -Level "INFO"
        Start-Process "steam://rungameid/$appId"
        return
    }

    $gameDir = Split-Path -Parent $ExecutablePath
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ExecutablePath
    $psi.WorkingDirectory = $gameDir
    $psi.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    Write-Status -Message "[EXECUCAO] Executavel iniciado: $(Split-Path -Leaf $ExecutablePath)" -Level "OK"
}
