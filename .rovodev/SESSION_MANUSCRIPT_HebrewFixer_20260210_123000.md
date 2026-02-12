# SESSION MANUSCRIPT — HebrewFixer — 2026-02-10 (Tue)

**HebrewFixer Manuscripts Series:** Volume 5/5  
**Document type:** Session log (Win11 tray icon pinning + installer/uninstaller hardening)

## Abstract
This volume captures the final-mile work to make HebrewFixer’s Windows 11 tray icon “always show” behavior deterministic, with **zero GUI** during install/uninstall. We pivoted from legacy Win10 control panel GUI automation to Win11 registry-backed state (`HKCU:\Control Panel\NotifyIconSettings`) and then hardened the Inno Setup installer/uninstaller to correctly apply/revert the setting only when selected, clean up install directories, and prove execution via persistent debug logging.

## TL;DR
- Win11 “Other system tray icons” can be forced via registry: `HKCU:\Control Panel\NotifyIconSettings\{GUID}\IsPromoted`.
- Built `Set-NotificationAreaIconBehavior-Win11-3.ps1` to set `IsPromoted` for matching entries.
- Installer got hardened to:
  - gate tray promotion behind a checkbox
  - revert promotion on uninstall
  - delete `HKCU\Software\HebrewFixer` marker key on uninstall
  - delete `{app}` even if not empty
  - `taskkill HebrewFixer1998.exe` before uninstall actions
- Major debugging wins:
  - fixed PowerShell parameter binding issues (`FailIfMissing` int 0/1)
  - ensured installer always uses the correct helper script
  - fixed log file lock contention between Inno and PowerShell

## Summary
### Goals
1) No Settings UI / no GUI automation during install.
2) User checkbox determines whether tray icon is always shown.
3) Uninstall leaves no residue (folder removed; HKCU marker removed; promotion reverted).
4) Deterministic proof via logging.

### Key deliverables
- `Tests/Win11/Set-NotificationAreaIconBehavior-Win11-3.ps1` (registry-only tray pinning)
- `Installer/HebrewFixer_Setup.iss` updates (gating, revert on uninstall, cleanup, logging)
- Persistent installer log:
  - `%APPDATA%\HebrewFixer\InstallLogs\installer_debug.log`

## Main body
### 1) Win10 legacy UI was the wrong target
We discovered the legacy “Notification Area Icons” shell GUID is Win10-oriented and unreliable for Win11 Taskbar. Win11 uses a different Settings UI and, crucially, stores tray visibility state in per-user registry entries.

### 2) Win11 registry method (zero GUI)
The state lives in:
- `HKCU:\Control Panel\NotifyIconSettings\{GUID}`

The key value:
- `IsPromoted` (DWORD)

The helper script searches for matching entries and sets `IsPromoted` to 1 (show) or 0 (hide).

### 3) Installer/uninstaller hardening
We iteratively fixed state leakage and brittleness:
- uninstall not deleting install folder → fixed with `[UninstallDelete] Type: filesandordirs`
- tray pin persisted across uninstall → added revert path (registry-based)
- checkbox not honored → ensured logic gated by `WizardIsTaskSelected('trayvisible')`
- older uninstallers embedded older args → added persistent logging and corrected helper selection
- file lock contention → separated PowerShell log target and appended into main log

### 4) Persistent debug logging (prove, don’t guess)
We created a black-box debug log written by Inno Setup and augmented by PowerShell sentinels so failures are diagnosable:
- exact PS command lines
- Exec() return codes
- script start/end markers

## Key files
- `Installer/HebrewFixer_Setup.iss`
- `Tests/Win11/Set-NotificationAreaIconBehavior-Win11-3.ps1`
- Logs: `%APPDATA%\HebrewFixer\InstallLogs\installer_debug.log`

## Recent commits (selected)
(From `git log` on installer + helper)
- `214bce2` installer: taskkill HebrewFixer before uninstall actions to avoid locked install dir
- `73f40e6` fix(win11-3): make FailIfMissing int 0/1 for reliable CLI binding
- `26e95ae` fix(installer): deploy dedicated helper filename and log script version banner
- `7a3e667` debug(installer): persistent log + PS sentinel to prove tray setting apply/revert
- `1f9e583` installer: register tray entry then promote via NotifyIconSettings IsPromoted (later revised)

## Conclusion
We reached a working, deterministic Win11 tray icon pinning flow aligned with installer UX requirements: **no GUI**, checkbox-controlled apply/revert, and robust diagnostics. Remaining polish is mostly about simplifying the accumulated debug pathways, ensuring the shipping installer uses the minimal necessary logging, and final packaging/exe signing considerations.

## Index
- Project root: `/mnt/c/Users/FireSongz/Desktop/HebrewFixer`
- Installer script: `Installer/HebrewFixer_Setup.iss`
- Win11 registry helper: `Tests/Win11/Set-NotificationAreaIconBehavior-Win11-3.ps1`
- Persistent log: `%APPDATA%\HebrewFixer\InstallLogs\installer_debug.log`

## Glossary
- **IsPromoted**: Win11 per-user registry value controlling whether a tray icon is shown outside the overflow.
- **NotifyIconSettings**: Registry subtree where Windows stores notification area icon preferences.
- **Inno Setup**: Installer framework used for packaging and uninstall orchestration.
- **PS sentinel**: Log entries written by PowerShell helper to prove it executed.
