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
    [int]$BuildRetries = 8,
    [int]$BuildRetryDelayMs = 650,
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

$runId = [Guid]::NewGuid().ToString('N')
$tmpOutDirLocal = Join-Path $OutDirLocal ("tmp_inno_out_" + $runId)
New-Item -ItemType Directory -Path $tmpOutDirLocal | Out-Null

$tmpBase = "HebrewFixer_Setup_tmp_" + $runId
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

# Optional signing: set env vars consumed by the .iss preprocessor.
try {
    # In WSL pwsh, $env:USERPROFILE may be empty. Derive the Windows PFX path via wslpath.
    $pfxWin = $null
    $pfxLocal = $null

    if ($IsWindows) {
        $pfxWin = Join-Path $env:USERPROFILE 'HebrewFixer_codesign.pfx'
        $pfxLocal = $pfxWin
    } else {
        # Known expected location of the PFX in this environment.
        $pfxLocal = '/mnt/c/Users/FireSongz/HebrewFixer_codesign.pfx'
        if (Test-Path -LiteralPath $pfxLocal) {
            $pfxWin = (& wslpath -w -- "$pfxLocal" 2>$null).Trim()
        }
    }

    if (-not $pfxWin -or -not $pfxLocal) {
        throw "Could not determine PFX path (pfxWin/pfxLocal)"
    }
    if (Test-Path -LiteralPath $pfxLocal) {
        $psi.Environment['HF_SIGN_PFX'] = $pfxWin

        # Pass password if caller set it in env.
        if ($env:HF_SIGN_PFX_PASS) {
            $psi.Environment['HF_SIGN_PFX_PASS'] = $env:HF_SIGN_PFX_PASS
        }

        # Prefer newest x64 signtool if present.
        $sig1 = 'C:\\Program Files (x86)\\Windows Kits\\10\\bin\\10.0.26100.0\\x64\\signtool.exe'
        $sig2 = 'C:\\Program Files (x86)\\Windows Kits\\10\\bin\\10.0.19041.0\\x64\\signtool.exe'
        if (Test-Path (Convert-ToLocalPathIfNeeded $sig1)) {
            $psi.Environment['HF_SIGNTOOL_PATH'] = $sig1
        } elseif (Test-Path (Convert-ToLocalPathIfNeeded $sig2)) {
            $psi.Environment['HF_SIGNTOOL_PATH'] = $sig2
        }

        Log "Signing enabled (HF_SIGN_PFX=$pfxWin)"
    } else {
        Log "Signing disabled (no PFX at $pfxWin)"
    }
} catch {
    Log "Signing config error: $($_.Exception.Message)"
}

$exitCode = $null
$stdout = $null
$stderr = $null

for ($attempt = 1; $attempt -le $BuildRetries; $attempt++) {
    Log "Running (attempt $attempt/$BuildRetries): `"$($psi.FileName)`" $($psi.Arguments)"
    $p = [System.Diagnostics.Process]::new()
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    $exitCode = $p.ExitCode

    Log "ISCC exit code=$exitCode"
    if ($stdout) { Log "ISCC stdout:`n$stdout" }
    if ($stderr) { Log "ISCC stderr:`n$stderr" }

    if ($exitCode -eq 0) {
        break
    }

    # Retry resource-update errors which can happen when Windows has a transient lock.
    if (
        $stdout -match 'EndUpdateResource failed \(\d+\)' -or $stderr -match 'EndUpdateResource failed \(\d+\)' -or
        $stdout -match 'being used by another process' -or $stderr -match 'being used by another process'
    ) {
        if ($attempt -lt $BuildRetries) {
            Log "ISCC resource update error (110). Retrying after ${BuildRetryDelayMs}ms..."
            Start-Sleep -Milliseconds $BuildRetryDelayMs
            continue
        }
    }

    throw "ISCC failed with exit code $exitCode"
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

# Post-sign (more reliable than relying on ISCC SignTools, especially across environments)
try {
    if ($psi.Environment.ContainsKey('HF_SIGN_PFX') -and $psi.Environment['HF_SIGN_PFX']) {
        $pfxWin = $psi.Environment['HF_SIGN_PFX']
        $sigWin = $psi.Environment['HF_SIGNTOOL_PATH']
        $pass = $null
        if ($psi.Environment.ContainsKey('HF_SIGN_PFX_PASS')) { $pass = $psi.Environment['HF_SIGN_PFX_PASS'] }

        $finalWin = Convert-ToWindowsPathIfNeeded $finalInstallerLocal

        $passArg = ''
        if ($pass) { $passArg = " /p `"$pass`"" }

        $cmd = "& `"$sigWin`" sign /fd SHA256 /f `"$pfxWin`"$passArg `"$finalWin`""
        Log "Signing installer: $cmd"

        # Run in Windows PowerShell so signtool.exe can execute
        $out = & powershell.exe -NoProfile -Command $cmd 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "signtool sign failed (exit=$LASTEXITCODE): $out"
        }
        if ($out) { Log "signtool output:`n$out" }

        Log "SIGNED: $finalInstallerLocal"
    }
} catch {
    Log "SIGNING FAILED: $($_.Exception.Message)"
}

