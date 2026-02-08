<#
HebrewFixer - Test Utility

Goal
----
Open the legacy "Notification Area Icons" control panel UI and set the behavior
for a specific app entry (e.g., HebrewFixer) using UI Automation.

Why this exists
--------------
Windows 11 does not provide a clean supported API to "pin" a tray icon. This test
script explores brute-force but deterministic UI automation (no coordinates, no
assumed ordering).

Usage examples
--------------
# Show icon + notifications for HebrewFixer
powershell -NoProfile -ExecutionPolicy Bypass -File .\Set-NotificationAreaIconBehavior.ps1 -Match 'HebrewFixer' -Behavior ShowIconAndNotifications -Verbose

# Dry run
powershell -NoProfile -File .\Set-NotificationAreaIconBehavior.ps1 -Match 'HebrewFixer' -Behavior ShowIconAndNotifications -WhatIf

Notes
-----
- Must be run in Windows PowerShell / pwsh on Windows (not inside WSL).
- Requires an interactive desktop session (UI Automation).
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    # Regex used to match the row (the visible name column usually contains app name)
    [Parameter(Mandatory=$true)]
    [string]$Match,

    [Parameter(Mandatory=$true)]
    [ValidateSet('ShowIconAndNotifications','HideIconAndNotifications','OnlyShowNotifications')]
    [string]$Behavior,

    # Optional: also match the window title; useful if localized OS.
    [string]$WindowNameRegex = 'Notification Area Icons',

    [int]$TimeoutSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-UIAutomationAssemblies {
    # These are part of .NET on Windows.
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
}

function Start-NotificationAreaIcons {
    # Legacy control panel page:
    # control.exe /name Microsoft.NotificationAreaIcons
    Start-Process -FilePath 'control.exe' -ArgumentList '/name Microsoft.NotificationAreaIcons'
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
            $n = $w.Current.Name
            if ($n -match $nameRegex) {
                return $w
            }
        }
        Start-Sleep -Milliseconds 200
    }

    throw "Timed out waiting for window name matching regex: $nameRegex"
}

function Find-FirstDescendant($root, [System.Windows.Automation.Condition]$condition) {
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

function Find-ListItemByRegex($window, [string]$itemRegex) {
    # The main table is typically a List control.
    $listCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::List
    )
    $list = Find-FirstDescendant $window $listCond
    if (-not $list) { throw 'Could not find List control in window (UI layout changed?)' }

    $itemCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::DataItem
    )

    $items = $list.FindAll([System.Windows.Automation.TreeScope]::Children, $itemCond)
    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items.Item($i)
        $name = $it.Current.Name
        if ($name -match $itemRegex) {
            return $it
        }

        # Some builds may put the app name in Text descendants rather than DataItem name.
        $textCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Text
        )
        $texts = $it.FindAll([System.Windows.Automation.TreeScope]::Descendants, $textCond)
        foreach ($t in $texts) {
            if ($t.Current.Name -match $itemRegex) {
                return $it
            }
        }
    }

    return $null
}

function Set-ComboValueInRow($row, [string]$targetValueRegex) {
    # The behavior column is typically a ComboBox inside the row.
    $comboCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::ComboBox
    )

    $combo = Find-FirstDescendant $row $comboCond
    if (-not $combo) {
        throw 'Could not find ComboBox in the matched row. UI may have changed.'
    }

    # Expand the combobox
    $ecp = $combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    if (-not $ecp) {
        # Fallback: Invoke
        $inv = $combo.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        if ($inv) { $inv.Invoke() } else { throw 'ComboBox is neither expandable nor invokable.' }
    } else {
        $ecp.Expand()
    }

    Start-Sleep -Milliseconds 200

    # The dropdown list items appear as ListItem controls.
    $listItemCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::ListItem
    )

    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $choices = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $listItemCond)

    $match = $null
    foreach ($c in $choices) {
        $n = $c.Current.Name
        if ($n -match $targetValueRegex) {
            $match = $c
            break
        }
    }

    if (-not $match) {
        # Collapse for cleanliness
        try {
            if ($ecp) { $ecp.Collapse() }
        } catch {}
        throw "Could not find dropdown choice matching: $targetValueRegex"
    }

    $sel = $match.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    if (-not $sel) {
        throw 'Matched dropdown entry is not selectable.'
    }
    $sel.Select()

    # Collapse
    try {
        if ($ecp) { $ecp.Collapse() }
    } catch {}
}

# Map abstract behavior to the visible UI strings.
# These exact strings can vary by Windows version and localization;
# we use regexes instead of exact string equality.
$behaviorRegex = switch ($Behavior) {
    'ShowIconAndNotifications' { 'Show\s+icon\s+and\s+notifications' }
    'HideIconAndNotifications' { 'Hide\s+icon\s+and\s+notifications' }
    'OnlyShowNotifications' { 'Only\s+show\s+notifications' }
}

Add-UIAutomationAssemblies

Write-Verbose "Launching Notification Area Icons control panel..."
Start-NotificationAreaIcons

$timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
$win = Wait-ForWindow -nameRegex $WindowNameRegex -timeout $timeout

Write-Verbose "Found window: '$($win.Current.Name)'"

$row = Find-ListItemByRegex -window $win -itemRegex $Match
if (-not $row) {
    throw "Could not find any row matching regex: $Match"
}

Write-Verbose "Matched row element name: '$($row.Current.Name)'"

# Select the row (helps ensure the combobox is realized)
$selItem = $row.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
if ($selItem) {
    $selItem.Select()
    Start-Sleep -Milliseconds 100
}

if ($PSCmdlet.ShouldProcess("Row matching '$Match'", "Set behavior to $Behavior")) {
    Set-ComboValueInRow -row $row -targetValueRegex $behaviorRegex
    Write-Host "OK: Set behavior for '$Match' to '$Behavior'"
} else {
    Write-Host "WhatIf: would set behavior for '$Match' to '$Behavior'"
}
