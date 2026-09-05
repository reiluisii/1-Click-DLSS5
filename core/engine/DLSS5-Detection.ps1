# ==============================================================================
# 1 Click DLSS 5 — Store Scanners, Platform Resolvers & API Detection Engine
# ==============================================================================

function Get-XboxGameConfigExe {
    param([Parameter(Mandatory = $true)][string]$GameFolder)
    $candidates = @(
        (Join-Path $GameFolder "MicrosoftGame.config"),
        (Join-Path $GameFolder "Content\MicrosoftGame.config")
    )
    foreach ($cfg in $candidates) {
        if (Test-Path -LiteralPath $cfg -PathType Leaf) {
            try {
                $rawXml = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($rawXml -match '<Executable\b([^>]*)/?>') {
                    $attrBlock = $matches[1]
                    $nameMatch = [regex]::Match($attrBlock, 'Name\s*=\s*"([^"]+)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    $archMatch = [regex]::Match($attrBlock, 'Architecture\s*=\s*"([^"]+)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    if ($nameMatch.Success) {
                        $exeRel = $nameMatch.Groups[1].Value.Replace('/', '\')
                        if ($exeRel -ieq "gamelaunchhelper.exe") { continue }
                        $cfgDir = Split-Path -Parent $cfg
                        $resolvedExe = Join-Path $cfgDir $exeRel
                        $arch = if ($archMatch.Success -and $archMatch.Groups[1].Value -ieq "x64") { "X64" } else { "X86" }
                        return [pscustomobject]@{
                            ConfigPath   = $cfg
                            Executable   = $resolvedExe
                            Architecture = $arch
                        }
                    }
                }
            } catch {}
        }
    }
    return $null
}

function Get-EmulatorProfile {
    param([Parameter(Mandatory = $true)][string]$ExeName)
    $profiles = @(
        [pscustomobject]@{ Key = 'duckstation'; Name = 'DuckStation'; System = 'PlayStation 1'; Exes = @('duckstation-qt-x64.exe', 'duckstation.exe'); Apis = @('DXGI', 'VULKAN', 'OPENGL') }
        [pscustomobject]@{ Key = 'pcsx2'; Name = 'PCSX2'; System = 'PlayStation 2'; Exes = @('pcsx2-qt.exe', 'pcsx2x64.exe', 'pcsx2.exe'); Apis = @('DXGI', 'VULKAN') }
        [pscustomobject]@{ Key = 'dolphin'; Name = 'Dolphin'; System = 'GameCube / Wii'; Exes = @('dolphin.exe', 'dolphinqt.exe'); Apis = @('DXGI', 'VULKAN') }
        [pscustomobject]@{ Key = 'ppsspp'; Name = 'PPSSPP'; System = 'PSP'; Exes = @('ppssppwindows64.exe', 'ppssppwindows.exe'); Apis = @('DXGI', 'VULKAN') }
        [pscustomobject]@{ Key = 'xenia'; Name = 'Xenia'; System = 'Xbox 360'; Exes = @('xenia.exe', 'xenia_canary.exe'); Apis = @('DXGI', 'VULKAN') }
        [pscustomobject]@{ Key = 'cemu'; Name = 'Cemu'; System = 'Wii U'; Exes = @('cemu.exe'); Apis = @('VULKAN', 'OPENGL') }
        [pscustomobject]@{ Key = 'rpcs3'; Name = 'RPCS3'; System = 'PlayStation 3'; Exes = @('rpcs3.exe'); Apis = @('VULKAN') }
        [pscustomobject]@{ Key = 'ryujinx'; Name = 'Ryujinx'; System = 'Nintendo Switch'; Exes = @('ryujinx.exe', 'ryujinx.ava.exe'); Apis = @('VULKAN') }
        [pscustomobject]@{ Key = 'yuzu'; Name = 'Yuzu / Suyu / Eden'; System = 'Nintendo Switch'; Exes = @('yuzu.exe', 'suyu.exe', 'eden.exe', 'citron.exe', 'sudachi.exe'); Apis = @('VULKAN') }
        [pscustomobject]@{ Key = 'shadps4'; Name = 'shadPS4'; System = 'PlayStation 4'; Exes = @('shadps4.exe'); Apis = @('VULKAN') }
        [pscustomobject]@{ Key = 'citra'; Name = 'Citra / Lime3DS / Azahar'; System = 'Nintendo 3DS'; Exes = @('citra.exe', 'citra-qt.exe', 'lime3ds.exe', 'azahar.exe'); Apis = @('VULKAN', 'OPENGL') }
        [pscustomobject]@{ Key = 'vita3k'; Name = 'Vita3K'; System = 'PlayStation Vita'; Exes = @('vita3k.exe'); Apis = @('VULKAN') }
        [pscustomobject]@{ Key = 'retroarch'; Name = 'RetroArch'; System = 'Multi-system'; Exes = @('retroarch.exe'); Apis = @('DXGI', 'VULKAN') }
    )
    $low = $ExeName.ToLowerInvariant()
    foreach ($p in $profiles) {
        foreach ($e in $p.Exes) {
            if ($e.ToLowerInvariant() -eq $low) { return $p }
        }
    }
    return $null
}

function Detect-GameGraphicsApi {
    param(
        [Parameter(Mandatory = $true)][string]$TargetExe,
        [Parameter(Mandatory = $false)][string]$GameFolder = ""
    )
    if (-not (Test-Path -LiteralPath $TargetExe -PathType Leaf)) { return "DXGI" }

    $baseName = (Split-Path -Leaf $TargetExe).ToLowerInvariant()
    
    # 1. Perfil dedicado de renderizadores de jogos conhecidos
    if ($baseName -eq "rdr2.exe") {
        return "D3D12" # RDR2 usa DX12 / Vulkan nativamente, ignorando falso positivo de D3D9 em compatibilidade
    }

    # 2. Perfil de Emuladores Conhecidos
    $emu = Get-EmulatorProfile -ExeName $baseName
    if ($emu) {
        return $emu.Apis[0]
    }

    # 3. Inspecao Direta de Tabela de Importacao (PE Import Directory + Delay-Load Imports)
    $imports = [DLSS5PeEngine]::GetImports($TargetExe)
    if ($imports) {
        if ($imports -contains "d3d12.dll") { return "D3D12" }
        if ($imports -contains "d3d11.dll") { return "D3D11" }
        if ($imports -contains "dxgi.dll")   { return "DXGI" }
        if ($imports -contains "vulkan-1.dll") { return "VULKAN" }
        if ($imports -contains "d3d9.dll")   { return "D3D9" }
        if ($imports -contains "d3d8.dll")   { return "D3D8" }
        if ($imports -contains "opengl32.dll") { return "OPENGL" }
    }

    # 4. Marcadores Binarios em Arquivos Protegidos (D3D12 Agility SDK, D3D11CreateDevice, etc.)
    $apiMarkers = @(
        'D3D12CreateDevice', 'D3D12SDKPath', 'D3D12SDKVersion',
        'D3D11CreateDevice', 'D3D10CreateDevice',
        'Direct3DCreate9', 'Direct3DCreate8', 'CreateDXGIFactory',
        'vkCreateInstance', 'wglCreateContext'
    )
    $foundMarkers = [DLSS5PeEngine]::FindMarkers($TargetExe, $apiMarkers)
    if ($foundMarkers) {
        if ($foundMarkers -contains 'D3D12CreateDevice' -or $foundMarkers -contains 'D3D12SDKPath' -or $foundMarkers -contains 'D3D12SDKVersion') {
            return "D3D12"
        }
        if ($foundMarkers -contains 'D3D11CreateDevice') { return "D3D11" }
        if ($foundMarkers -contains 'CreateDXGIFactory') { return "DXGI" }
        if ($foundMarkers -contains 'vkCreateInstance')  { return "VULKAN" }
        if ($foundMarkers -contains 'Direct3DCreate9')   { return "D3D9" }
        if ($foundMarkers -contains 'Direct3DCreate8')   { return "D3D8" }
        if ($foundMarkers -contains 'wglCreateContext')  { return "OPENGL" }
    }

    # 5. Dispatchers de Engine que carregam modulos graficos em subpastas
    $engineModules = @{
        'hl.exe'         = @('hw.dll')
        'hl2.exe'        = @('bin\shaderapidx9.dll', 'bin\engine.dll', 'bin\x64\shaderapidx9.dll')
        'left4dead2.exe' = @('bin\shaderapidx9.dll', 'bin\engine.dll')
        'farcry5.exe'    = @('FC_m64.dll')
        'watch_dogs.exe' = @('Disrupt_b64.dll')
    }
    if ($engineModules.ContainsKey($baseName)) {
        $exeDir = Split-Path -Parent $TargetExe
        foreach ($relMod in $engineModules[$baseName]) {
            $mPath = Join-Path $exeDir $relMod
            if (Test-Path -LiteralPath $mPath -PathType Leaf) {
                $mImports = [DLSS5PeEngine]::GetImports($mPath)
                if ($mImports -contains "d3d12.dll") { return "D3D12" }
                if ($mImports -contains "d3d11.dll") { return "D3D11" }
                if ($mImports -contains "dxgi.dll")   { return "DXGI" }
                if ($mImports -contains "vulkan-1.dll") { return "VULKAN" }
                if ($mImports -contains "d3d9.dll")   { return "D3D9" }
            }
        }
    }

    # 6. Heuristica pelo Sufixo do Nome do Executavel
    if ($baseName -match '(?:^|[_-])(?:d3d|dx)12(?:[_-]|\.|$)') { return "D3D12" }
    if ($baseName -match '(?:^|[_-])(?:d3d|dx)11(?:[_-]|\.|$)') { return "D3D11" }
    if ($baseName -match '(?:^|[_-])(?:d3d|dx)9(?:[_-]|\.|$)')  { return "D3D9" }
    if ($baseName -match '(?:^|[_-])vulkan(?:[_-]|\.|$)')       { return "VULKAN" }
    if ($baseName -match '(?:^|[_-])(?:ogl|opengl)(?:[_-]|\.|$)') { return "OPENGL" }

    # Fallback seguro para DirectX Moderno
    return "DXGI"
}

function Detect-GameUpscalerType {
    param(
        [Parameter(Mandatory = $true)][string]$GameFolder,
        [Parameter(Mandatory = $false)][string]$GameRoot = ""
    )
    $searchFolders = @($GameFolder)
    if ($GameRoot -and (Test-Path -LiteralPath $GameRoot) -and ($GameRoot -ne $GameFolder)) {
        $searchFolders += $GameRoot
    }

    # 1. Presenca de DLSS Nativo (nvngx_dlss.dll ou Streamline)
    foreach ($f in $searchFolders) {
        $dlssHits = Get-ChildItem -LiteralPath $f -Filter "nvngx_dlss*.dll" -File -Recurse -Depth 4 -ErrorAction SilentlyContinue
        if (@($dlssHits).Count -gt 0) {
            # Se for apenas o modelo de reconstrucao neural injetado, continua a busca
            $onlyNr = $true
            foreach ($hit in $dlssHits) {
                if ($hit.Name -ine "nvngx_dlssnr.dll") { $onlyNr = $false; break }
            }
            if (-not $onlyNr) { return "NATIVE_DLSS" }
        }
        if (Test-Path -LiteralPath (Join-Path $f "sl.interposer.dll")) { return "NATIVE_DLSS" }
        if (Test-Path -LiteralPath (Join-Path $f "_nvngx.dll")) { return "NATIVE_DLSS" }
    }

    # 2. Presenca de FSR2
    foreach ($f in $searchFolders) {
        $fsrHits = Get-ChildItem -LiteralPath $f -Filter "*fsr2*.dll" -File -Recurse -Depth 3 -ErrorAction SilentlyContinue
        if (@($fsrHits).Count -gt 0) { return "FSR2_BRIDGE" }
    }

    # 3. Presenca de Intel XeSS
    foreach ($f in $searchFolders) {
        if (Test-Path -LiteralPath (Join-Path $f "libxess.dll")) { return "XESS_BRIDGE" }
    }

    return "FEEDER"
}

function Test-GameDlss5Installed {
    param([Parameter(Mandatory = $true)][string]$GameFolder)
    $indicators = @(
        (Join-Path $GameFolder "renodx-dlss5.addon64"),
        (Join-Path $GameFolder "dlss5-feed.addon64"),
        (Join-Path $GameFolder "dlss5-feed.addon32"),
        (Join-Path $GameFolder "OptiScaler.ini"),
        (Join-Path $GameFolder "_DLSS5_Backup\manifest.json")
    )
    foreach ($ind in $indicators) {
        if (Test-Path -LiteralPath $ind -PathType Leaf) { return $true }
    }
    return $false
}

function Resolve-GameTarget {
    param([Parameter(Mandatory = $true)][string]$TargetPath)
    $cleanPath = Sanitize-PathString -Path $TargetPath
    if (-not (Test-Path -LiteralPath $cleanPath)) {
        throw "ERR_PATH_NOT_FOUND: Caminho inexistente: $TargetPath"
    }
    $targetItem = Get-Item -LiteralPath $cleanPath
    $folder = if ($targetItem.PSIsContainer) { $targetItem.FullName } else { $targetItem.Directory.FullName }
    $root = $folder
    $exePath = $null

    # 1. Checagem de Microsoft Game Pass / Store via MicrosoftGame.config
    $xboxResult = Get-XboxGameConfigExe -GameFolder $folder
    if ($xboxResult -and (Test-Path -LiteralPath $xboxResult.Executable -PathType Leaf)) {
        $xExe = $xboxResult.Executable
        $icon = $null
        try { $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($xExe) } catch {}
        return [pscustomobject]@{
            Root          = $root
            InstallFolder = (Split-Path -Parent $xExe)
            Executable    = $xExe
            ExeName       = (Split-Path -Leaf $xExe)
            Icon          = $icon
            Architecture  = $xboxResult.Architecture
        }
    }

    $allExes = @(Get-ChildItem -LiteralPath $folder -Filter "*.exe" -File -Recurse -Depth 4 -ErrorAction SilentlyContinue)

    $ignoredDirPattern = '\\(redistributables?|_commonredist|commonredist|redist|installers?|support|tools?|launcher|dotnet|directx|vcredist|__installer|_dlss5_backup|_backup[^\\]*|engine\\binaries|host64)(\\|$)'
    $ignoredPattern = '(crashreport|crashhandler|crashpad|unitycrashhandler|unins|setup|install|config|launcher|easyanticheat|eac_|battleye|epicgameslauncher|redist|dxsetup|quickstart|webinstaller|support|console|banana|social-club|socialclub|rockstar|updater|report|activation|benchmark|dedicatedserver|helper|cleanup|touchup|bootstrap|dlss5-feed-host)'
    
    $filtered = @($allExes | Where-Object {
        $baseName = $_.BaseName.ToLowerInvariant()
        $dirName = $_.Directory.FullName.ToLowerInvariant()
        -not ($baseName -match $ignoredPattern) -and -not ($dirName -match $ignoredDirPattern)
    })
    if ($filtered.Count -eq 0) {
        $filtered = @($allExes | Where-Object { -not ($_.Directory.FullName.ToLowerInvariant() -match $ignoredDirPattern) })
    }
    if ($filtered.Count -eq 0) { $filtered = $allExes }

    # Se o executavel foi apontado diretamente, honra a escolha do usuario
    if (-not $targetItem.PSIsContainer -and $targetItem.Extension -ieq ".exe") {
        $exePath = $targetItem.FullName
    }

    if (-not $exePath) {
        # Prioridade A: Emuladores conhecidos
        foreach ($e in $filtered) {
            $emuProfile = Get-EmulatorProfile -ExeName $e.Name
            if ($emuProfile) {
                $exePath = $e.FullName
                break
            }
        }
    }

    if (-not $exePath) {
        # Prioridade B: Subpastas de engine 64-bit conhecidas (bin\x64, binaries\win64, bin64)
        $known64Subfolders = '\\(binaries\\win64|bin64|bin\\x64|bin\\x64_dx12|bin\\win64|x64)\\'
        $found64 = @($filtered | Where-Object {
            $_.FullName -imatch $known64Subfolders -and ([DLSS5PeEngine]::GetArchitecture($_.FullName) -eq "X64")
        } | Sort-Object -Property Length -Descending)
        if ($found64.Count -gt 0) {
            $exePath = $found64[0].FullName
        }
    }

    if (-not $exePath) {
        # Prioridade C: Nomes com sufixo x64
        $foundX64Named = @($filtered | Where-Object {
            $_.Name -imatch '(\.x64\.exe|_x64\.exe|win64.*\.exe)$' -and ([DLSS5PeEngine]::GetArchitecture($_.FullName) -eq "X64")
        } | Sort-Object -Property Length -Descending)
        if ($foundX64Named.Count -gt 0) {
            $exePath = $foundX64Named[0].FullName
        }
    }

    if (-not $exePath) {
        # Prioridade D: Maior executavel 64-bit na raiz ou pasta mais rasa
        $x64All = @($filtered | Where-Object { [DLSS5PeEngine]::GetArchitecture($_.FullName) -eq "X64" } | Sort-Object -Property Length -Descending)
        if ($x64All.Count -gt 0) {
            $exePath = $x64All[0].FullName
        }
    }

    if (-not $exePath -and $filtered.Count -gt 0) {
        # Prioridade E: Maior executavel x86
        $exePath = ($filtered | Sort-Object -Property Length -Descending)[0].FullName
    }

    if (-not $exePath) {
        throw "ERR_NO_VALID_EXE: Nenhum executavel valido encontrado em $folder."
    }

    $finalArch = [DLSS5PeEngine]::GetArchitecture($exePath)
    $finalFolder = Split-Path -Parent $exePath
    $icon = $null
    try { $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($exePath) } catch {}

    return [pscustomobject]@{
        Root          = $root
        InstallFolder = $finalFolder
        Executable    = $exePath
        ExeName       = (Split-Path -Leaf $exePath)
        Icon          = $icon
        Architecture  = $finalArch
    }
}

function Scan-DriveForGames {
    param(
        [string]$DriveLetter = "ALL",
        [scriptblock]$ProgressCallback = $null
    )
    $results = New-Object System.Collections.Generic.List[pscustomobject]
    $rootsToScan = New-Object System.Collections.Generic.List[string]

    # 1. Steam (Registry + LibraryFolders VDF)
    $steamRegPaths = @("HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam")
    foreach ($srp in $steamRegPaths) {
        try {
            $regProp = Get-ItemProperty -Path $srp -ErrorAction SilentlyContinue
            if ($regProp) {
                $sPath = if ($regProp.SteamPath) { $regProp.SteamPath } else { $regProp.InstallPath }
                if ($sPath) {
                    $vdf = Join-Path $sPath "steamapps\libraryfolders.vdf"
                    if (Test-Path -LiteralPath $vdf -PathType Leaf) {
                        $vdfContent = Get-Content -LiteralPath $vdf -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                        $matches = [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"')
                        foreach ($m in $matches) {
                            $p = $m.Groups[1].Value.Replace('\\', '\')
                            $common = Join-Path $p "steamapps\common"
                            if (Test-Path -LiteralPath $common) { [void]$rootsToScan.Add($common) }
                        }
                    }
                }
            }
        } catch {}
    }

    # 2. GOG Galaxy
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

    # 3. Epic Games
    $epicDir = "C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
    if (Test-Path -LiteralPath $epicDir -PathType Container) {
        $mfs = Get-ChildItem -LiteralPath $epicDir -Filter "*.item" -File -ErrorAction SilentlyContinue
        foreach ($mf in $mfs) {
            try {
                $itemData = Get-Content -LiteralPath $mf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($itemData.InstallLocation -and (Test-Path -LiteralPath $itemData.InstallLocation)) {
                    [void]$rootsToScan.Add($itemData.InstallLocation)
                }
            } catch {}
        }
    }

    # 4. Unidades Fixas (Games, Jogos, XboxGames, Emuladores)
    $drives = @()
    if ($DriveLetter -eq "ALL") {
        $drives = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.IsReady } | ForEach-Object { $_.Name })
    } else {
        $drives = @($DriveLetter)
    }
    foreach ($d in $drives) {
        foreach ($sub in @("Games", "Jogos", "SteamLibrary\steamapps\common", "XboxGames", "Emulators", "Emuladores")) {
            $checkDir = Join-Path $d $sub
            if (Test-Path -LiteralPath $checkDir) { [void]$rootsToScan.Add($checkDir) }
        }
    }

    $allGameDirs = New-Object System.Collections.Generic.List[pscustomobject]
    $seenPaths = New-Object System.Collections.Generic.HashSet[string]

    foreach ($root in $rootsToScan) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            try {
                $hasDirectExe = @(Get-ChildItem -LiteralPath $root -Filter "*.exe" -File -ErrorAction SilentlyContinue).Count -gt 0
                if ($hasDirectExe) {
                    $norm = $root.ToLowerInvariant()
                    if (-not $seenPaths.Contains($norm)) {
                        [void]$seenPaths.Add($norm)
                        [void]$allGameDirs.Add([pscustomobject]@{ Root = $root; Dir = (Get-Item -LiteralPath $root) })
                    }
                } else {
                    $dirs = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue
                    foreach ($dir in $dirs) {
                        $norm = $dir.FullName.ToLowerInvariant()
                        if (-not $seenPaths.Contains($norm)) {
                            [void]$seenPaths.Add($norm)
                            [void]$allGameDirs.Add([pscustomobject]@{ Root = $root; Dir = $dir })
                        }
                    }
                }
            } catch {}
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
        if ($isInstalled) { $order = 0 }
        elseif ($upscaler -eq "NATIVE_DLSS") { $order = 1 }
        elseif ($upscaler -eq "FSR2_BRIDGE" -or $upscaler -eq "XESS_BRIDGE") { $order = 2 }

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
