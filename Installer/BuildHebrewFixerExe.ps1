param(
    # Ahk2Exe is "universal" for v2, but ONLY if the base file is the v2 runtime EXE (per AHK forum guidance).
    # Reference: https://www.autohotkey.com/boards/viewtopic.php?t=96255
    [string]$Ahk2ExePath = 'C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe',
    [string]$AhkScript = (Join-Path $PSScriptRoot '..\src\Current Version\HebrewFixer_BiDiPaste.ahk'),
    [string]$OutExe = (Join-Path $PSScriptRoot '..\bin\HebrewFixer.exe'),

    # IMPORTANT: For v2 compilation, BaseFile must be AutoHotkey64.exe / AutoHotkey32.exe from the v2 install folder.
    [string]$BaseFile = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
)

$ErrorActionPreference = 'Stop'

function Log($msg) {
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    Write-Host "[$ts] $msg"
}

Log "Ahk2ExePath=$Ahk2ExePath"
Log "AhkScript=$AhkScript"
Log "OutExe=$OutExe"
Log "BaseFile=$BaseFile"

if (-not (Test-Path -LiteralPath $Ahk2ExePath)) {
    throw "Ahk2Exe.exe not found at: $Ahk2ExePath"
}
if (-not (Test-Path -LiteralPath $AhkScript)) {
    throw "AHK script not found at: $AhkScript"
}
if (-not (Test-Path -LiteralPath $BaseFile)) {
    throw "AutoHotkey v2 base file not found at: $BaseFile"
}

# Safety: refuse v1 stub bases (.bin). Those will compile v2 scripts as if they were v1 and produce syntax errors.
if ([IO.Path]::GetExtension($BaseFile).ToLowerInvariant() -eq '.bin') {
    throw "BaseFile points to a .bin stub ($BaseFile). For AHK v2, set BaseFile to the v2 AutoHotkey64.exe/32.exe."
}

$outDir = Split-Path -Parent $OutExe
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

# Ahk2Exe is sensitive to spaces in paths; pass a single, explicitly quoted argument string.
$ahkScriptFull = (Resolve-Path -LiteralPath $AhkScript).Path
$outExeFull = (Resolve-Path -LiteralPath $outDir).Path + '\\' + (Split-Path -Leaf $OutExe)
$baseFull = (Resolve-Path -LiteralPath $BaseFile).Path

# /silent verbose makes Ahk2Exe print useful diagnostics in the console.
$argString = "/in `"$ahkScriptFull`" /out `"$outExeFull`" /base `"$baseFull`" /silent verbose"

Log "Running: `"$Ahk2ExePath`" $argString"

$proc = Start-Process -FilePath $Ahk2ExePath -ArgumentList $argString -Wait -PassThru
Log "Ahk2Exe exit code=$($proc.ExitCode)"

if ($proc.ExitCode -ne 0) {
    throw "Ahk2Exe failed with exit code $($proc.ExitCode)"
}

if (-not (Test-Path -LiteralPath $OutExe)) {
    throw "Output EXE not produced: $OutExe"
}

Log "SUCCESS: built $OutExe"
