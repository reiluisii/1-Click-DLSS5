# ==============================================================================
# 1 Click DLSS 5 — Release Packaging & Privacy Audit Engine (v3.0.1-fix)
# ==============================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path "$PSScriptRoot/..").Path
$distDir = Split-Path -Parent $repoRoot
$zipOutput = Join-Path $distDir "1-Click-DLSS5-v3.0.1-fix.zip"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " 1 Click DLSS 5 — Release Packaging & Privacy Audit (v3.0.1-fix)" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "Source:      $repoRoot"
Write-Host "Destination: $zipOutput"

# 1. Sanitize Logs and Caches
Write-Host "`n[1/5] Sanitizing developer telemetry and cache files..." -ForegroundColor Yellow
$logPath = Join-Path $repoRoot "core/1-Click-DLSS5.log"
if (Test-Path -LiteralPath $logPath) {
    Set-Content -LiteralPath $logPath -Value "" -NoNewline
    Write-Host "  -> Truncated core/1-Click-DLSS5.log to 0 bytes." -ForegroundColor Green
}

$cfgPath = Join-Path $repoRoot "core/assets/config.json"
if (Test-Path -LiteralPath $cfgPath) {
    $cleanCfg = @{
        Language             = "AUTO"
        AutoScanOnStartup    = $false
        ScanDrives           = "ALL"
        LastSelectedGamePath = ""
        CustomGamePaths      = @()
    }
    $cleanCfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding UTF8
    Write-Host "  -> Reset core/assets/config.json to clean defaults." -ForegroundColor Green
}

$cachePath = Join-Path $repoRoot "core/assets/games_cache.json"
if (Test-Path -LiteralPath $cachePath) {
    Set-Content -LiteralPath $cachePath -Value "[]`r`n" -Encoding UTF8
    Write-Host "  -> Reset core/assets/games_cache.json to empty list." -ForegroundColor Green
}

# 2. Validate Shader Payload
Write-Host "`n[2/5] Validating shader payload integrity..." -ForegroundColor Yellow
$shaderDir = Join-Path $repoRoot "core/payload/feeder/shaders"
$forbidden = @("FXAA.fx", "FXAA.fxh", "SMAA.fx", "SMAA.fxh")
foreach ($fb in $forbidden) {
    $fbPath = Join-Path $shaderDir $fb
    if (Test-Path -LiteralPath $fbPath) {
        Remove-Item -LiteralPath $fbPath -Force
        Write-Host "  -> Removed forbidden shader: $fb" -ForegroundColor Yellow
    }
}
Write-Host "  -> Shader payload validated (no broken FXAA/SMAA shaders)." -ForegroundColor Green

# 3. Validate PowerShell BOM & AST Parsing
Write-Host "`n[3/5] Validating PowerShell script encoding & syntax..." -ForegroundColor Yellow
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$psFiles = Get-ChildItem -LiteralPath (Join-Path $repoRoot "core") -Filter "*.ps1" -Recurse -File
foreach ($pf in $psFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($pf.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if (-not $hasBom) {
        $text = [System.IO.File]::ReadAllText($pf.FullName, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($pf.FullName, $text, $utf8Bom)
        Write-Host "  -> Added UTF-8 BOM to $($pf.Name)" -ForegroundColor Yellow
    }
    $tok = $null; $err = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($pf.FullName, [ref]$tok, [ref]$err)
    if ($err.Count -gt 0) {
        throw "Syntax error in $($pf.FullName): $($err[0].Message)"
    }
}
Write-Host "  -> All $($psFiles.Count) PowerShell scripts verified with valid UTF-8 BOM and AST." -ForegroundColor Green

# 4. Create Release Zip Archive
Write-Host "`n[4/5] Packaging release archive..." -ForegroundColor Yellow
if (Test-Path -LiteralPath $zipOutput) {
    Remove-Item -LiteralPath $zipOutput -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zipStream = [System.IO.File]::Open($zipOutput, [System.IO.FileMode]::CreateNew)
$archive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)

$excludeDirNames = @(".git", ".vs", ".vscode", "scratch", "bin", "obj", "__pycache__")
$excludeFileNames = @("1-Click-DLSS5.log", ".gitattributes", ".gitignore", "desktop.ini", "Thumbs.db")

$allFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File
$packagedCount = 0

foreach ($file in $allFiles) {
    # Check directory exclusions
    $skip = $false
    $parentParts = $file.DirectoryName.Substring($repoRoot.Length).Split([System.IO.Path]::DirectorySeparatorChar)
    foreach ($part in $parentParts) {
        if ($excludeDirNames -contains $part) {
            $skip = $true
            break
        }
    }
    if ($skip) { continue }

    # Check file exclusions
    if ($excludeFileNames -contains $file.Name -or $file.Extension -ieq ".tmp" -or $file.Extension -ieq ".zip") {
        continue
    }

    $relPath = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
    $entryName = "1-Click-DLSS5/" + $relPath.Replace('\', '/')

    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    $packagedCount++
}

$archive.Dispose()
$zipStream.Dispose()

$zipItem = Get-Item -LiteralPath $zipOutput
$zipSizeMb = [math]::Round($zipItem.Length / 1MB, 2)
Write-Host "  -> Successfully packaged $packagedCount files into '$zipOutput' ($zipSizeMb MB)." -ForegroundColor Green

# 5. Security & Privacy Telemetry Audit
Write-Host "`n[5/5] Executing post-packaging security and privacy leak audit..." -ForegroundColor Yellow
$leakPatterns = @(
    'Luis\s+Eduardo',
    'C:\\OneDrive',
    'E:\\JOGOS',
    'FreshWomen'
)

$auditStream = [System.IO.File]::OpenRead($zipOutput)
$auditArchive = New-Object System.IO.Compression.ZipArchive($auditStream, [System.IO.Compression.ZipArchiveMode]::Read)
$leakCount = 0

foreach ($entry in $auditArchive.Entries) {
    $ext = [System.IO.Path]::GetExtension($entry.FullName).ToLowerInvariant()
    if (@(".json", ".txt", ".md", ".log", ".ini", ".cfg", ".conf") -contains $ext) {
        $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd()
        $reader.Close()

        foreach ($pat in $leakPatterns) {
            if ($text -match $pat) {
                Write-Host "  [LEAK DETECTED] File '$($entry.FullName)' matched pattern '$pat'!" -ForegroundColor Red
                $leakCount++
            }
        }
    }
}

$auditArchive.Dispose()
$auditStream.Dispose()

if ($leakCount -gt 0) {
    throw "AUDIT FAILED: $leakCount privacy/telemetry leaks detected in release package!"
}

Write-Host "  -> Audit PASSED: Zero personal data, zero developer logs detected in package." -ForegroundColor Green

Write-Host "`n==================================================================" -ForegroundColor Green
Write-Host " Release v3.0.1-fix successfully built, verified, and audited!" -ForegroundColor Green
Write-Host " Location: $zipOutput" -ForegroundColor Green
Write-Host " Size:     $zipSizeMb MB ($($zipItem.Length) bytes)" -ForegroundColor Green
Write-Host " Files:    $packagedCount files" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
