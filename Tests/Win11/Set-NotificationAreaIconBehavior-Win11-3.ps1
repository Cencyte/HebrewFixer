<#
HebrewFixer - Win11 Tray Icon Behavior Test Utility (v3 - registry only)

Goal
----
Set the Win11 "Other system tray icons" toggle for a specific program WITHOUT opening Settings UI.

Mechanism
---------
Windows 11 enumerates per-app notification icon settings under:
  HKCU:\Control Panel\NotifyIconSettings\{GUID}

Each subkey may contain:
- ExecutablePath (full path to exe, or sometimes just exe)
- IsPromoted (DWORD) : 1 = show icon, 0 = hide/collapse

References
----------
- SuperUser answer (2024-07): https://superuser.com/a/1849552
- Microsoft Tech Community users also report setting IsPromoted in this path.

Notes / Caveats
---------------
- These GUID subkeys can be dynamic and re-created; an app upgrade or restart can generate a new entry.
  For installer UX, it is best to run this immediately after launching the tray app at least once.
- This script is HKCU-only (per-user), which matches the Settings UI behavior.

Logging
-------
Writes a rolling journal:
  notification_area_icons_transparent-Win11-3.log

Usage
-----
powershell -NoProfile -ExecutionPolicy Bypass -File .\Set-NotificationAreaIconBehavior-Win11-3.ps1 -Match 'HebrewFixer1998.exe' -LiteralMatch -DesiredSetting 1 -Verbose
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$Match,

    [switch]$LiteralMatch,

    # 1 = show/promote, 0 = hide/collapse
    [Parameter(Mandatory=$true)]
    [ValidateSet(0,1)]
    [int]$DesiredSetting,

    # If true, if no matching key exists yet, we log and exit non-zero (installer can decide what to do)
    [switch]$FailIfMissing = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Global:LogPath = Join-Path -Path $PSScriptRoot -ChildPath 'notification_area_icons_transparent-Win11-3.log'

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','STEP','OK','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )

    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $line = "[$ts][$Level] $Message"

    $color = switch ($Level) {
        'ERROR' { 'Red' }
        'WARN'  { 'Yellow' }
        'OK'    { 'Green' }
        'STEP'  { 'Cyan' }
        'DEBUG' { 'DarkGray' }
        default { 'Gray' }
    }

    try { Write-Host $line -ForegroundColor $color } catch {}
    Write-Verbose $line
    Add-Content -LiteralPath $Global:LogPath -Value $line -Encoding UTF8
}

function Get-EffectiveRegex([string]$pattern, [bool]$literal) {
    if ($literal) { return [regex]::Escape($pattern) }
    return $pattern
}

$effective = Get-EffectiveRegex -pattern $Match -literal ([bool]$LiteralMatch)
$root = 'HKCU:\Control Panel\NotifyIconSettings'

Write-Log -Level 'INFO' -Message ('=' * 78)
Write-Log -Level 'INFO' -Message ("Run started | Script={0} | MatchInput='{1}' | LiteralMatch={2} | EffectiveRegex=/{3}/ | DesiredSetting={4}" -f $MyInvocation.MyCommand.Name, $Match, [bool]$LiteralMatch, $effective, $DesiredSetting)

try {
    if (-not (Test-Path -LiteralPath $root)) {
        throw "Registry root not found: $root"
    }

    Write-Log -Level 'STEP' -Message "Enumerating subkeys under $root"
    $keys = Get-ChildItem -LiteralPath $root -ErrorAction Stop
    Write-Log -Level 'DEBUG' -Message ("Subkey count: {0}" -f $keys.Count)

    # IMPORTANT: do not use variable name $matches/$Matches (PowerShell automatic hashtable from -match).
    $matchResults = @()

    foreach ($k in $keys) {
        $path = $k.PSPath
        $cur = $null
        $matchedOn = @()
        $allStrings = @()
        $exec = $null

        try {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop
            $exec = $p.ExecutablePath
            $cur = $p.IsPromoted

            # Collect ALL string-valued properties for robust matching (ExecutablePath is sometimes absent).
            foreach ($prop in $p.PSObject.Properties) {
                try {
                    $val = $prop.Value
                    if ($val -is [string] -and $val) {
                        $allStrings += ("{0}={1}" -f $prop.Name, $val)
                        if ([regex]::IsMatch($val, $effective)) {
                            $matchedOn += $prop.Name
                        }
                    }
                } catch {}
            }
        } catch {
            continue
        }

        if ($matchedOn.Count -gt 0) {
            $matchResults += [pscustomobject]@{
                KeyPath = $k.PSPath
                SubKey  = $k.PSChildName
                ExecutablePath = $exec
                IsPromoted = $cur
                MatchedOn = ($matchedOn -join ',')
                StringsSample = ($allStrings | Select-Object -First 8) -join ' | '
            }
        }
    }

    Write-Log -Level 'INFO' -Message ("Matching entries: {0}" -f $matchResults.Count)
    foreach ($m in $matchResults | Select-Object -First 50) {
        Write-Log -Level 'INFO' -Message ("Match | SubKey={0} | IsPromoted={1} | MatchedOn={2} | ExecutablePath={3}" -f $m.SubKey, $m.IsPromoted, $m.MatchedOn, $m.ExecutablePath)
        Write-Log -Level 'DEBUG' -Message ("  StringsSample: {0}" -f $m.StringsSample)
    }

    if ($matchResults.Count -eq 0) {
        $msg = "No NotifyIconSettings entries matched /$effective/. The app may not have registered a tray icon yet."
        if ($FailIfMissing) {
            Write-Log -Level 'ERROR' -Message $msg
            throw "MissingEntry: $msg"
        } else {
            Write-Log -Level 'WARN' -Message $msg
            return
        }
    }

    foreach ($m in $matchResults) {
        if ($PSCmdlet.ShouldProcess($m.KeyPath, "Set IsPromoted=$DesiredSetting")) {
            $before = $m.IsPromoted
            Set-ItemProperty -LiteralPath $m.KeyPath -Name 'IsPromoted' -Type DWord -Value $DesiredSetting -ErrorAction Stop
            $after = (Get-ItemProperty -LiteralPath $m.KeyPath -Name 'IsPromoted' -ErrorAction Stop).IsPromoted
            Write-Log -Level 'OK' -Message ("Set IsPromoted | SubKey={0} | {1} -> {2}" -f $m.SubKey, $before, $after)
        } else {
            Write-Log -Level 'INFO' -Message ("WhatIf: would set IsPromoted=$DesiredSetting on {0}" -f $m.KeyPath)
        }
    }

    Write-Log -Level 'OK' -Message 'Run completed'
}
catch {
    Write-Log -Level 'ERROR' -Message ("Exception: {0}" -f $_.Exception.Message)
    if ($_.ScriptStackTrace) { Write-Log -Level 'ERROR' -Message ("ScriptStackTrace: {0}" -f $_.ScriptStackTrace) }
    throw
}
finally {
    Write-Log -Level 'INFO' -Message 'Run finished'
}
