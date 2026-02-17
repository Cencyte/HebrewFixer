<#
HebrewFixer - NotifyIconSettings Cleanup (registry-only)

Purpose
-------
On uninstall, remove per-user tray/notification icon registry entries for HebrewFixer so no stale
"Other system tray icons" state remains. This script intentionally performs NO UI automation and does
NOT launch the Settings app.

What it touches
--------------
HKCU:\Control Panel\NotifyIconSettings\*

It removes any subkey where any string-valued property contains the target app name or executable path
(e.g. HebrewFixer1998.exe).

Logging
-------
Appends to a log file path supplied by -LogPath (recommended: installer_debug_ps.log).

Exit codes
----------
0 = success
1 = errors encountered
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$AppName,

    # Optional: override log file path (shared with installer/uninstaller)
    [string]$LogPath,

    # Optional: RunId suffix used to compute log path without cmd.exe quoting issues.
    # If provided and -LogPath is empty, the script will log to:
    #   %APPDATA%\HebrewFixer\InstallLogs\installer_debug_ps_<RunId>.log
    [string]$RunId,

    # When set, logging failures will be reported to console and will cause a non-zero exit.
    # Use this during installer runs; keep it OFF for uninstall so cleanup never blocks uninstall.
    [switch]$FailIfCannotLog = $false,

    # Behavior mode:
    # - Sanitize: keep subkey but set promotion flags to desired value (default; safe for install)
    # - Delete: remove matching subkey(s) entirely (use on uninstall only if desired)
    [ValidateSet('Sanitize','Delete')]
    [string]$Mode = 'Sanitize',

    # When Mode=Sanitize, set these values.
    # NOTE: Do not use ValidateSet here; parameter binding errors occur before any logging can happen.
    # We validate manually after logging is initialized.
    [int]$DesiredPromoted = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','STEP','OK','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )

    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $line = "[$ts][$Level] $Message"

    try { Write-Host $line } catch {}

    if ($script:LogPath) {
        try {
            $dir = Split-Path -Parent $script:LogPath
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8 -ErrorAction Stop
        } catch {
            # If we can't log when requested, surface it loudly.
            if ($FailIfCannotLog) {
                try { Write-Warning "LOGGING FAILURE: $($_.Exception.Message)" } catch {}
                throw
            }
        }
    }
}

# Normalize / compute log path
$script:LogPath = $null

# Prefer explicit -LogPath
if ($LogPath) {
    $script:LogPath = $LogPath
}

# If not provided, compute from -RunId to avoid cmd.exe nested quoting issues
if (-not $script:LogPath -and $RunId) {
    try {
        $base = Join-Path $env:APPDATA 'HebrewFixer\InstallLogs'
        $script:LogPath = Join-Path $base ("installer_debug_ps_{0}.log" -f $RunId)
    } catch {
        # If this fails, leave LogPath empty; FailIfCannotLog will catch it later.
    }
}

# Diagnostic: confirm parameter binding (visible in bootstrap log even if file logging fails)
try { Write-Host ("[DBG] Raw -RunId param: '{0}'" -f $RunId) } catch {}
try { Write-Host ("[DBG] Raw -LogPath param: '{0}'" -f $LogPath) } catch {}
try { Write-Host ("[DBG] Effective script LogPath: '{0}'" -f $script:LogPath) } catch {}

# If requested, ensure we can actually create/append to the requested log path.
# This prevents silent "success" when nothing was logged.
if ($FailIfCannotLog -and $script:LogPath) {
    try {
        $dir = Split-Path -Parent $script:LogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $script:LogPath -Value ("[{0}][INFO] LOGGING CANARY | script=CleanupNotifyIconSettings" -f ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'))) -Encoding UTF8 -ErrorAction Stop
    } catch {
        try { Write-Warning "LOGGING FAILURE (CANARY): $($_.Exception.Message)" } catch {}
        exit 1
    }
}

$root = 'HKCU:\\Control Panel\\NotifyIconSettings'

Write-Log -Level 'INFO' -Message ('=' * 78)
$logPathDisplay = ''
if ($script:LogPath) { $logPathDisplay = $script:LogPath }
Write-Log -Level 'INFO' -Message ("SCRIPT START | NAME=CleanupNotifyIconSettings | Pid={0} | User={1} | AppName={2} | Mode={3} | DesiredPromoted={4} | LogPath={5}" -f $PID, $env:USERNAME, $AppName, $Mode, $DesiredPromoted, $logPathDisplay)

# Manual validation (after logging is available)
if ($Mode -eq 'Sanitize' -and ($DesiredPromoted -ne 0 -and $DesiredPromoted -ne 1)) {
    Write-Log -Level 'ERROR' -Message "Invalid DesiredPromoted=$DesiredPromoted. Expected 0 or 1."
    exit 1
}

$hadErrors = $false

try {
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Log -Level 'WARN' -Message "Registry root not found: $root (nothing to clean)"
        return
    }

    $keys = @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)
    Write-Log -Level 'INFO' -Message ("Subkey count: {0}" -f ($keys.Count))

    $needle = $AppName
    $changed = 0
    $removed = 0
    $scanned = 0

    foreach ($k in $keys) {
        $scanned++
        $match = $false
        $matchedOn = @()

        try {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop
            foreach ($prop in $p.PSObject.Properties) {
                try {
                    $val = $prop.Value
                    if ($val -is [string] -and $val) {
                        # Match either the bare exe name or common full path occurrence.
                        if ($val -like "*${needle}*" -or $val -like "*\\${needle}*") {
                            $match = $true
                            $matchedOn += $prop.Name
                        }
                    }
                } catch {}
            }
        } catch {
            continue
        }

        if ($match) {
            if ($Mode -eq 'Delete') {
                try {
                    Write-Log -Level 'STEP' -Message ("Deleting subkey {0} (matched on: {1})" -f $k.PSChildName, ($matchedOn -join ','))
                    Remove-Item -LiteralPath $k.PSPath -Recurse -Force -ErrorAction Stop
                    $removed++
                } catch {
                    $hadErrors = $true
                    Write-Log -Level 'ERROR' -Message ("Failed deleting {0}: {1}" -f $k.PSChildName, $_.Exception.Message)
                }
            }
            else {
                try {
                    Write-Log -Level 'STEP' -Message ("Sanitizing promotion flags in {0} => {1} (matched on: {2})" -f $k.PSChildName, $DesiredPromoted, ($matchedOn -join ','))
                    # These values are what Windows uses for the tray pinning UI.
                    # Create them if missing.
                    New-ItemProperty -LiteralPath $k.PSPath -Name 'IsPromoted' -Value $DesiredPromoted -PropertyType DWord -Force | Out-Null
                    New-ItemProperty -LiteralPath $k.PSPath -Name 'IsUserPromoted' -Value $DesiredPromoted -PropertyType DWord -Force | Out-Null
                    $changed++
                } catch {
                    $hadErrors = $true
                    Write-Log -Level 'ERROR' -Message ("Failed sanitizing {0}: {1}" -f $k.PSChildName, $_.Exception.Message)
                }
            }
        }
    }

    Write-Log -Level 'OK' -Message ("Cleanup complete | mode={0} scanned={1} changed={2} removed={3}" -f $Mode, $scanned, $changed, $removed)
$exitCode = 0
if ($hadErrors) { $exitCode = 1 }
Write-Log -Level 'INFO' -Message ("SCRIPT END | exit={0}" -f $exitCode)
}
catch {
    $hadErrors = $true
    Write-Log -Level 'ERROR' -Message ("Unhandled exception: {0}" -f $_.Exception.Message)
}
finally {
    Write-Log -Level 'INFO' -Message ("SCRIPT END | Success={0}" -f (-not $hadErrors))
    Write-Log -Level 'INFO' -Message 'Run finished'
}

if ($hadErrors) { exit 1 } else { exit 0 }
