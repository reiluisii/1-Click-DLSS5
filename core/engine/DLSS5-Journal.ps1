# ==============================================================================
# 1 Click DLSS 5 — Transaction Journal, Safety Guards & Rollback Engine
# ==============================================================================

function Get-Dlss5RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )
    $baseStr = $BasePath.TrimEnd('\') + '\'
    if ($TargetPath.StartsWith($baseStr, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $TargetPath.Substring($baseStr.Length)
    }
    try {
        $fromUri = New-Object System.Uri($baseStr)
        $toUri = New-Object System.Uri($TargetPath)
        return [System.Uri]::UnescapeDataString($fromUri.MakeRelativeUri($toUri).ToString().Replace('/', '\'))
    } catch {
        return (Split-Path -Leaf $TargetPath)
    }
}

function Assert-GameClosedSafetyCheck {
    param(
        [Parameter(Mandatory = $true)][string]$GameFolder,
        [Parameter(Mandatory = $false)][string]$TargetExe = ""
    )
    $cleanFolder = (Resolve-Path $GameFolder).Path.TrimEnd('\')
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
    $runningMatches = @()
    foreach ($p in $procs) {
        $pPath = $p.ExecutablePath
        if ($pPath) {
            if ($pPath.StartsWith($cleanFolder, [System.StringComparison]::OrdinalIgnoreCase)) {
                $runningMatches += $p
                continue
            }
        }
        if ($TargetExe) {
            $tName = Split-Path -Leaf $TargetExe
            if ($p.Name -ieq $tName -or $p.Name -ieq "gamelaunchhelper.exe") {
                $runningMatches += $p
            }
        }
    }
    if ($runningMatches.Count -gt 0) {
        $names = ($runningMatches | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" }) -join ", "
        throw "ERR_GAME_RUNNING: O jogo ou utilitario auxiliar ainda esta em execucao: $names. Feche o jogo antes de prosseguir."
    }
}

function Test-DirectoryWritable {
    param([Parameter(Mandatory = $true)][string]$Folder)
    $testFile = Join-Path $Folder ".dlss5_perm_probe_$([System.IO.Path]::GetRandomFileName())"
    try {
        [System.IO.File]::WriteAllText($testFile, "DLSS5_OK")
        [System.IO.File]::Delete($testFile)
        return $true
    } catch {
        return $false
    }
}

function Test-AntiCheatRisk {
    param([Parameter(Mandatory = $true)][string]$GameFolder)
    $acSignatures = @(
        'easyanticheat', 'eac_server', 'battleye', 'be_service',
        'vanguard', 'vgtray', 'ricochet', 'anticheat', 'equ8'
    )
    $exes = Get-ChildItem -LiteralPath $GameFolder -Filter "*.exe" -File -Recurse -Depth 3 -ErrorAction SilentlyContinue
    foreach ($e in $exes) {
        $base = $e.BaseName.ToLowerInvariant()
        foreach ($sig in $acSignatures) {
            if ($base.Contains($sig)) { return $true }
        }
    }
    return $false
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    $hashBytes = $sha.ComputeHash($stream)
    $stream.Close()
    $stream.Dispose()
    return ( -join ($hashBytes | ForEach-Object { "{0:x2}" -f $_ }))
}

function Sanitize-PathString {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $p = $Path.Trim().Trim('"', "'")
    return $p
}

function Get-Dlss5ManifestPath {
    param([Parameter(Mandatory = $true)][string]$GameFolder)
    return (Join-Path $GameFolder "_DLSS5_Backup\manifest.json")
}

function Read-Dlss5Manifest {
    param([Parameter(Mandatory = $true)][string]$GameFolder)
    $mPath = Get-Dlss5ManifestPath -GameFolder $GameFolder
    if (-not (Test-Path -LiteralPath $mPath -PathType Leaf)) { return $null }
    try {
        return (Get-Content -LiteralPath $mPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Save-Dlss5Manifest {
    param(
        [Parameter(Mandatory = $true)][string]$GameFolder,
        [Parameter(Mandatory = $true)]$Manifest
    )
    $bDir = Join-Path $GameFolder "_DLSS5_Backup"
    if (-not (Test-Path -LiteralPath $bDir)) {
        [void](New-Item -ItemType Directory -Path $bDir -Force)
    }
    $mPath = Join-Path $bDir "manifest.json"
    $tmpPath = "$mPath.tmp"
    $json = ConvertTo-Json $Manifest -Depth 10
    [System.IO.File]::WriteAllText($tmpPath, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmpPath -Destination $mPath -Force
}

function Init-Dlss5Manifest {
    param(
        [Parameter(Mandatory = $true)][string]$GameFolder,
        [Parameter(Mandatory = $true)][string]$ExeRel,
        [Parameter(Mandatory = $true)][string]$Route,
        [Parameter(Mandatory = $false)][string]$Api = "DXGI",
        [Parameter(Mandatory = $false)][int]$Bitness = 64
    )
    $existing = Read-Dlss5Manifest -GameFolder $GameFolder
    if ($existing) {
        $existing.route = $Route
        $existing.date = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        return $existing
    }

    return [pscustomobject]@{
        version      = 1
        backupPrefix = "originals/$([System.Guid]::NewGuid().ToString())"
        date         = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        route        = $Route
        game         = [pscustomobject]@{
            dir     = $GameFolder
            exe     = $ExeRel
            api     = $Api
            bitness = $Bitness
        }
        replaced     = @()
        added        = @()
        addedDirs    = @()
        reshade      = [pscustomobject]@{
            installedByUs = $false
            file          = $null
            filesAdded    = @()
        }
    }
}

function Track-FileBeforeWrite {
    param(
        [Parameter(Mandatory = $true)][string]$GameFolder,
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $false)][string]$Kind = "runtime"
    )
    $rel = Get-Dlss5RelativePath -BasePath $GameFolder -TargetPath $TargetPath
    $backupRoot = Join-Path $GameFolder "_DLSS5_Backup"
    $origFolder = Join-Path $backupRoot $Manifest.backupPrefix
    
    if (Test-Path -LiteralPath $TargetPath -PathType Leaf) {
        $wasAdded = ($Manifest.added -contains $rel)
        if (-not $wasAdded) {
            $destBackup = Join-Path $origFolder $rel
            if (-not (Test-Path -LiteralPath $destBackup)) {
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destBackup) -Force)
                Copy-Item -LiteralPath $TargetPath -Destination $destBackup -Force
            }
            $existingRow = $Manifest.replaced | Where-Object { $_.rel -ieq $rel } | Select-Object -First 1
            if (-not $existingRow) {
                $curVer = [DLSS5PeEngine]::GetFileVersion($TargetPath)
                $Manifest.replaced += [pscustomobject]@{
                    rel        = $rel
                    oldVersion = $curVer
                    newVersion = ""
                    kind       = $Kind
                }
            }
        }
    } else {
        if ($Manifest.added -notcontains $rel) {
            $Manifest.added += $rel
        }
    }
    return $rel
}

function Restore-Dlss5Originals {
    param(
        [Parameter(Mandatory = $true)][string]$GameFolder,
        [Parameter(Mandatory = $false)][scriptblock]$LogCallback = $null
    )
    $manifest = Read-Dlss5Manifest -GameFolder $GameFolder
    if (-not $manifest) {
        throw "ERR_NO_BACKUP: Nenhum manifesto ou ponto de restauracao encontrado em $GameFolder."
    }

    $backupRoot = Join-Path $GameFolder "_DLSS5_Backup"
    $origFolder = Join-Path $backupRoot $manifest.backupPrefix

    # 1. Restaura arquivos genuinos substituidos
    if ($manifest.replaced) {
        foreach ($row in $manifest.replaced) {
            $src = Join-Path $origFolder $row.rel
            $dst = Join-Path $GameFolder $row.rel
            if (Test-Path -LiteralPath $src -PathType Leaf) {
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force)
                Copy-Item -LiteralPath $src -Destination $dst -Force
                if ($LogCallback) { &$LogCallback "Arquivo original restaurado: $($row.rel)" "OK" }
            }
        }
    }

    # 2. Deleta arquivos novos injetados por nos
    if ($manifest.added) {
        foreach ($rel in $manifest.added) {
            $target = Join-Path $GameFolder $rel
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
                if ($LogCallback) { &$LogCallback "Componente injetado removido: $rel" "INFO" }
            }
        }
    }

    # 3. Remove pastas criadas que estejam vazias
    if ($manifest.addedDirs) {
        $sortedDirs = @($manifest.addedDirs | Sort-Object { $_.Length } -Descending)
        foreach ($dirRel in $sortedDirs) {
            $dPath = Join-Path $GameFolder $dirRel
            if (Test-Path -LiteralPath $dPath -PathType Container) {
                $rem = Get-ChildItem -LiteralPath $dPath -Force -ErrorAction SilentlyContinue
                if (@($rem).Count -eq 0) {
                    Remove-Item -LiteralPath $dPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    # 4. Remove ReShade se instalado por nos
    if ($manifest.reshade -and $manifest.reshade.installedByUs -and $manifest.reshade.file) {
        $exeDir = Split-Path -Parent (Join-Path $GameFolder $manifest.game.exe)
        $hook = Join-Path $exeDir $manifest.reshade.file
        if (Test-Path -LiteralPath $hook -PathType Leaf) {
            Remove-Item -LiteralPath $hook -Force -ErrorAction SilentlyContinue
            if ($LogCallback) { &$LogCallback "Proxy ReShade removido: $($manifest.reshade.file)" "INFO" }
        }
    }

    # Marca manifesto como concluido
    $mPath = Get-Dlss5ManifestPath -GameFolder $GameFolder
    if (Test-Path -LiteralPath $mPath) {
        $donePath = "$mPath.done-$((Get-Date).Ticks)"
        Move-Item -LiteralPath $mPath -Destination $donePath -Force -ErrorAction SilentlyContinue
    }
    return $true
}
