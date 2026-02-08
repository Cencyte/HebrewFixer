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

    # Console (color) + verbose + file
    $color = switch ($Level) {
        'ERROR' { 'Red' }
        'WARN'  { 'Yellow' }
        'OK'    { 'Green' }
        'STEP'  { 'Cyan' }
        'DEBUG' { 'DarkGray' }
        default { 'Gray' }
    }

    try {
        # Always emit a readable console line; Verbose is still useful when the caller uses -Verbose.
        Write-Host $line -ForegroundColor $color
    } catch {
        # If host doesn't support color, ignore.
    }

    Write-Verbose $line
    Add-Content -LiteralPath $Global:LogPath -Value $line -Encoding UTF8
}

function Get-ControlTypeName($el) {
    try {
        $ctObj = $el.Current.ControlType
        if (-not $ctObj) { return '<null>' }
        # Some objects may not expose ProgrammaticName in the way we expect.
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
    } catch {
        return ''
    }
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

function Get-RowTextSummary($row) {
    try {
        $textCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Text
        )
        $texts = $row.FindAll([System.Windows.Automation.TreeScope]::Descendants, $textCond)
        $snippet = @()
        for ($i=0; $i -lt $texts.Count; $i++) {
            $n = $texts.Item($i).Current.Name
            if ($n) { $snippet += $n }
        }
        return ($snippet | Select-Object -Unique | Select-Object -First 8) -join ' | '
    } catch {
        return ''
    }
}

function Find-RowWithFallback($window, [string]$itemRegex) {
    Write-Log -Level 'DEBUG' -Message ("Find-RowWithFallback | regex=/{0}/" -f $itemRegex)

    # Find any plausible container (List or ScrollViewer)
    $container = $null
    $listCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::List
    )
    $container = Find-FirstDescendant $window $listCond
    if ($container) {
        Write-Log -Level 'OK' -Message ("Container=List | Name='{0}' | Class='{1}'" -f $container.Current.Name, $container.Current.ClassName)
    } else {
        $paneCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Pane
        )
        # Prefer the scrollviewer pane if present
        $panes = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $paneCond)
        for ($i=0; $i -lt $panes.Count; $i++) {
            $p = $panes.Item($i)
            if ($p.Current.Name -match 'scrollviewer' -or $p.Current.ClassName -match 'ScrollViewer') {
                $container = $p
                break
            }
        }
        if ($container) {
            Write-Log -Level 'OK' -Message ("Container=Pane(scrollviewer-ish) | Name='{0}' | Class='{1}'" -f $container.Current.Name, $container.Current.ClassName)
        }
    }

    if (-not $container) {
        Write-Log -Level 'ERROR' -Message 'Could not find any List/ScrollViewer-like container'
        return $null
    }

    $modes = @(
        'ControlViewChildren',
        'ControlViewDescendants',
        'ContentViewWalker',
        'RawViewWalker',
        'RawTextNodes'
    )

    foreach ($mode in $modes) {
        Write-Log -Level 'STEP' -Message ("Enumeration mode: {0}" -f $mode)
        try {
            $candidates = @()

            switch ($mode) {
                'ControlViewChildren' {
                    $cts = @(
                        [System.Windows.Automation.ControlType]::DataItem,
                        [System.Windows.Automation.ControlType]::ListItem,
                        [System.Windows.Automation.ControlType]::Custom
                    )
                    foreach ($ct in $cts) {
                        $cond = New-Object System.Windows.Automation.PropertyCondition(
                            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                            $ct
                        )
                        $found = $container.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
                        $ctName = if ($ct.PSObject.Properties['ProgrammaticName']) { $ct.ProgrammaticName } else { $ct.ToString() }
                        Write-Log -Level 'DEBUG' -Message ("{0} children ({1}): {2}" -f $mode, $ctName, $found.Count)
                        for ($i=0; $i -lt $found.Count; $i++) { $candidates += $found.Item($i) }
                    }
                }
                'ControlViewDescendants' {
                    $cts = @(
                        [System.Windows.Automation.ControlType]::DataItem,
                        [System.Windows.Automation.ControlType]::ListItem,
                        [System.Windows.Automation.ControlType]::Custom
                    )
                    foreach ($ct in $cts) {
                        $cond = New-Object System.Windows.Automation.PropertyCondition(
                            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                            $ct
                        )
                        $found = $container.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
                        $ctName = if ($ct.PSObject.Properties['ProgrammaticName']) { $ct.ProgrammaticName } else { $ct.ToString() }
                        Write-Log -Level 'DEBUG' -Message ("{0} descendants ({1}): {2}" -f $mode, $ctName, $found.Count)
                        for ($i=0; $i -lt $found.Count; $i++) { $candidates += $found.Item($i) }
                    }
                }
                'ContentViewWalker' {
                    $walker = [System.Windows.Automation.TreeWalker]::ContentViewWalker
                    $child = $walker.GetFirstChild($container)
                    while ($child -ne $null) {
                        $candidates += $child
                        $child = $walker.GetNextSibling($child)
                    }
                    Write-Log -Level 'DEBUG' -Message ("{0} siblings: {1}" -f $mode, $candidates.Count)
                }
                'RawViewWalker' {
                    $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
                    $child = $walker.GetFirstChild($container)
                    while ($child -ne $null) {
                        $candidates += $child
                        $child = $walker.GetNextSibling($child)
                    }
                    Write-Log -Level 'DEBUG' -Message ("{0} siblings: {1}" -f $mode, $candidates.Count)
                }
                'RawTextNodes' {
                    # If we can't identify rows, at least extract text nodes + rectangles.
                    $textCond = New-Object System.Windows.Automation.PropertyCondition(
                        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                        [System.Windows.Automation.ControlType]::Text
                    )
                    $texts = $container.FindAll([System.Windows.Automation.TreeScope]::Descendants, $textCond)
                    Write-Log -Level 'DEBUG' -Message ("Text descendants: {0}" -f $texts.Count)
                    for ($i=0; $i -lt $texts.Count -and $i -lt 200; $i++) {
                        $t = $texts.Item($i)
                        $tn = $t.Current.Name
                        if ($tn) {
                            Write-Log -Level 'WARN' -Message ("TEXT[{0}] '{1}' Rect={2}" -f $i, $tn, (Get-RectString $t))
                        }
                    }
                    continue
                }
            }

            # De-dup by runtime id
            $uniq = @{}
            foreach ($c in $candidates) {
                $rid = ''
                try { $rid = ($c.GetRuntimeId() -join '.') } catch { $rid = [guid]::NewGuid().ToString() }
                if (-not $uniq.ContainsKey($rid)) { $uniq[$rid] = $c }
            }
            $candidates = @($uniq.Values)

            Write-Log -Level 'DEBUG' -Message ("{0} candidates after de-dup: {1}" -f $mode, $candidates.Count)

            # Log first N candidate summaries
            for ($i=0; $i -lt $candidates.Count -and $i -lt 60; $i++) {
                $c = $candidates[$i]
                $name = ''
                try { $name = $c.Current.Name } catch {}
                $ctn = Get-ControlTypeName $c
                $summary = Get-RowTextSummary $c
                if ($name -or $summary) {
                    Write-Log -Level 'DEBUG' -Message ("Cand[{0}] {1} Name='{2}' Text='{3}' Rect={4}" -f $i, $ctn, $name, $summary, (Get-RectString $c))
                }

                if ($name -match $itemRegex -or $summary -match $itemRegex) {
                    Write-Log -Level 'OK' -Message ("MATCH in mode {0} at candidate {1}" -f $mode, $i)
                    return $c
                }
            }
        } catch {
            Write-Log -Level 'WARN' -Message ("Mode {0} threw: {1}" -f $mode, $_.Exception.Message)
        }

        Step-Delay ("enumeration mode: $mode")
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

        $ct = Get-ControlTypeName $el
        $name = ''
        $cls = ''
        $aid = ''
        $fw = ''
        try { $name = $el.Current.Name } catch {}
        try { $cls  = $el.Current.ClassName } catch {}
        try { $aid  = $el.Current.AutomationId } catch {}
        try { $fw   = $el.Current.FrameworkId } catch {}
        $rect = Get-RectString $el

        Write-Log -Level 'WARN' -Message ("UIA | {0} | Name='{1}' | Class='{2}' | AId='{3}' | FW='{4}' | Rect={5}" -f $ct, $name, $cls, $aid, $fw, $rect)

        # Enqueue children
        try {
            $children = $el.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
            for ($i=0; $i -lt $children.Count; $i++) {
                $q.Enqueue($children.Item($i))
            }
        } catch {
            # ignore enumeration errors
        }
    }

    Write-Log -Level 'WARN' -Message ("UIA DUMP END | ElementsLogged={0} | RemainingQueue={1}" -f $count, $q.Count)
}

function Dump-UiaRawView {
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Automation.AutomationElement]$Root,
        [int]$Max = 2000
    )

    Write-Log -Level 'WARN' -Message ("UIA RAWVIEW DUMP START | RootName='{0}' | RootClass='{1}' | Max={2}" -f $Root.Current.Name, $Root.Current.ClassName, $Max)

    $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
    $q = New-Object System.Collections.Generic.Queue[System.Windows.Automation.AutomationElement]
    $q.Enqueue($Root)
    $count = 0

    while ($q.Count -gt 0 -and $count -lt $Max) {
        $el = $q.Dequeue();
        $count++

        $ct = Get-ControlTypeName $el
        $name = ''
        $cls = ''
        $aid = ''
        $fw = ''
        try { $name = $el.Current.Name } catch {}
        try { $cls  = $el.Current.ClassName } catch {}
        try { $aid  = $el.Current.AutomationId } catch {}
        try { $fw   = $el.Current.FrameworkId } catch {}
        $rect = Get-RectString $el

        Write-Log -Level 'WARN' -Message ("RAW | {0} | Name='{1}' | Class='{2}' | AId='{3}' | FW='{4}' | Rect={5}" -f $ct, $name, $cls, $aid, $fw, $rect)

        try {
            $child = $walker.GetFirstChild($el)
            while ($child -ne $null) {
                $q.Enqueue($child)
                $child = $walker.GetNextSibling($child)
            }
        } catch {
            # ignore
        }
    }

    Write-Log -Level 'WARN' -Message ("UIA RAWVIEW DUMP END | ElementsLogged={0} | RemainingQueue={1}" -f $count, $q.Count)
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
    $row = Find-RowWithFallback -window $win -itemRegex $effectiveMatchRegex
    if (-not $row) {
        Write-Log -Level 'ERROR' -Message ("No row matched regex: /{0}/" -f $effectiveMatchRegex)
        if ($DumpUiOnFailure) {
            Write-Log -Level 'WARN' -Message 'DumpUiOnFailure enabled; dumping UIA ControlView tree to log for inspection'
            Dump-UiaTree -Root $win -Max $MaxDumpElements
            Step-Delay 'after ControlView dump'
            Write-Log -Level 'WARN' -Message 'DumpUiOnFailure enabled; dumping UIA RawView tree to log for inspection'
            Dump-UiaRawView -Root $win -Max $MaxDumpElements
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
