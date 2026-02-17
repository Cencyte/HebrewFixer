#requires -Version 7.0
<#!
MakeReleaseArtifacts.ps1

Creates clean, non-versioned release artifacts in bin/:
- HebrewFixer_portable.zip
- SHA256SUMS.txt

Design goals:
- Deterministic outputs (stable filenames)
- Removes only old portable zips + checksum file (no broad bin cleanup)
- Does not depend on Linux-only tools
#>

[CmdletBinding()]
param(
    [string]$BinDir = "$(Join-Path $PSScriptRoot '..\\bin')",
    [string]$ExePath = "$(Join-Path $PSScriptRoot '..\\bin\\HebrewFixer.exe')",
    [string]$SetupPath = "$(Join-Path $PSScriptRoot '..\\bin\\HebrewFixer_Setup.exe')",
    [string]$ReadmePath = "$(Join-Path $PSScriptRoot '..\\README.md')",
    [string]$LicensePath = "$(Join-Path $PSScriptRoot '..\\LICENSE')"
)

$ErrorActionPreference = 'Stop'

function Log([string]$msg) {
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    Write-Host "[$ts] $msg"
}

if (-not (Test-Path -LiteralPath $BinDir)) {
    throw "BinDir does not exist: $BinDir"
}

foreach ($p in @($ExePath, $ReadmePath, $LicensePath)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Missing input file: $p"
    }
}

$portableZip = Join-Path $BinDir 'HebrewFixer_portable.zip'
$shaFile = Join-Path $BinDir 'SHA256SUMS.txt'

# Remove older portable zips and checksum file.
Get-ChildItem -LiteralPath $BinDir -Filter 'HebrewFixer_v*_portable.zip' -ErrorAction SilentlyContinue | ForEach-Object {
    try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue } catch {}
}
foreach ($p in @($portableZip, $shaFile)) {
    if (Test-Path -LiteralPath $p) {
        try { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } catch {}
    }
}

# Build portable zip (exe + docs).
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($portableZip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in @($ExePath, $ReadmePath, $LicensePath)) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file, (Split-Path $file -Leaf), [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $zip.Dispose()
}
Log "Wrote $portableZip"

# SHA256SUMS
$lines = @()
if (Test-Path -LiteralPath $SetupPath) {
    $lines += (Get-FileHash -Algorithm SHA256 -LiteralPath $SetupPath).Hash.ToLower() + "  " + (Split-Path $SetupPath -Leaf)
}
$lines += (Get-FileHash -Algorithm SHA256 -LiteralPath $ExePath).Hash.ToLower() + "  " + (Split-Path $ExePath -Leaf)
$lines += (Get-FileHash -Algorithm SHA256 -LiteralPath $portableZip).Hash.ToLower() + "  " + (Split-Path $portableZip -Leaf)
$lines | Set-Content -LiteralPath $shaFile -Encoding ascii
Log "Wrote $shaFile"
