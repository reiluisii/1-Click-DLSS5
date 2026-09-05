<#
.SYNOPSIS
    Re-runs the integrity checks from the 2026-09-04 security review against your local copy.

.DESCRIPTION
    For every binary listed in tools\payload-manifest.json this script:
      1. Computes the SHA-256 and compares it to the reviewed hash.
      2. Checks the Authenticode signature with Get-AuthenticodeSignature and compares
         the signer and status to what the review recorded.
    Any difference means your copy is NOT the package that was reviewed and you should
    not run it until you know why.

    Run from the repository root:  powershell -ExecutionPolicy Bypass -File tools\Verify-Payload.ps1
#>
[CmdletBinding()]
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$manifestPath = Join-Path $PSScriptRoot "payload-manifest.json"
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$fail = 0; $warn = 0

Write-Host ""
Write-Host "1 Click DLSS 5 payload verification (manifest reviewed $($manifest.reviewed))" -ForegroundColor Cyan
Write-Host ("=" * 78)

foreach ($prop in $manifest.files.PSObject.Properties) {
    $rel = $prop.Name; $exp = $prop.Value
    $path = Join-Path $Root ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host ("[MISSING] {0}" -f $rel) -ForegroundColor Yellow; $warn++; continue
    }

    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
    $hashOk = ($hash -eq $exp.sha256)

    $sigOk = $true; $sigText = "not signed (as expected)"
    if ($rel -notmatch '\.zip$') {
        $sig = Get-AuthenticodeSignature -LiteralPath $path
        $signer = if ($sig.SignerCertificate) { ($sig.SignerCertificate.Subject -split ',')[0] -replace '^CN=', '' } else { $null }
        if ($exp.expectedSigner) {
            # ReShade signs with a self-signed certificate, so Windows reports UnknownError (untrusted root)
            # even though the file hash matches the signature. Only HashMismatch/NotSigned mean tampering.
            $sigOk = ($signer -eq $exp.expectedSigner -and $sig.Status -in @('Valid', 'UnknownError'))
            $sigText = "signer='$signer' status=$($sig.Status)"
        }
        else {
            $sigOk = ($sig.Status -ne 'Valid')   # an unexpected valid signature is also a change
            $sigText = "status=$($sig.Status)"
        }
    }

    if ($hashOk -and $sigOk) {
        Write-Host ("[OK]      {0}  ({1})" -f $rel, $sigText) -ForegroundColor Green
    }
    else {
        $fail++
        Write-Host ("[CHANGED] {0}" -f $rel) -ForegroundColor Red
        if (-not $hashOk) { Write-Host ("          sha256 expected {0}`n          sha256 actual   {1}" -f $exp.sha256, $hash) -ForegroundColor Red }
        if (-not $sigOk)  { Write-Host ("          signature: {0}; expected signer '{1}'" -f $sigText, $exp.expectedSigner) -ForegroundColor Red }
    }
    if ($exp.note) { Write-Host ("          note: {0}" -f $exp.note) -ForegroundColor DarkYellow }
}

Write-Host ("=" * 78)
if ($fail -eq 0) { Write-Host "All binaries match the reviewed package. ($warn missing)" -ForegroundColor Green }
else { Write-Host "$fail file(s) differ from the reviewed package. Do not run until you understand why." -ForegroundColor Red }

Write-Host ""
Write-Host "Reminder from the review: nvngx_dlssnr.dll is a modified, unsigned copy of a leaked NVIDIA build." -ForegroundColor DarkYellow
Write-Host "A matching hash means it is the SAME file that was reviewed, not that its contents are trustworthy." -ForegroundColor DarkYellow
exit $fail
