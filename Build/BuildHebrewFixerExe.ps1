param(
    # Ahk2Exe is "universal" for v2, but ONLY if the base file is the v2 runtime EXE (per AHK forum guidance).
    # Reference: https://www.autohotkey.com/boards/viewtopic.php?t=96255
    [string]$Ahk2ExePath = 'C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe',
    [string]$AhkScript = (Join-Path $PSScriptRoot '..\src\Current Version\HebrewFixer_BiDiPaste.ahk'),
    [string]$OutExe = (Join-Path $PSScriptRoot '..\bin\HebrewFixer.exe'),

    # Bakes the app icon into the compiled EXE resources (this is NOT the runtime tray icon).
    # Default: your Affinity-style icon.
    [string]$IconFile = (Join-Path $PSScriptRoot '..\\Icon\\ICOs\\hebrewfixer_app.ico'),

    # IMPORTANT: For v2 compilation, BaseFile must be AutoHotkey64.exe / AutoHotkey32.exe from the v2 install folder.
    [string]$BaseFile = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
)

$ErrorActionPreference = 'Stop'

function Log($msg) {
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    Write-Host "[$ts] $msg"
}

function Convert-ToLocalPathIfNeeded([string]$p) {
    if (-not $p) { return $p }

    # On WSL/Unix PowerShell, accept Windows paths like C:\... by converting them to /mnt/c/...
    if (-not $IsWindows) {
        try {
            if ($p -match '^[a-zA-Z]:\\') {
                $u = & wslpath -u -- "$p" 2>$null
                if ($LASTEXITCODE -eq 0 -and $u) {
                    return $u.Trim()
                }
            }
        } catch {
            # best-effort
        }
    }

    return $p
}

function Convert-ToWindowsPathIfNeeded([string]$p) {
    if (-not $p) { return $p }

    # When running in WSL/Unix but invoking Windows Ahk2Exe.exe, its /in /out etc must be Windows paths.
    if (-not $IsWindows) {
        try {
            if ($p -match '^/mnt/[a-zA-Z]/') {
                $w = & wslpath -w -- "$p" 2>$null
                if ($LASTEXITCODE -eq 0 -and $w) {
                    return $w.Trim()
                }
            }
        } catch {
            # best-effort
        }
    }

    return $p
}

# Normalize tool paths for the current host OS (Windows PowerShell vs WSL pwsh).
$Ahk2ExePathLocal = Convert-ToLocalPathIfNeeded $Ahk2ExePath
$AhkScriptLocal   = Convert-ToLocalPathIfNeeded $AhkScript
$OutExeLocal      = Convert-ToLocalPathIfNeeded $OutExe

$IconFileLocal    = Convert-ToLocalPathIfNeeded $IconFile
$BaseFileLocal    = Convert-ToLocalPathIfNeeded $BaseFile

Log "Ahk2ExePath=$Ahk2ExePath (local=$Ahk2ExePathLocal)"
Log "AhkScript=$AhkScript (local=$AhkScriptLocal)"
Log "OutExe=$OutExe (local=$OutExeLocal)"
Log "IconFile=$IconFile (local=$IconFileLocal)"
Log "BaseFile=$BaseFile (local=$BaseFileLocal)"

if (-not (Test-Path -LiteralPath $Ahk2ExePathLocal)) {
    throw "Ahk2Exe.exe not found at: $Ahk2ExePathLocal"
}
if (-not (Test-Path -LiteralPath $AhkScriptLocal)) {
    throw "AHK script not found at: $AhkScriptLocal"
}

# Remove previous output EXE so the build doesn't fail due to file locks or stale metadata.
try {
    if (Test-Path -LiteralPath $OutExeLocal) {
        Remove-Item -LiteralPath $OutExeLocal -Force -ErrorAction SilentlyContinue
    }
} catch {
    # non-fatal
}
if (-not (Test-Path -LiteralPath $IconFileLocal)) {
    throw "Icon file not found at: $IconFileLocal"
}
if (-not (Test-Path -LiteralPath $BaseFileLocal)) {
    throw "AutoHotkey v2 base file not found at: $BaseFileLocal"
}

# Safety: refuse v1 stub bases (.bin). Those will compile v2 scripts as if they were v1 and produce syntax errors.
if ([IO.Path]::GetExtension($BaseFile).ToLowerInvariant() -eq '.bin') {
    throw "BaseFile points to a .bin stub ($BaseFile). For AHK v2, set BaseFile to the v2 AutoHotkey64.exe/32.exe."
}

$outDir = Split-Path -Parent $OutExeLocal
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

# Ahk2Exe is sensitive to spaces in paths; pass a single, explicitly quoted argument string.
# Resolve paths locally, then convert to Windows paths if needed for Ahk2Exe arguments.
$ahkScriptFullLocal = (Resolve-Path -LiteralPath $AhkScriptLocal).Path
$outExeFullLocal = Join-Path -Path (Resolve-Path -LiteralPath $outDir).Path -ChildPath (Split-Path -Leaf $OutExeLocal)
$iconFullLocal = (Resolve-Path -LiteralPath $IconFileLocal).Path
$baseFullLocal = (Resolve-Path -LiteralPath $BaseFileLocal).Path

$ahkScriptArg = Convert-ToWindowsPathIfNeeded $ahkScriptFullLocal
$outExeArg    = Convert-ToWindowsPathIfNeeded $outExeFullLocal
$iconArg      = Convert-ToWindowsPathIfNeeded $iconFullLocal
$baseArg      = Convert-ToWindowsPathIfNeeded $baseFullLocal

# /silent verbose makes Ahk2Exe print useful diagnostics in the console.
$argString = "/in `"$ahkScriptArg`" /out `"$outExeArg`" /icon `"$iconArg`" /base `"$baseArg`" /silent verbose"

Log "Running: `"$Ahk2ExePathLocal`" $argString"

# Run Ahk2Exe with captured stdout/stderr so failures are diagnosable.
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Ahk2ExePathLocal
$psi.Arguments = $argString
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
[void]$p.Start()
$stdout = $p.StandardOutput.ReadToEnd()
$stderr = $p.StandardError.ReadToEnd()
$p.WaitForExit()

Log "Ahk2Exe exit code=$($p.ExitCode)"
if ($stdout) { Log "Ahk2Exe stdout:\n$stdout" }
if ($stderr) { Log "Ahk2Exe stderr:\n$stderr" }

if ($p.ExitCode -ne 0) {
    throw "Ahk2Exe failed with exit code $($p.ExitCode)"
}

if (-not (Test-Path -LiteralPath $OutExeLocal)) {
    throw "Output EXE not produced: $OutExeLocal"
}

Log "SUCCESS: built $OutExeLocal"
