<#
HebrewFixer - Win11 Tray Icon Behavior Test Utility (v2)

v2 goals
--------
- Reuse the working v1 UIAutomation logic (expand "Other system tray icons" and toggle per-app switch).
- Make the Settings window non-intrusive:
  - Move it fully off-screen ASAP.
  - Optionally make it transparent (best-effort; may require Win32 window style changes).
  - Close Settings at the end.

Logging
-------
Writes a rolling timestamped journal:
  notification_area_icons_transparent-Win11-2.log

Run from Windows PowerShell (interactive desktop).
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$Match,

    [switch]$LiteralMatch,

    [Parameter(Mandatory=$true)]
    [ValidateSet('On','Off')]
    [string]$DesiredState,

    [string]$SettingsWindowRegex = 'Settings',

    # Window hiding behavior
    [switch]$MoveOffScreen = $false,

    # Best-effort transparency (may fail harmlessly)
    [switch]$Transparent = $false,

    # 0..255 alpha when -Transparent; 0=fully invisible, 255=opaque
    [ValidateRange(0,255)]
    [int]$Alpha = 1,

    # Close Settings at end
    [switch]$CloseWindow = $true,

    [int]$TimeoutSeconds = 40
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Global:OperationDelaySeconds = 5
$Global:LogPath = Join-Path -Path $PSScriptRoot -ChildPath 'notification_area_icons_transparent-Win11-2.log'

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
    try { Add-Type -AssemblyName UIAutomationClientsideProviders } catch {}
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
    Start-Process 'explorer.exe' 'ms-settings:taskbar'
}

function Get-EffectiveRegex([string]$pattern, [bool]$literal) {
    if ($literal) { return [regex]::Escape($pattern) }
    return $pattern
}

# Win32 window manipulation helpers
# Use -TypeDefinition (full C# type) and guard against redefinition.
if (-not ('Win32.NativeMethods' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Win32 {
  public static class NativeMethods {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll", SetLastError=true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError=true)]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_LAYERED = 0x00080000;

    public const uint LWA_ALPHA = 0x00000002;

    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_NOZORDER = 0x0004;
    public const uint SWP_NOACTIVATE = 0x0010;

    public const uint WM_CLOSE = 0x0010;
  }
}
'@
}

function Try-GetNativeHwnd([System.Windows.Automation.AutomationElement]$win) {
    try {
        return [IntPtr]$win.Current.NativeWindowHandle
    } catch {
        return [IntPtr]::Zero
    }
}

function Move-WindowOffScreen([IntPtr]$hWnd) {
    # Move far left and up; no resize, no activate.
    [void][Win32.NativeMethods]::SetWindowPos($hWnd, [IntPtr]::Zero, -32000, -32000, 0, 0, [Win32.NativeMethods]::SWP_NOSIZE -bor [Win32.NativeMethods]::SWP_NOZORDER -bor [Win32.NativeMethods]::SWP_NOACTIVATE)
}

function Set-WindowAlpha([IntPtr]$hWnd, [byte]$alpha) {
    $ex = [Win32.NativeMethods]::GetWindowLong($hWnd, [Win32.NativeMethods]::GWL_EXSTYLE)
    [void][Win32.NativeMethods]::SetWindowLong($hWnd, [Win32.NativeMethods]::GWL_EXSTYLE, ($ex -bor [Win32.NativeMethods]::WS_EX_LAYERED))
    [void][Win32.NativeMethods]::SetLayeredWindowAttributes($hWnd, 0, $alpha, [Win32.NativeMethods]::LWA_ALPHA)
}

# --- UIAutomation logic (copied from v1 with minimal edits) ---

function Find-TextElementByRegex($root, [string]$regex) {
    $textCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Text
    )

    $texts = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $textCond)
    Write-Log -Level 'DEBUG' -Message ("Text nodes found: {0} | searching /{1}/" -f $texts.Count, $regex)

    for ($i=0; $i -lt $texts.Count; $i++) {
        $t = $texts.Item($i)
        $name = ''
        try { $name = $t.Current.Name } catch {}
        if ($name -and $name -match $regex) {
            Write-Log -Level 'OK' -Message ("Matched Text node | Name='{0}'" -f $name)
            return $t
        }
    }

    return $null
}

function Find-AncestorWithExpandCollapse($el) {
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $cur = $el
    for ($depth = 0; $depth -lt 15 -and $cur -ne $null; $depth++) {
        try { $p = $walker.GetParent($cur) } catch { $p = $null }
        if (-not $p) { break }
        try {
            $pat = $p.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
            if ($pat) { return $p }
        } catch {}
        $cur = $p
    }
    return $null
}

function Expand-SectionByLabel($window, [string]$labelRegex) {
    Write-Log -Level 'STEP' -Message ("Locating section label /{0}/" -f $labelRegex)
    $label = Find-TextElementByRegex -root $window -regex $labelRegex
    if (-not $label) { return $null }

    Write-Log -Level 'STEP' -Message 'Searching for ancestor with ExpandCollapsePattern'
    $section = Find-AncestorWithExpandCollapse -el $label
    if ($section) {
        try {
            $ec = $section.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
            $ec.Expand()
            Write-Log -Level 'OK' -Message 'Section expanded (ExpandCollapsePattern)'
            return $section
        } catch {
            Write-Log -Level 'WARN' -Message ("ExpandCollapse expand failed; will try expander button fallback: {0}" -f $_.Exception.Message)
        }
    }

    # Expander button inside nearest group
    Write-Log -Level 'STEP' -Message 'Searching for ExpanderToggleButton within nearest group'
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $group = $label
    for ($depth=0; $depth -lt 12 -and $group -ne $null; $depth++) {
        try { $parent = $walker.GetParent($group) } catch { $parent = $null }
        if (-not $parent) { break }
        $group = $parent
        try {
            if ($group.Current.ControlType -eq [System.Windows.Automation.ControlType]::Group -and $group.Current.Name) { break }
        } catch {}
    }

    if (-not $group) { return $null }

    $btnCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button
    )
    $buttons = $group.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)

    for ($i=0; $i -lt $buttons.Count; $i++) {
        $b = $buttons.Item($i)
        $bn = ''; $bc=''
        try { $bn = $b.Current.Name } catch {}
        try { $bc = $b.Current.ClassName } catch {}

        if (($bc -match 'ExpanderToggleButton') -or ($bn -match 'Show\s+more\s+settings')) {
            Write-Log -Level 'OK' -Message ("Found expander button candidate | Name='{0}' | Class='{1}'" -f $bn, $bc)
            try {
                $ecp = $b.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
                if ($ecp) {
                    $ecp.Expand()
                    Write-Log -Level 'OK' -Message 'Activated expander via ExpandCollapsePattern.Expand()'
                    return $group
                }
            } catch {
                Write-Log -Level 'WARN' -Message ("Expander activation failed: {0}" -f $_.Exception.Message)
            }
        }
    }

    return $null
}

function Find-AppGroupByRegex($window, [string]$regex) {
    $grpCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Group
    )

    $groups = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $grpCond)
    Write-Log -Level 'DEBUG' -Message ("Groups found: {0} (searching Name match /{1}/)" -f $groups.Count, $regex)

    for ($i=0; $i -lt $groups.Count; $i++) {
        $g = $groups.Item($i)
        $gn = ''
        try { $gn = $g.Current.Name } catch {}
        if ($gn -and ($gn -match $regex)) {
            Write-Log -Level 'OK' -Message ("Matched app group | Name='{0}' | AId='{1}'" -f $gn, $g.Current.AutomationId)
            return $g
        }
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
                if ($tp) {
                    Write-Log -Level 'OK' -Message ("Matched toggle in group | Name='{0}' | AId='{1}'" -f $b.Current.Name, $aid)
                    return $b
                }
            } catch {}
        }
    }

    return $null
}

function Set-ToggleState($toggleButton, [string]$desiredOnOff) {
    $desired = if ($desiredOnOff -eq 'On') { [System.Windows.Automation.ToggleState]::On } else { [System.Windows.Automation.ToggleState]::Off }
    $tp = $toggleButton.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
    $cur = $tp.Current.ToggleState
    Write-Log -Level 'INFO' -Message ("Toggle current state={0}, desired={1}" -f $cur, $desired)

    if ($cur -ne $desired) {
        $tp.Toggle()
        Write-Log -Level 'OK' -Message 'Toggled'
    } else {
        Write-Log -Level 'OK' -Message 'Already in desired state'
    }
}

function Close-SettingsWindow([IntPtr]$hWnd) {
    [void][Win32.NativeMethods]::SendMessage($hWnd, [Win32.NativeMethods]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
}

# --- main ---

Add-UIAutomationAssemblies
$effectiveMatchRegex = Get-EffectiveRegex -pattern $Match -literal ([bool]$LiteralMatch)

Write-Log -Level 'INFO' -Message ('=' * 78)
Write-Log -Level 'INFO' -Message ("Run started | Script={0} | MatchInput='{1}' | LiteralMatch={2} | EffectiveRegex=/{3}/ | DesiredState={4} | MoveOffScreen={5} | Transparent={6} Alpha={7} CloseWindow={8}" -f $MyInvocation.MyCommand.Name, $Match, [bool]$LiteralMatch, $effectiveMatchRegex, $DesiredState, [bool]$MoveOffScreen, [bool]$Transparent, $Alpha, [bool]$CloseWindow)

try {
    Write-Log -Level 'STEP' -Message 'Launching Win11 Taskbar settings (ms-settings:taskbar)'
    Start-Win11TrayIconsSettings
    Step-Delay 'launch settings'

    $timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    Write-Log -Level 'STEP' -Message ("Waiting for Settings window /{0}/" -f $SettingsWindowRegex)
    $win = Wait-ForWindow -nameRegex $SettingsWindowRegex -timeout $timeout
    Write-Log -Level 'OK' -Message ("Found window | Name='{0}'" -f $win.Current.Name)

    $hWnd = Try-GetNativeHwnd $win
    Write-Log -Level 'INFO' -Message ("NativeWindowHandle={0}" -f $hWnd)

    if ($hWnd -ne [IntPtr]::Zero) {
        if ($MoveOffScreen) {
            Move-WindowOffScreen $hWnd
            Write-Log -Level 'OK' -Message 'Moved Settings window off-screen'
            Step-Delay 'move off-screen'
        }
        if ($Transparent) {
            try {
                Set-WindowAlpha -hWnd $hWnd -alpha ([byte]$Alpha)
                Write-Log -Level 'OK' -Message ("Applied transparency alpha={0}" -f $Alpha)
            } catch {
                Write-Log -Level 'WARN' -Message ("Transparency failed (continuing): {0}" -f $_.Exception.Message)
            }
            Step-Delay 'set transparency'
        }
    } else {
        Write-Log -Level 'WARN' -Message 'No native HWND; cannot move/transparentize Settings window'
    }

    # Expand "Other system tray icons" and toggle
    $section = Expand-SectionByLabel -window $win -labelRegex 'Other\s+system\s+tray\s+icons'
    if (-not $section) { throw "Could not expand Other system tray icons" }
    Step-Delay 'expanded Other system tray icons'

    $appGroup = Find-AppGroupByRegex -window $win -regex $effectiveMatchRegex
    if (-not $appGroup) { throw "Could not find app group matching /$effectiveMatchRegex/" }
    Step-Delay 'found app group'

    $toggle = Find-ToggleInAppGroup -appGroup $appGroup
    if (-not $toggle) { throw 'Could not find toggle within app group' }
    Step-Delay 'found toggle'

    if ($PSCmdlet.ShouldProcess("Toggle for '$Match'", "Set to $DesiredState")) {
        Set-ToggleState -toggleButton $toggle -desiredOnOff $DesiredState
        Step-Delay 'set toggle state'
        Write-Log -Level 'OK' -Message 'Completed successfully'
    } else {
        Write-Log -Level 'INFO' -Message 'WhatIf: no changes applied'
    }
}
catch {
    Write-Log -Level 'ERROR' -Message ("Exception: {0}" -f $_.Exception.Message)
    if ($_.ScriptStackTrace) { Write-Log -Level 'ERROR' -Message ("ScriptStackTrace: {0}" -f $_.ScriptStackTrace) }
    throw
}
finally {
    try {
        if ($CloseWindow -and $hWnd -and $hWnd -ne [IntPtr]::Zero) {
            Close-SettingsWindow $hWnd
            Write-Log -Level 'OK' -Message 'Sent WM_CLOSE to Settings window'
        }
    } catch {
        Write-Log -Level 'WARN' -Message ("Close window failed: {0}" -f $_.Exception.Message)
    }

    Write-Log -Level 'INFO' -Message 'Run finished'
}
