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

function Get-EffectiveRegex([string]$pattern, [bool]$literal) {
    # NOTE: do not name the parameter $input (reserved automatic variable in PowerShell)
    if ($literal) { return [regex]::Escape($pattern) }
    return $pattern
}

function Get-ControlTypeName($el) {
    try {
        $ctObj = $el.Current.ControlType
        if (-not $ctObj) { return '<null>' }
        $p = $ctObj.PSObject.Properties['ProgrammaticName']
        if ($p) { return [string]$ctObj.ProgrammaticName }
        return [string]$ctObj.ToString()
    } catch {
        return '<ct-error>'
    }
}

function Get-RectString($el) {
    try {
        $r = $el.Current.BoundingRectangle
        return ("[{0},{1},{2},{3}]" -f [int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height)
    } catch { return '' }
}

function Dump-UiaTree {
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Automation.AutomationElement]$Root,
        [int]$Max = 1500
    )

    Write-Log -Level 'WARN' -Message ("UIA DUMP START | RootName='{0}' | RootClass='{1}' | Max={2}" -f $Root.Current.Name, $Root.Current.ClassName, $Max)

    $q = New-Object System.Collections.Generic.Queue[System.Windows.Automation.AutomationElement]
    $q.Enqueue($Root)
    $count = 0

    while ($q.Count -gt 0 -and $count -lt $Max) {
        $el = $q.Dequeue(); $count++

        $ct = Get-ControlTypeName $el
        $name = ''; $cls=''; $aid=''; $fw=''
        try { $name = $el.Current.Name } catch {}
        try { $cls  = $el.Current.ClassName } catch {}
        try { $aid  = $el.Current.AutomationId } catch {}
        try { $fw   = $el.Current.FrameworkId } catch {}
        $rect = Get-RectString $el

        if ($name -or $aid -or $ct -ne '<null>') {
            Write-Log -Level 'WARN' -Message ("UIA | {0} | Name='{1}' | Class='{2}' | AId='{3}' | FW='{4}' | Rect={5}" -f $ct, $name, $cls, $aid, $fw, $rect)
        }

        try {
            $children = $el.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
            for ($i=0; $i -lt $children.Count; $i++) { $q.Enqueue($children.Item($i)) }
        } catch {}
    }

    Write-Log -Level 'WARN' -Message ("UIA DUMP END | ElementsLogged={0} | RemainingQueue={1}" -f $count, $q.Count)
}

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
            Write-Log -Level 'OK' -Message ("Matched Text node | Name='{0}' | Rect={1}" -f $name, (Get-RectString $t))
            return $t
        }
    }

    return $null
}

function Find-AncestorWithExpandCollapse($el) {
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $cur = $el
    for ($depth = 0; $depth -lt 15 -and $cur -ne $null; $depth++) {
        try {
            $p = $walker.GetParent($cur)
        } catch {
            $p = $null
        }
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

    # Strategy 1: ExpandCollapsePattern on an ancestor
    Write-Log -Level 'STEP' -Message 'Searching for ancestor with ExpandCollapsePattern'
    $section = Find-AncestorWithExpandCollapse -el $label
    if ($section) {
        try {
            $ec = $section.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
            Write-Log -Level 'OK' -Message ("Section container found (ExpandCollapse) | Ct={0} | Name='{1}' | Rect={2}" -f (Get-ControlTypeName $section), $section.Current.Name, (Get-RectString $section))
            $ec.Expand()
            Write-Log -Level 'OK' -Message 'Section expanded (ExpandCollapsePattern)'
            return $section
        } catch {
            Write-Log -Level 'WARN' -Message ("ExpandCollapse expand failed; will try Invoke fallback: {0}" -f $_.Exception.Message)
        }
    } else {
        Write-Log -Level 'WARN' -Message 'No ExpandCollapse ancestor found for label (expected on some builds)'
    }

    # Strategy 2: Invokable expander button (per your UIA dump: Button Name='Show more settings', Class='ExpanderToggleButton')
    Write-Log -Level 'STEP' -Message 'Searching for invokable ExpanderToggleButton near label'

    # Find nearest ancestor group (often NamedContainerAutomationPeer) then search within it.
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $group = $label
    for ($depth=0; $depth -lt 12 -and $group -ne $null; $depth++) {
        try { $parent = $walker.GetParent($group) } catch { $parent = $null }
        if (-not $parent) { break }
        $group = $parent
        try {
            $ct = $group.Current.ControlType
            # Stop when we reach a named group container.
            if ($ct -eq [System.Windows.Automation.ControlType]::Group -and $group.Current.Name) { break }
        } catch {}
    }

    if ($group) {
        Write-Log -Level 'DEBUG' -Message ("Nearest group container | Ct={0} | Name='{1}' | Class='{2}'" -f (Get-ControlTypeName $group), $group.Current.Name, $group.Current.ClassName)

        $btnCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button
        )
        $buttons = $group.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
        for ($i=0; $i -lt $buttons.Count; $i++) {
            $b = $buttons.Item($i)
            $bn = ''
            $bc = ''
            try { $bn = $b.Current.Name } catch {}
            try { $bc = $b.Current.ClassName } catch {}

            if (($bc -match 'ExpanderToggleButton') -or ($bn -match 'Show\s+more\s+settings')) {
                Write-Log -Level 'OK' -Message ("Found expander button candidate | Name='{0}' | Class='{1}' | Rect={2}" -f $bn, $bc, (Get-RectString $b))
                try {
                    $inv = $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                    if ($inv) {
                        $inv.Invoke()
                        Write-Log -Level 'OK' -Message 'Invoked expander button (InvokePattern)'
                        return $group
                    }
                } catch {
                    Write-Log -Level 'WARN' -Message ("Expander candidate exists but InvokePattern failed: {0}" -f $_.Exception.Message)
                }
            }
        }
    }

    Write-Log -Level 'ERROR' -Message 'Unable to expand section via ExpandCollapse or Invoke expander button'
    return $null
}

function Find-ToggleNearText($window, [System.Windows.Automation.AutomationElement]$textEl) {
    # Win11 toggle switches often show up as ControlType.Button with TogglePattern.
    # Strategy: locate a nearby TogglePattern element within the same Y band.
    $targetRect = $textEl.Current.BoundingRectangle
    $yMid = $targetRect.Y + ($targetRect.Height / 2.0)

    $btnCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button
    )

    $buttons = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
    Write-Log -Level 'DEBUG' -Message ("Buttons found: {0} (searching for TogglePattern near matched text)" -f $buttons.Count)

    $best = $null
    $bestScore = [double]::PositiveInfinity

    for ($i=0; $i -lt $buttons.Count; $i++) {
        $b = $buttons.Item($i)
        # Must support TogglePattern
        try {
            $tp = $b.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
            if (-not $tp) { continue }
        } catch { continue }

        $r = $b.Current.BoundingRectangle
        if ($r.Width -le 0 -or $r.Height -le 0) { continue }

        $byMid = $r.Y + ($r.Height / 2.0)
        $dy = [math]::Abs($byMid - $yMid)

        # Require roughly same row band
        if ($dy -gt 25) { continue }

        # Prefer toggles to the right of the text
        $dx = $r.X - $targetRect.X
        if ($dx -lt 0) { $dx = 99999 }

        $score = ($dy * 10.0) + $dx
        if ($score -lt $bestScore) {
            $bestScore = $score
            $best = $b
        }
    }

    if ($best) {
        Write-Log -Level 'OK' -Message ("Matched toggle candidate | Name='{0}' | Rect={1}" -f $best.Current.Name, (Get-RectString $best))
    }

    return $best
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

Add-UIAutomationAssemblies

$effectiveMatchRegex = Get-EffectiveRegex -pattern $Match -literal ([bool]$LiteralMatch)

Write-Log -Level 'INFO' -Message ('=' * 78)
Write-Log -Level 'INFO' -Message ("Run started | Script={0} | MatchInput='{1}' | LiteralMatch={2} | EffectiveRegex=/{3}/ | DesiredState={4}" -f $MyInvocation.MyCommand.Name, $Match, [bool]$LiteralMatch, $effectiveMatchRegex, $DesiredState)
if (-not $effectiveMatchRegex -or $effectiveMatchRegex -eq '') {
    Write-Log -Level 'WARN' -Message 'EffectiveRegex is empty; match will fail. (Bug check)'
}

try {
    Write-Log -Level 'STEP' -Message 'Launching Win11 Taskbar settings (ms-settings:taskbar)'
    Start-Win11TrayIconsSettings
    Step-Delay 'launch settings'

    $timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    Write-Log -Level 'STEP' -Message ("Waiting for Settings window /{0}/" -f $SettingsWindowRegex)
    $win = Wait-ForWindow -nameRegex $SettingsWindowRegex -timeout $timeout
    Write-Log -Level 'OK' -Message ("Found window | Name='{0}'" -f $win.Current.Name)
    Step-Delay 'found settings window'

    # Phase 1: Expand the "Other system tray icons" section.
    $section = Expand-SectionByLabel -window $win -labelRegex 'Other\s+system\s+tray\s+icons'
    if (-not $section) {
        Write-Log -Level 'ERROR' -Message "Could not expand 'Other system tray icons' section via UIA."
        Write-Log -Level 'WARN' -Message 'Dumping UIA tree for debugging (early termination)'
        Dump-UiaTree -Root $win -Max 1200
        throw "EarlyTermination: could not expand Other system tray icons section"
    }
    Step-Delay 'expanded Other system tray icons'

    # Phase 2: Find the app entry text.
    Write-Log -Level 'STEP' -Message ("Searching for app entry text matching /{0}/" -f $effectiveMatchRegex)
    $textEl = Find-TextElementByRegex -root $win -regex $effectiveMatchRegex
    if (-not $textEl) {
        Write-Log -Level 'ERROR' -Message 'Could not find app entry text in UIA text nodes.'
        Write-Log -Level 'WARN' -Message 'Dumping UIA tree for debugging (early termination)'
        Dump-UiaTree -Root $win -Max 1400
        throw "EarlyTermination: could not find app entry text"
    }
    Step-Delay 'found app entry text'

    # Phase 3: Find toggle switch near that text and set it.
    $toggle = Find-ToggleNearText -window $win -textEl $textEl
    if (-not $toggle) {
        Write-Log -Level 'ERROR' -Message 'Could not find a TogglePattern button near the matched app text.'
        Dump-UiaTree -Root $win -Max 1600
        throw "EarlyTermination: could not locate toggle near text"
    }
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
    Write-Log -Level 'INFO' -Message 'Run finished'
}
