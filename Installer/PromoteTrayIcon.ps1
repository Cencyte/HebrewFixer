param(
    [string]$ExePath,
    [switch]$DeleteOnly,
    [switch]$PromoteExisting
)

$notifyPath = 'HKCU:\Control Panel\NotifyIconSettings'

if ($DeleteOnly) {
    # Delete any existing HebrewFixer entries
    Get-ChildItem $notifyPath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($props.ExecutablePath -like '*HebrewFixer*') {
            Remove-Item $_.PSPath -Force -ErrorAction SilentlyContinue
        }
    }
    exit 0
}

if ($PromoteExisting) {
    # Find HebrewFixer entry and set IsPromoted = 1
    Get-ChildItem $notifyPath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($props.ExecutablePath -like '*HebrewFixer*') {
            Set-ItemProperty $_.PSPath -Name "IsPromoted" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        }
    }
    exit 0
}

exit 0
