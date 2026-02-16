#requires -Version 7.0
<#!
BuildInstaller.ps1

Builds HebrewFixer_Setup.exe using Inno Setup (ISCC.exe).
Designed to work on:
- Windows PowerShell / PowerShell 7 on Windows
- PowerShell 7 under WSL (calls Windows ISCC.exe via /mnt/c/...)

Strategy:
- Compile to a temp output folder + temp filename to avoid file-lock/resource-update issues.
- Then replace bin/HebrewFixer_Setup.exe.
#>

[CmdletBinding()]
param(
    [string]$IsccPath = "C:\\Program Files (x86)\\Inno Setup 6\\ISCC.exe",
    [string]$IssFile = "$(Join-Path $PSScriptRoot 'HebrewFixer_Setup.iss')",
    [string]$OutDir = "$(Join-Path $PSScriptRoot '..\\bin')",
    [string]$OutFileName = "HebrewFixer_Setup.exe",
    [int]$ReplaceRetries = 8,
    [int]$ReplaceRetryDelayMs = 300
)

$ErrorActionPreference = 'Stop'

function Log([string]$msg) {
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    Write-Host "[$ts] $msg"
}

function Convert-ToLocalPathIfNeeded([string]$p) {
    if (-not $p) { return $p }
    if ($IsWindows) { return $p }

    # In WSL, allow callers to pass C:\... and convert to /mnt/c/... for filesystem ops.
    if ($p -match '^[a-zA-Z]:\\') {
        try {
            $l = & wslpath -u -- "$p" 2>$null
            if ($LASTEXITCODE -eq 0 -and $l) { return $l.Trim() }
        } catch {}
    }

    return $p
}

function Convert-ToWindowsPathIfNeeded([string]$p) {
    if (-not $p) { return $p }
    if ($IsWindows) { return $p }

    # In WSL, if the path is /mnt/<drive>/..., convert to C:\... for Windows tools.
    if ($p -match '^/mnt/[a-zA-Z]/') {
        try {
            $w = & wslpath -w -- "$p" 2>$null
            if ($LASTEXITCODE -eq 0 -and $w) { return $w.Trim() }
        } catch {}
    }

    return $p
}

$IsccPathLocal = Convert-ToLocalPathIfNeeded $IsccPath
$IssFileLocal  = Convert-ToLocalPathIfNeeded $IssFile
$OutDirLocal   = Convert-ToLocalPathIfNeeded $OutDir

if (-not (Test-Path -LiteralPath $IsccPathLocal)) {
    throw "ISCC.exe not found at: $IsccPath (local=$IsccPathLocal)"
}
if (-not (Test-Path -LiteralPath $IssFileLocal)) {
    throw ".iss file not found at: $IssFile (local=$IssFileLocal)"
}

if (-not (Test-Path -LiteralPath $OutDirLocal)) {
    New-Item -ItemType Directory -Path $OutDirLocal | Out-Null
}

$tmpOutDirLocal = Join-Path $OutDirLocal 'tmp_inno_out'
if (Test-Path -LiteralPath $tmpOutDirLocal) {
    # best effort cleanup
    try { Remove-Item -LiteralPath $tmpOutDirLocal -Recurse -Force } catch {}
}
New-Item -ItemType Directory -Path $tmpOutDirLocal | Out-Null

$tmpBase = "HebrewFixer_Setup_tmp"
$tmpInstallerLocal = Join-Path $tmpOutDirLocal ($tmpBase + '.exe')
$finalInstallerLocal = Join-Path $OutDirLocal $OutFileName

# Convert arguments for ISCC (Windows tool)
$IsccExeForLaunch = $IsccPathLocal
$issForLaunch     = Convert-ToWindowsPathIfNeeded $IssFileLocal
$outDirForLaunch  = Convert-ToWindowsPathIfNeeded $tmpOutDirLocal

Log "ISCC=$IsccPath (local=$IsccPathLocal)"
Log "ISS=$IssFile (local=$IssFileLocal)"
Log "OutDir=$OutDir (local=$OutDirLocal)"
Log "TempOutDir=$tmpOutDirLocal"

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $IsccExeForLaunch
$psi.Arguments = "/O$outDirForLaunch /F$tmpBase `"$issForLaunch`""
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

Log "Running: `"$($psi.FileName)`" $($psi.Arguments)"
$p = [System.Diagnostics.Process]::new()
$p.StartInfo = $psi
[void]$p.Start()
$stdout = $p.StandardOutput.ReadToEnd()
$stderr = $p.StandardError.ReadToEnd()
$p.WaitForExit()
Log "ISCC exit code=$($p.ExitCode)"
if ($stdout) { Log "ISCC stdout:`n$stdout" }
if ($stderr) { Log "ISCC stderr:`n$stderr" }
if ($p.ExitCode -ne 0) {
    throw "ISCC failed with exit code $($p.ExitCode)"
}

if (-not (Test-Path -LiteralPath $tmpInstallerLocal)) {
    throw "Expected temp installer not produced: $tmpInstallerLocal"
}

# Replace final output with retry (file may be locked by AV/indexer/explorer)
for ($i = 1; $i -le $ReplaceRetries; $i++) {
    try {
        Copy-Item -LiteralPath $tmpInstallerLocal -Destination $finalInstallerLocal -Force
        break
    } catch {
        if ($i -eq $ReplaceRetries) { throw }
        Start-Sleep -Milliseconds $ReplaceRetryDelayMs
    }
}

Log "SUCCESS: built $finalInstallerLocal"
