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
    # Pattern used to match the row (usually includes app name/exe). By default treated as a regex.
    [Parameter(Mandatory=$true)]
    [string]$Match,

    # If set, $Match is treated as a literal substring (it will be regex-escaped internally).
    [switch]$LiteralMatch,

    [Parameter(Mandatory=$true)]
    [ValidateSet('ShowIconAndNotifications','HideIconAndNotifications','OnlyShowNotifications')]
    [string]$Behavior,

    # Optional: also match the window title; useful if localized OS.
    [string]$WindowNameRegex = 'Notification Area Icons',

    # Dump everything we can see in the window UIA tree when matching fails.
    [switch]$DumpUiOnFailure = $true,

    # Safety cap to avoid infinite/huge dumps.
    [int]$MaxDumpElements = 2000,

    [int]$TimeoutSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Mandatory inter-operation delay (seconds) to accommodate the complex Explorer/D3D-hosted UI.
# Per project requirement, this delay is applied between each major automation step.
$Global:OperationDelaySeconds = 5

# Journal-style log file (mirrors the related AHK script naming convention per project request).
# NOTE: This is a *single* rolling log file; each line is timestamped.
$Global:LogPath = Join-Path -Path $PSScriptRoot -ChildPath 'notification_area_icons_transparent.log'

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','STEP','OK','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )

    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $line = "[$ts][$Level] $Message"

    # Write to console (verbose-friendly) + append to log file
    Write-Verbose $line
    Add-Content -LiteralPath $Global:LogPath -Value $line -Encoding UTF8
}

function Step-Delay([string]$StepName) {
    Write-Log -Level 'DEBUG' -Message ("Delay {0}s (mandatory) after step: {1}" -f $Global:OperationDelaySeconds, $StepName)
    Start-Sleep -Seconds $Global:OperationDelaySeconds
}

function Add-UIAutomationAssemblies {
    # These are part of .NET on Windows.
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
}

function Start-NotificationAreaIcons {
    # Proven invocation method (works even when other control panel launchers are flaky):
    # - explorer shell:::{05d7b0f4-2121-4eff-bf6b-ed3f69b894d9}
    # - or Shell.Application.Open("shell:::{...}")
    $guidPath = 'shell:::{05d7b0f4-2121-4eff-bf6b-ed3f69b894d9}'

    # Prefer explorer.exe for parity with the known-working AHK tests.
    Start-Process -FilePath 'explorer.exe' -ArgumentList $guidPath
}

function Wait-ForWindow([string]$nameRegex, [TimeSpan]$timeout) {
    Write-Log -Level 'DEBUG' -Message ("Wait-ForWindow start | regex=/{0}/ | timeoutMs={1}" -f $nameRegex, [int]$timeout.TotalMilliseconds)
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

    Write-Log -Level 'ERROR' -Message ("Wait-ForWindow timeout | regex=/{0}/" -f $nameRegex)
    throw "Timed out waiting for window name matching regex: $nameRegex"
}

function Find-FirstDescendant($root, [System.Windows.Automation.Condition]$condition) {
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

function Find-ListItemByRegex($window, [string]$itemRegex) {
    Write-Log -Level 'DEBUG' -Message ("Find-ListItemByRegex | regex=/{0}/" -f $itemRegex)
    # The main table is typically a List control.
    $listCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::List
    )
    $list = Find-FirstDescendant $window $listCond
    if (-not $list) {
        Write-Log -Level 'ERROR' -Message 'Could not find List control in window (UI layout changed?)'
        throw 'Could not find List control in window (UI layout changed?)'
    }

    Write-Log -Level 'DEBUG' -Message ("List found | Name='{0}' | ClassName='{1}'" -f $list.Current.Name, $list.Current.ClassName)

    # Many builds expose rows as DataItem, but some expose Custom or ListItem.
    $rowControlTypes = @(
        [System.Windows.Automation.ControlType]::DataItem,
        [System.Windows.Automation.ControlType]::ListItem,
        [System.Windows.Automation.ControlType]::Custom
    )

    $items = New-Object System.Collections.Generic.List[System.Windows.Automation.AutomationElement]
    foreach ($ct in $rowControlTypes) {
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            $ct
        )
        $found = $list.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
        Write-Log -Level 'DEBUG' -Message ("Row count ({0} children): {1}" -f $ct.ProgrammaticName, $found.Count)
        for ($i=0; $i -lt $found.Count; $i++) { [void]$items.Add($found.Item($i)) }
    }

    # De-dup by RuntimeId (best-effort)
    $unique = @{}
    foreach ($it in $items) {
        try {
            $rid = ($it.GetRuntimeId() -join '.')
        } catch {
            $rid = [System.Guid]::NewGuid().ToString()
        }
        if (-not $unique.ContainsKey($rid)) { $unique[$rid] = $it }
    }
    $items = @($unique.Values)
    Write-Log -Level 'DEBUG' -Message ("Total unique candidate rows: {0}" -f $items.Count)
    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]
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

        # Helpful dump: log a compact view of what each candidate row contains.
        if ($i -lt 200) {
            $snippet = @()
            foreach ($t in $texts) {
                $tn = $t.Current.Name
                if ($tn) { $snippet += $tn }
            }
            if ($name -or $snippet.Count -gt 0) {
                $sn = ($snippet | Select-Object -Unique | Select-Object -First 6) -join ' | '
                Write-Log -Level 'DEBUG' -Message ("Row[{0}] Candidate | ElementName='{1}' | Text='{2}'" -f $i, $name, $sn)
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
        Write-Log -Level 'ERROR' -Message 'Could not find ComboBox in the matched row. UI may have changed.'
        throw 'Could not find ComboBox in the matched row. UI may have changed.'
    }

    Write-Log -Level 'DEBUG' -Message ("ComboBox found | Name='{0}' | ClassName='{1}'" -f $combo.Current.Name, $combo.Current.ClassName)

    # Expand the combobox
    Write-Log -Level 'STEP' -Message 'Expanding ComboBox'
    $ecp = $combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    if (-not $ecp) {
        # Fallback: Invoke
        $inv = $combo.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        if ($inv) {
            $inv.Invoke()
            Write-Log -Level 'OK' -Message 'ComboBox invoked (InvokePattern)'
        } else {
            Write-Log -Level 'ERROR' -Message 'ComboBox is neither expandable nor invokable.'
            throw 'ComboBox is neither expandable nor invokable.'
        }
    } else {
        $ecp.Expand()
        Write-Log -Level 'OK' -Message 'ComboBox expanded (ExpandCollapsePattern)'
    }

    Step-Delay 'expand combobox'

    # The dropdown list items appear as ListItem controls.
    $listItemCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::ListItem
    )

    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $choices = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $listItemCond)
    Write-Log -Level 'DEBUG' -Message ("Dropdown ListItem count (global search): {0}" -f $choices.Count)

    $match = $null
    foreach ($c in $choices) {
        $n = $c.Current.Name
        if ($n -match $targetValueRegex) {
            $match = $c
            break
        }
    }

    if (-not $match) {
        Write-Log -Level 'ERROR' -Message ("Could not find dropdown choice matching: /{0}/" -f $targetValueRegex)
        # Collapse for cleanliness
        try {
            if ($ecp) { $ecp.Collapse() }
        } catch {}
        throw "Could not find dropdown choice matching: $targetValueRegex"
    }

    Write-Log -Level 'OK' -Message ("Matched dropdown choice | Name='{0}'" -f $match.Current.Name)

    $sel = $match.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    if (-not $sel) {
        Write-Log -Level 'ERROR' -Message 'Matched dropdown entry is not selectable.'
        throw 'Matched dropdown entry is not selectable.'
    }
    $sel.Select()
    Write-Log -Level 'OK' -Message 'Dropdown choice selected'

    # Collapse
    try {
        if ($ecp) { $ecp.Collapse() }
    } catch {}
}

function Dump-UiaTree {
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Automation.AutomationElement]$Root,
        [int]$Max = 2000
    )

    Write-Log -Level 'WARN' -Message ("UIA DUMP START | RootName='{0}' | RootClass='{1}' | Max={2}" -f $Root.Current.Name, $Root.Current.ClassName, $Max)

    $q = New-Object System.Collections.Generic.Queue[System.Windows.Automation.AutomationElement]
    $q.Enqueue($Root)
    $count = 0

    while ($q.Count -gt 0 -and $count -lt $Max) {
        $el = $q.Dequeue()
        $count++

        $ct = $el.Current.ControlType.ProgrammaticName
        $name = $el.Current.Name
        $cls = $el.Current.ClassName
        $aid = $el.Current.AutomationId
        $fw = $el.Current.FrameworkId

        # BoundingRectangle can throw in some cases; guard.
        $rect = ''
        try {
            $r = $el.Current.BoundingRectangle
            $rect = ("[{0},{1},{2},{3}]" -f [int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height)
        } catch { }

        Write-Log -Level 'WARN' -Message ("UIA | {0} | Name='{1}' | Class='{2}' | AId='{3}' | FW='{4}' | Rect={5}" -f $ct, $name, $cls, $aid, $fw, $rect)

        # Enqueue children
        $children = $el.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
        for ($i=0; $i -lt $children.Count; $i++) {
            $q.Enqueue($children.Item($i))
        }
    }

    Write-Log -Level 'WARN' -Message ("UIA DUMP END | ElementsLogged={0} | RemainingQueue={1}" -f $count, $q.Count)
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

# Start a new run marker in the rolling log.
Write-Log -Level 'INFO' -Message ('=' * 78)
$effectiveMatchRegex = if ($LiteralMatch) { [regex]::Escape($Match) } else { $Match }
Write-Log -Level 'INFO' -Message ("Run started | Script={0} | MatchInput='{1}' | LiteralMatch={2} | EffectiveRegex=/{3}/ | Behavior={4} | WindowNameRegex=/{5}/" -f $MyInvocation.MyCommand.Name, $Match, [bool]$LiteralMatch, $effectiveMatchRegex, $Behavior, $WindowNameRegex)

try {
    Write-Log -Level 'STEP' -Message "Launching Notification Area Icons dialog (shell GUID)"
    Start-NotificationAreaIcons
    Step-Delay 'launch dialog'

    $timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    Write-Log -Level 'STEP' -Message ("Waiting for window: /{0}/ (timeout={1}s)" -f $WindowNameRegex, $TimeoutSeconds)
    $win = Wait-ForWindow -nameRegex $WindowNameRegex -timeout $timeout
    Write-Log -Level 'OK' -Message ("Found window | Name='{0}'" -f $win.Current.Name)
    Step-Delay 'find window'

    Write-Log -Level 'STEP' -Message ("Searching for row matching regex: /{0}/" -f $effectiveMatchRegex)
    $row = Find-ListItemByRegex -window $win -itemRegex $effectiveMatchRegex
    if (-not $row) {
        Write-Log -Level 'ERROR' -Message ("No row matched regex: /{0}/" -f $effectiveMatchRegex)
        if ($DumpUiOnFailure) {
            Write-Log -Level 'WARN' -Message 'DumpUiOnFailure enabled; dumping UIA tree to log for inspection'
            Dump-UiaTree -Root $win -Max $MaxDumpElements
        }
        throw "Could not find any row matching regex: $Match"
    }
    Write-Log -Level 'OK' -Message ("Matched row | ElementName='{0}'" -f $row.Current.Name)
    Step-Delay 'find row'

    # Select the row (helps ensure the combobox is realized)
    Write-Log -Level 'STEP' -Message 'Selecting matched row'
    $selItem = $row.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    if ($selItem) {
        $selItem.Select()
        Write-Log -Level 'OK' -Message 'Row selected (SelectionItemPattern)'
    } else {
        Write-Log -Level 'WARN' -Message 'Row does not support SelectionItemPattern; continuing'
    }
    Step-Delay 'select row'

    if ($PSCmdlet.ShouldProcess("Row matching '$Match'", "Set behavior to $Behavior")) {
        Write-Log -Level 'STEP' -Message ("Setting dropdown behavior to '{0}' (regex=/{1}/)" -f $Behavior, $behaviorRegex)
        Set-ComboValueInRow -row $row -targetValueRegex $behaviorRegex
        Write-Log -Level 'OK' -Message 'Dropdown value set'
        Step-Delay 'set combobox value'
        Write-Host "OK: Set behavior for '$Match' to '$Behavior'"
        Write-Log -Level 'OK' -Message "Run completed successfully"
    } else {
        Write-Host "WhatIf: would set behavior for '$Match' to '$Behavior'"
        Write-Log -Level 'INFO' -Message "WhatIf: no changes applied"
    }
}
catch {
    $msg = $_.Exception.Message
    Write-Log -Level 'ERROR' -Message ("Exception: {0}" -f $msg)
    if ($_.ScriptStackTrace) {
        Write-Log -Level 'ERROR' -Message ("ScriptStackTrace: {0}" -f $_.ScriptStackTrace)
    }
    throw
}
finally {
    Write-Log -Level 'INFO' -Message ("Run finished")
}
