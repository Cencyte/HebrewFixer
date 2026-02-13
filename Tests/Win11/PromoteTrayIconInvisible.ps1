<#
.SYNOPSIS
    Promote HebrewFixer tray icon invisibly by spawning Settings at installer position
.DESCRIPTION
    Based on Set-NotificationAreaIconBehavior-Win11-2.ps1
    Sets Settings window registry position, launches Settings, runs UI automation.
.PARAMETER InstallerX
    Installer window X position (not used for Settings positioning when centering is enabled)
.PARAMETER InstallerY
    Installer window Y position (not used for Settings positioning when centering is enabled)
.PARAMETER InstallerWidth
    Installer window width (used as Settings window width)
.PARAMETER InstallerHeight
    Installer window height (used as Settings window height)
.PARAMETER AppName
    App name to toggle (e.g., "HebrewFixer1998.exe")
.PARAMETER LogPath
    Primary log path (installer-friendly). When -Debug is enabled, an additional log is written to the Tests directory.
.PARAMETER Debug
    When enabled (default), also write a copy of the log to the Tests directory (next to this script).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [int]$InstallerX,
    
    [Parameter(Mandatory)]
    [int]$InstallerY,
    
    [Parameter(Mandatory)]
    [int]$InstallerWidth,
    
    [Parameter(Mandatory)]
    [int]$InstallerHeight,
    
    [Parameter(Mandatory)]
    [string]$AppName,
    
    [switch]$HideIcon = $false,

    # If set, sanitize existing NotifyIconSettings promoted values for this app before UI automation.
    [switch]$CleanupRegistry = $false,

    # Optional extra debug logging.
    [switch]$DebugMode = $false,
    
    [string]$LogPath = "C:\Users\FireSongz\AppData\Roaming\HebrewFixer\InstallLogs\notification_area_icons_installer.log"
)

$ErrorActionPreference = 'Continue'

$DebugLogPath = $null
if ($DebugMode) {
    $DebugLogPath = Join-Path -Path $PSScriptRoot -ChildPath 'notification_area_icons_installer.debug.log'
}

# Logging function - COPIED FROM Win11-2
function Write-LogLine {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG','OK','STEP')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = "[$timestamp][$Level] $Message"
    
    # Write to console with color
    $color = switch ($Level) {
        'ERROR' { 'Red' }
        'WARN'  { 'Yellow' }
        'OK'    { 'Green' }
        'STEP'  { 'Cyan' }
        'DEBUG' { 'Gray' }
        default { 'White' }
    }
    Write-Host $line -ForegroundColor $color
    
    # Append to log file(s)
    foreach ($path in @($LogPath, $DebugLogPath) | Where-Object { $_ }) {
        try {
            $line | Out-File -FilePath $path -Append -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-Warning "Failed to write to log '$path': $_"
        }
    }
}

function Ensure-LogDirectory([string]$path) {
    if (-not $path) { return }
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Ensure log directories exist
Ensure-LogDirectory $LogPath
Ensure-LogDirectory $DebugLogPath

function Sanitize-NotifyIconSettings {
    param(
        [Parameter(Mandatory)][string]$AppName,
        [Parameter(Mandatory)][int]$DesiredPromoted
    )

    $base = 'HKCU:\\Control Panel\\NotifyIconSettings'
    if (-not (Test-Path $base)) {
        Write-LogLine "CleanupRegistry: NotifyIconSettings key not present: $base" -Level WARN
        return
    }

    $touched = 0
    $errors = 0
    $keys = Get-ChildItem $base -ErrorAction SilentlyContinue
    foreach ($k in $keys) {
        try {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop

            $strings = @()
            foreach ($prop in $p.PSObject.Properties) {
                if ($prop.Value -is [string] -and $prop.Value) {
                    $strings += $prop.Value
                }
            }
            $hit = $false
            foreach ($s in $strings) {
                if ($s -like "*$AppName*") { $hit = $true; break }
            }
            if (-not $hit) { continue }

            New-ItemProperty -LiteralPath $k.PSPath -Name 'IsPromoted' -Value $DesiredPromoted -PropertyType DWord -Force | Out-Null
            New-ItemProperty -LiteralPath $k.PSPath -Name 'IsUserPromoted' -Value $DesiredPromoted -PropertyType DWord -Force | Out-Null

            $touched++
        } catch {
            $errors++
        }
    }

    Write-LogLine "CleanupRegistry: touched=$touched errors=$errors desired=$DesiredPromoted app='$AppName'" -Level INFO
}

# Win32 helper (for post-launch exact positioning)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
"@

$SWP_NOZORDER   = 0x0004
$SWP_NOACTIVATE = 0x0010
$SWP_SHOWWINDOW = 0x0040

# Write separator and startup info
Write-LogLine "==============================================================================" -Level INFO
Write-LogLine "SCRIPT START | VERSION=INSTALLER_INVISIBLE_TESTS | Pid=$PID | User=$env:USERNAME | Script=$($MyInvocation.MyCommand.Name)" -Level INFO
Write-LogLine "Installer bounds: X=$InstallerX, Y=$InstallerY, W=$InstallerWidth, H=$InstallerHeight" -Level INFO
Write-LogLine "AppName: $AppName" -Level INFO
Write-LogLine "HideIcon: $HideIcon (will $(if ($HideIcon) {'HIDE'} else {'SHOW'}) icon)" -Level INFO
Write-LogLine "LogPath: $LogPath" -Level INFO
if ($DebugLogPath) { Write-LogLine "DebugLogPath: $DebugLogPath" -Level INFO }
Write-LogLine "==============================================================================" -Level INFO

try {
    # Step 1: Set Settings window position to match installer (size) and be centered like installer
    Write-LogLine "Setting Settings window registry position (centered; sized like installer)..."

    $posPath = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\windows.immersivecontrolpanel_cw5n1h2txyewy\ApplicationFrame\windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel"
    
    # Backup original position
    $backup = (Get-ItemProperty -Path $posPath -Name "Positions" -ErrorAction SilentlyContinue).Positions
    
    # Create WINDOWPLACEMENT with installer coordinates
    $matchedPos = [byte[]]::new(44)
    
    # Copy header from original or use defaults
    if ($backup) {
        [Array]::Copy($backup, 0, $matchedPos, 0, 28)
    } else {
        $matchedPos[0] = 44  # length
        $matchedPos[8] = 1   # showCmd = SW_SHOWNORMAL
    }

    # DEBUG MODE: Offset Settings 600px to the LEFT so we can see what it's doing
    # (normally it would overlay the installer invisibly)
    $left = $InstallerX
    $top  = $InstallerY
    $right = $left + $InstallerWidth
    $bottom = $InstallerY + $InstallerHeight

    # (debug offset removed)
# Write-LogLine "DEBUG: Settings offset 600px LEFT from installer for visibility" -Level WARN
    Write-LogLine "Desired Settings bounds: L=$left T=$top R=$right B=$bottom" -Level DEBUG

    [Array]::Copy([BitConverter]::GetBytes($left), 0, $matchedPos, 28, 4)
    [Array]::Copy([BitConverter]::GetBytes($top), 0, $matchedPos, 32, 4)
    [Array]::Copy([BitConverter]::GetBytes($right), 0, $matchedPos, 36, 4)
    [Array]::Copy([BitConverter]::GetBytes($bottom), 0, $matchedPos, 40, 4)
    
    Set-ItemProperty -Path $posPath -Name "Positions" -Value $matchedPos -Type Binary
    Write-LogLine "Settings position set (centered; sized like installer)" -Level OK
    
    # Kill any existing SystemSettings processes first (so we launch fresh)
    Write-LogLine "Killing any existing SystemSettings processes..."
    $existing = Get-Process -Name "SystemSettings" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-LogLine "Found $($existing.Count) existing SystemSettings process(es), killing..." -Level WARN
        $existing | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 250
    } else {
        Write-LogLine "No existing SystemSettings processes found (good)"
    }
    
    # Step 2: Launch Settings
    Write-LogLine "Launching Settings (will appear behind installer - invisible!)..." -Level STEP
    $proc = Start-Process "explorer.exe" -ArgumentList "ms-settings:taskbar" -PassThru
    Write-LogLine "Settings launched via explorer.exe (explorer PID: $($proc.Id))" -Level INFO
    
    # Step 3: Wait for Settings window
    Write-LogLine "Waiting for Settings window..." -Level STEP
    $settingsWindow = $null
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 250
        
        $allProcs = Get-Process -Name "SystemSettings" -ErrorAction SilentlyContinue
        if ($allProcs) {
            $settingsProc = $allProcs | Sort-Object Id -Descending | Select-Object -First 1
            if ($settingsProc.MainWindowHandle -ne 0) {
                $settingsWindow = $settingsProc.MainWindowHandle
                Write-LogLine "Settings window found (HWND: $settingsWindow, PID: $($settingsProc.Id), MainWindowTitle: '$($settingsProc.MainWindowTitle)')" -Level OK

                # Force exact overlay with installer bounds (eliminate any drift from registry interpretation).
                try {
                    [Win32]::SetWindowPos([IntPtr]$settingsWindow, [IntPtr]::Zero, $InstallerX, $InstallerY, $InstallerWidth, $InstallerHeight, ($SWP_NOZORDER -bor $SWP_NOACTIVATE -bor $SWP_SHOWWINDOW)) | Out-Null
                    Write-LogLine "Force-positioned Settings to installer bounds via SetWindowPos" -Level DEBUG
                } catch {
                    Write-LogLine "SetWindowPos force-position failed: $_" -Level WARN
                }

                break
            }
        }
    }
    
    if (-not $settingsWindow) {
        throw "Settings window not found after 10 seconds"
    }
    
    # Step 4: Wait for UI to fully load
    Start-Sleep -Milliseconds 250
    
    # Step 5: Perform UI Automation (Win11-2 proven logic)
    Write-LogLine "Starting UI Automation (proven Win11-2 logic)..." -Level STEP

    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes

    function Wait-ForSettingsWindow([int]$TimeoutSeconds = 20) {
        $timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
        $start = Get-Date
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty,
            "Settings"
        )

        while ((Get-Date) - $start -lt $timeout) {
            $win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
            if ($win) { return $win }
            Start-Sleep -Milliseconds 200
        }
        return $null
    }

    function Find-TextElementByRegex($root, [string]$regex) {
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Text
        )
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
        for ($i=0; $i -lt $all.Count; $i++) {
            $t = $all.Item($i)
            $n = ''
            try { $n = $t.Current.Name } catch {}
            if ($n -and ($n -match $regex)) { return $t }
        }
        return $null
    }

    function Find-AncestorWithExpandCollapse($el) {
        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        $cur = $el
        for ($i=0; $i -lt 15 -and $cur -ne $null; $i++) {
            try { $p = $walker.GetParent($cur) } catch { $p = $null }
            if (-not $p) { break }
            $cur = $p
            try {
                $cur.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern) | Out-Null
                return $cur
            } catch {}
        }
        return $null
    }

    function Expand-SectionByLabel($window, [string]$labelRegex) {
        Write-LogLine "Locating section label /$labelRegex/" -Level STEP
        $label = Find-TextElementByRegex -root $window -regex $labelRegex
        if (-not $label) { return $false }

        # 1) Try ExpandCollapsePattern on an ancestor
        $section = Find-AncestorWithExpandCollapse -el $label
        if ($section) {
            try {
                $ec = $section.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
                $ec.Expand()
                Write-LogLine "Section expanded (ExpandCollapsePattern)" -Level OK
                return $true
            } catch {
                Write-LogLine "ExpandCollapse expand failed; trying expander button fallback" -Level WARN
            }
        }

        # 2) Fallback: find expander button in nearest group
        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        $group = $label
        for ($depth=0; $depth -lt 12 -and $group -ne $null; $depth++) {
            try { $parent = $walker.GetParent($group) } catch { $parent = $null }
            if (-not $parent) { break }
            $group = $parent
            try {
                if ($group.Current.ControlType -eq [System.Windows.Automation.ControlType]::Group) { break }
            } catch {}
        }
        if (-not $group) { return $false }

        $btnCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button
        )
        $buttons = $group.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
        for ($i=0; $i -lt $buttons.Count; $i++) {
            $b = $buttons.Item($i)
            $bn=''; $bc=''
            try { $bn = $b.Current.Name } catch {}
            try { $bc = $b.Current.ClassName } catch {}
            if (($bc -match 'ExpanderToggleButton') -or ($bn -match 'Show\s+more\s+settings')) {
                try {
                    $ecp = $b.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
                    $ecp.Expand()
                    Write-LogLine "Activated expander via ExpandCollapsePattern.Expand()" -Level OK
                    return $true
                } catch {
                    Write-LogLine "Expander activation failed: $_" -Level WARN
                }
            }
        }

        return $false
    }

    function Find-AppGroupByRegex($window, [string]$regex) {
        $grpCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Group
        )
        $groups = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $grpCond)
        Write-LogLine "Groups found: $($groups.Count) (searching Name match /$regex/)" -Level DEBUG
        for ($i=0; $i -lt $groups.Count; $i++) {
            $g = $groups.Item($i)
            $gn=''
            try { $gn = $g.Current.Name } catch {}
            if ($gn -and ($gn -match $regex)) { return $g }
        }
        return $null
    }

    function Find-ToggleInAppGroup($appGroup) {
        $btnCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button
        )
        $buttons = $appGroup.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
        for ($i=0; $i -lt $buttons.Count; $i++) {
            $b = $buttons.Item($i)
            $cls=''; $aid=''
            try { $cls = $b.Current.ClassName } catch {}
            try { $aid = $b.Current.AutomationId } catch {}
            if ($cls -match 'ToggleSwitch' -or $aid -match '_ToggleSwitch$') {
                try {
                    $tp = $b.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
                    if ($tp) { return $b }
                } catch {}
            }
        }
        return $null
    }

    function Set-ToggleState($toggleButton, [bool]$DesiredOn) {
        $desired = if ($DesiredOn) { [System.Windows.Automation.ToggleState]::On } else { [System.Windows.Automation.ToggleState]::Off }
        $tp = $toggleButton.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        $cur = $tp.Current.ToggleState
        Write-LogLine "Toggle current state=$cur, desired=$desired" -Level INFO
        if ($cur -ne $desired) {
            $tp.Toggle()
            Write-LogLine "Toggled" -Level OK
        } else {
            Write-LogLine "Already in desired state" -Level OK
        }
    }

    $settingsElement = Wait-ForSettingsWindow -TimeoutSeconds 30
    if (-not $settingsElement) { throw "Settings window not found via UI Automation" }
    Write-LogLine "Found Settings window via UI Automation" -Level OK

    $expanded = Expand-SectionByLabel -window $settingsElement -labelRegex 'Other\s+system\s+tray\s+icons'
    if (-not $expanded) { Write-LogLine "Could not expand section (may already be expanded)" -Level WARN }

    Write-LogLine "Waiting briefly for UI to render all app groups..." -Level DEBUG
    Start-Sleep -Milliseconds 250

    $appRegex = [regex]::Escape($AppName)
    $appGroup = Find-AppGroupByRegex -window $settingsElement -regex $appRegex
    if (-not $appGroup) { throw "Could not find app group for: $AppName" }
    Write-LogLine "Matched app group: $($appGroup.Current.Name)" -Level OK

    $appToggle = Find-ToggleInAppGroup -appGroup $appGroup
    if (-not $appToggle) { throw "Could not find toggle switch within app group" }
    Write-LogLine "Matched toggle: $($appToggle.Current.Name)" -Level OK

    $desiredOn = (-not $HideIcon)
    Set-ToggleState -toggleButton $appToggle -DesiredOn $desiredOn

    Write-LogLine "UI Automation completed successfully!" -Level OK
    
    # Step 6: Close Settings
    Write-LogLine "Closing Settings..." -Level STEP
    Get-Process -Name "SystemSettings" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    
    # Step 7: Restore original position
    if ($backup) {
        Write-LogLine "Restoring original Settings position..." -Level STEP
        Set-ItemProperty -Path $posPath -Name "Positions" -Value $backup -Type Binary
    }
    
    Write-LogLine "==============================================================" -Level INFO
    Write-LogLine "SUCCESS: Tray icon promoted invisibly!" -Level OK
    Write-LogLine "==============================================================" -Level INFO
    
    exit 0
    
} catch {
    Write-LogLine "ERROR: $($_.Exception.Message)" -Level ERROR
    Write-LogLine "StackTrace: $($_.ScriptStackTrace)" -Level ERROR
    
    # Cleanup
    try {
        Get-Process -Name "SystemSettings" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if ($backup) {
            Set-ItemProperty -Path $posPath -Name "Positions" -Value $backup -Type Binary -ErrorAction SilentlyContinue
        }
    } catch { }
    
    exit 1
}
