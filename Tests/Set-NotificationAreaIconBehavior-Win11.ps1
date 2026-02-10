<#
HebrewFixer - Win11 Tray Icon Behavior Test Utility

Purpose
-------
This script targets the Windows 11 Taskbar settings UI (NOT the Win10 legacy "Notification Area Icons" dialog)
so we can deterministically set the tray icon visibility behavior for a specific app.

Design goals
------------
- Conservative: fewer moving parts, early termination on unexpected UI.
- Verbose + journal logging to file for every step with timestamps.
- Mandatory 5s delay between major operations.
- No coordinate clicking assumptions. Prefer UI Automation element discovery.

Log
---
Writes a rolling log file next to this script:
  notification_area_icons_transparent-Win11.log

Usage (example)
--------------
# Attempt to set HebrewFixer1998.exe to be always visible (best-effort; exact UI may vary by build)
powershell -NoProfile -ExecutionPolicy Bypass -File .\Set-NotificationAreaIconBehavior-Win11.ps1 -Match 'HebrewFixer1998.exe' -LiteralMatch -DesiredState On -Verbose

Notes
-----
- Run on Windows (interactive desktop) in Windows PowerShell.
- Windows 11 Taskbar settings UI is known to change across builds; this script is exploratory.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    # Match pattern for the app entry; by default regex
    [Parameter(Mandatory=$true)]
    [string]$Match,

    [switch]$LiteralMatch,

    # Intended end state for the Win11 tray icon toggle for the matched entry
    [Parameter(Mandatory=$true)]
    [ValidateSet('On','Off')]
    [string]$DesiredState,

    # Optional window name regex for Settings app (localized systems may differ)
    [string]$SettingsWindowRegex = 'Settings',

    [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Global:OperationDelaySeconds = 5
$Global:LogPath = Join-Path -Path $PSScriptRoot -ChildPath 'notification_area_icons_transparent-Win11.log'

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

function Step-Delay([string]$StepName) {
    Write-Log -Level 'DEBUG' -Message ("Delay {0}s (mandatory) after step: {1}" -f $Global:OperationDelaySeconds, $StepName)
    Start-Sleep -Seconds $Global:OperationDelaySeconds
}

function Add-UIAutomationAssemblies {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
}

function Wait-ForWindow([string]$nameRegex, [TimeSpan]$timeout) {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Window
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed -lt $timeout) {
        $wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
        foreach ($w in $wins) {
            try {
                $n = $w.Current.Name
                if ($n -match $nameRegex) { return $w }
            } catch {}
        }
        Start-Sleep -Milliseconds 200
    }

    throw "Timed out waiting for window name matching regex: $nameRegex"
}

function Start-Win11TrayIconsSettings {
    # Win11 Settings deep link (may vary):
    # ms-settings:taskbar
    # We start at taskbar; further navigation will depend on the UI.
    Start-Process 'explorer.exe' 'ms-settings:taskbar'
}

function Get-EffectiveRegex([string]$input, [bool]$literal) {
    if ($literal) { return [regex]::Escape($input) }
    return $input
}

Add-UIAutomationAssemblies

$effectiveMatchRegex = Get-EffectiveRegex -input $Match -literal ([bool]$LiteralMatch
)

Write-Log -Level 'INFO' -Message ('=' * 78)
Write-Log -Level 'INFO' -Message ("Run started | Script={0} | MatchInput='{1}' | LiteralMatch={2} | EffectiveRegex=/{3}/ | DesiredState={4}" -f $MyInvocation.MyCommand.Name, $Match, [bool]$LiteralMatch, $effectiveMatchRegex, $DesiredState)

try {
    Write-Log -Level 'STEP' -Message 'Launching Win11 Taskbar settings (ms-settings:taskbar)'
    Start-Win11TrayIconsSettings
    Step-Delay 'launch settings'

    $timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    Write-Log -Level 'STEP' -Message ("Waiting for Settings window /{0}/" -f $SettingsWindowRegex)
    $win = Wait-ForWindow -nameRegex $SettingsWindowRegex -timeout $timeout
    Write-Log -Level 'OK' -Message ("Found window | Name='{0}'" -f $win.Current.Name)
    Step-Delay 'found settings window'

    # Conservative early termination placeholder:
    # The Win11 UI structure for the tray icons list differs across builds.
    # Next iteration will implement element discovery for "Other system tray icons" list and toggles.
    Write-Log -Level 'WARN' -Message 'Win11 tray icon list automation not yet implemented in this skeleton; stopping early by design.'
    throw 'NotImplemented: Win11 tray icon list automation to be implemented next.'
}
catch {
    Write-Log -Level 'ERROR' -Message ("Exception: {0}" -f $_.Exception.Message)
    if ($_.ScriptStackTrace) { Write-Log -Level 'ERROR' -Message ("ScriptStackTrace: {0}" -f $_.ScriptStackTrace) }
    throw
}
finally {
    Write-Log -Level 'INFO' -Message 'Run finished'
}
