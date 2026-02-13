# HebrewFixer — Project Lifecycle Manuscript

**HebrewFixer Manuscripts Series:** Volume 1/6  
**Document type:** Project lifecycle (tray icon + packaging focus)

## Abstract
HebrewFixer is a Windows per-user tray utility (built with AutoHotkey v2) that improves RTL/Hebrew typing workflows (initially targeting Affinity apps) by intercepting keyboard input and performing cursor-relative insertion.

This manuscript tracks the project lifecycle: investigations, experiments, files/paths, installer work, and especially Windows tray icon persistence/promotion behavior across Windows versions.

## TL;DR
- HebrewFixer uses an AutoHotkey v2 tray icon.
- Windows tray icon visibility/promotion is inconsistent across versions; installer-created `NotifyIconSettings` entries are not reliably honored.
- Windows 11 24H2 appears to have deprecated/removed legacy tray icon registry caches (`TrayNotify` streams) for new apps.
- **Root cause discovered (2026-02-07): ExplorerPatcher** was installed and forcing a **Windows 10-style taskbar**, which changes notification-area behavior (visible tray placement + icon pop-up previews). This explains why behavior differed vs Windows Sandbox (stock Windows 11).
- New critical lead: incorrect `Shell_NotifyIcon` / `NOTIFYICONDATAW` struct sizing can cause the shell to treat the notify icon version as legacy (`uVersion = 0`) rather than `NOTIFYICON_VERSION_4`, changing behavior (incl. modern tooltip handling) and potentially overflow placement defaults.

## Summary
- Primary UX goal: control whether HebrewFixer’s tray icon starts **visible** or in the **overflow shelf** on first run.
- Key technical friction: Explorer appears to maintain internal state beyond simple registry writes.
- **Critical environmental factor discovered:** ExplorerPatcher can silently switch Explorer to a Windows 10-style taskbar, changing tray icon visibility defaults and UI behaviors.
- Windows 11 24H2 introduces behavior changes: new apps may not receive `HKCU\\Control Panel\\NotifyIconSettings` entries at all.

## Body

### 2026-02-07 — Tray icon visibility/promotion investigation continues (Windows 11 24H2)
#### Context
This continues the earlier “tray icon promotion / `IsPromoted`” investigation. A key new baseline observation is that on Windows 11 **24H2**, Explorer may **not create** `NotifyIconSettings` registry entries for newly-seen apps.

#### Discovery: legacy “Notification Area Icons” Control Panel applet still enumerates HebrewFixer
- Opened via shell URI:
  - `shell:::{05d7b0f4-2121-4eff-bf6b-ed3f69b894d9}`
- This legacy applet **does show HebrewFixer in real-time**.
- Renaming the executable to `HebrewFixer1998.exe` caused it to appear at the **bottom** of the list.
- Implication: the legacy enumeration/policy mechanism is still functional and can “see” HebrewFixer even when modern Settings/registry traces appear absent.

#### Experiment: transparency / overlay approach to make the legacy UI usable
- Created `notification_area_icons_transparent.ahk` to try to make the legacy applet window transparent for automation/overlay workflows.
- Window identification was successful:
  - Top-level window class: `CabinetWClass`
  - Title contains: “Notification Area Icons”
- Notable child windows encountered:
  - `Microsoft.UI.Content.DesktopChildSiteBridge`
  - `DirectUIHWND`
  - `DUIViewWndClassName`
- Result:
  - Transparency can be applied to the **File Explorer chrome**, but the **content pane** uses **DirectComposition** and resists transparency effects.
- Script hotkeys:
  - `Ctrl+Alt+T` — apply transparency
  - `Ctrl+Alt+R` — restore opacity
  - `Ctrl+Alt+D` — debug

#### Registry investigation (Windows 11 24H2)
- Observed registry paths:
  - `HKCU\Control Panel\NotifyIconSettings`
  - `HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\TrayNotify`
- Findings on 24H2:
  - No `NotifyIconSettings` entries are created for HebrewFixer (even after running).
  - `TrayNotify` legacy values such as `IconStreams` / `PastIconsStream` are absent.
- Working conclusion: older registry-backed tray icon storage appears **deprecated/removed** in 24H2, at least for newly-installed applications.

#### Comparative analysis: OBS Studio tray behavior
- Downloaded and analyzed OBS source code.
- Relevant file:
  - `obs-studio-source/obs-studio-master/frontend/widgets/OBSBasic_SysTray.cpp`
- Findings:
  - OBS has a “Minimize to system tray when started” setting (`SysTrayWhenStarted`).
  - OBS does **nothing special** to promote the tray icon.
  - It simply calls `trayIcon->show()` and differs mainly by not showing its main window.
  - On the test system, OBS (and WireGuard) land in the **overflow shelf** because Windows defaults new/unknown icons to overflow.

#### Discovery: `Shell_NotifyIcon` version/struct-size can change modern vs legacy behavior
##### Microsoft documentation confirmation
- Per Microsoft Learn documentation for the notification area, icons added via `Shell_NotifyIcon` are placed in the **overflow by default** since Windows 7.
- URL: https://learn.microsoft.com/en-us/windows/win32/shell/notification-area

##### EarTrumpet GitHub issue #460 — critical finding
- URL: https://github.com/File-New-Project/EarTrumpet/issues/460
- EarTrumpet observed incorrect behavior for some tray icons created via `Shell_NotifyIcon`.
- **Root cause:** the `NOTIFYICONDATA` struct size was incorrect, causing the shell to treat `uVersion` as **0** instead of `NOTIFYICON_VERSION_4`.
  - When `uVersion` is **0** (legacy), the shell uses older behavior.
  - When `uVersion` is `NOTIFYICON_VERSION_4`, the shell uses modern behavior, including `NIF_SHOWTIP` for tooltips.
- Key detail: struct size for `NOTIFYICONDATAW` on Vista+ is **976 bytes**.

##### Working hypothesis for HebrewFixer
- AutoHotkey’s compiled tray icon may be using **legacy** `Shell_NotifyIcon` behavior (version 0 or 3).
- If so, Windows may treat AutoHotkey icons differently than modern Win32/Qt apps (e.g., possibly **promoting** them by default instead of placing them in overflow).
- This could help explain why OBS behaves “normally” (overflow by default) while HebrewFixer appears **visible** by default.

##### Proposed solution direction
1. Start HebrewFixer with the `#NoTrayIcon` directive (disable AutoHotkey’s built-in tray icon).
2. Create a custom tray icon via `DllCall` to `Shell_NotifyIcon` with:
   - Proper `NOTIFYICONDATAW` struct size (**976 bytes**)
   - `NIM_SETVERSION` with `NOTIFYICON_VERSION_4`
   - `NIF_SHOWTIP` flag included
3. Expected effect: Windows treats HebrewFixer’s icon as a modern app, placing it in **overflow by default**.

##### Related files / paths (reference)
- OBS source downloaded to: `C:\Users\FireSongz\Desktop\HebrewFixer\obs-studio-source\`
- OBS tray code at: `obs-studio-source\obs-studio-master\frontend\widgets\OBSBasic_SysTray.cpp`
- OBS finding: OBS just calls `trayIcon->show()` normally — nothing special for overflow placement.

#### Core problem (reframed)
- HebrewFixer’s icon appears in the **VISIBLE** notification area on first launch (even on a fresh install and even after renaming the exe, e.g. `HebrewFixer1998.exe`).
- Meanwhile, OBS and WireGuard appear in **overflow** by default.
- Primary new hypothesis: AutoHotkey’s tray icon creation (e.g., `TraySetIcon` / its underlying `Shell_NotifyIcon` usage) may set flags or behaviors that influence whether Explorer treats the icon as promoted/visible.

#### Open questions (current)
1. Why does HebrewFixer default to **visible** while OBS defaults to **overflow**?
2. Does AutoHotkey’s `Shell_NotifyIcon` call include flags that influence promotion?
3. Can `NIS_HIDDEN` (or similar) be used to register the icon without showing it, then ensure it remains in overflow?
4. Can we automate the legacy “Notification Area Icons” UI to set the preference?

#### Root cause discovered: ExplorerPatcher (Windows 10-style taskbar) — **2026-02-07**
##### The problem
- The system under test had **ExplorerPatcher** installed, configured to use a **Windows 10-style taskbar**.
- This changes notification area behavior versus stock Windows 11, including:
  1. Tray icons appearing in the visible taskbar area (Windows 10 behavior).
  2. “Pop-up previews” for notification icons (Windows 10 behavior).
  3. Overall notification overflow behavior differing from **Windows Sandbox** (which runs stock Windows 11).

##### Why this was confusing
- Stock Windows 11 does not support “small taskbar” natively; ExplorerPatcher can re-enable a Windows 10-style implementation.
- ExplorerPatcher modifies shell UX in ways that can be easy to forget and hard to detect during debugging.
- Much of the prior tray icon testing was therefore done in a **non-stock** shell environment.

##### What this means
On a **stock Windows 11** system (without ExplorerPatcher):
- New tray icons likely **do** default to the **overflow shelf**.
- The previously-proposed `IsPromoted` registry approach may actually work (where applicable / when entries exist).
- The original installer flow (launch app → set registry → close) may be viable again.

##### Lessons learned
1. Always test on a clean/stock Windows environment when investigating Explorer/taskbar UX.
2. Third-party shell modifications can completely change system behavior.
3. Windows Sandbox is valuable for validating stock behavior quickly.

##### Next steps (revised)
- Re-evaluate the installer “promote/pin” behavior with **ExplorerPatcher disabled** and/or in **Windows Sandbox**.
- Re-test whether the installer checkbox for “pin / always show tray icon” works as originally intended on stock Windows 11.

#### Current goal
Re-validate the desired behavior on **stock Windows 11** and then choose the simplest reliable mechanism to control initial tray visibility (overflow vs visible), given that third-party shell modifications (e.g., ExplorerPatcher) can invalidate assumptions.

## Conclusion
A major confounder was identified: **ExplorerPatcher** (configured for a **Windows 10-style taskbar**) can substantially alter tray/notification-area UX, including whether new icons appear visible vs overflow and whether icons produce Windows 10-style “pop-up previews”. This explains the mismatch between the primary test system and **Windows Sandbox** (stock Windows 11).

With that root cause in mind, the investigation should be re-grounded in **stock Windows 11** behavior first (Sandbox or ExplorerPatcher disabled). Separately, Windows 11 24H2 still appears to have changed tray icon persistence such that older registry-based approaches (`NotifyIconSettings`, `TrayNotify` streams) may not apply uniformly. The legacy “Notification Area Icons” Control Panel applet remains a useful observational tool (it can enumerate HebrewFixer in real time), but any automation or registry strategy must be validated on an unmodified shell.or registry strategy must be validated on an unmodified shell. Separately, Windows 11 24H2 still appears to have changed tray icon persistence enough that older registry-based approaches (`NotifyIconSettings`, `TrayNotify` streams) may not apply uniformly. The legacy “Notification Area Icons” Control Panel applet remains a useful observational tool (it can enumerate HebrewFixer in real time), but any automation or registry strategy must be validated on an unmodified shell.

## Index
### Files (workspace)
- `Desktop/HebrewFixer/PROJECT_MANUSCRIPT.md`
- `Desktop/HebrewFixer/README.md`
- `Desktop/HebrewFixer/Installer/REPORT_Windows_TrayIcon_Persistence.md`
- `Desktop/HebrewFixer/notification_area_icons_transparent.ahk`
- `Desktop/HebrewFixer/enumerate_tray_windows.ahk`
- `Desktop/HebrewFixer/Installer/HebrewFixer_Setup.iss`
- `Desktop/HebrewFixer/obs-studio-source/obs-studio-master/frontend/widgets/OBSBasic_SysTray.cpp`
- `Desktop/ExplorerPatcher_26100.4946.69.6.reg` (evidence/config artifact present on test machine)

### Folders (workspace)
- `Desktop/HebrewFixer/obs-studio-source/obs-studio-master/`

### Registry paths
- `HKCU\Control Panel\NotifyIconSettings`
- `HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\TrayNotify`

### Shell URIs / CLSIDs
- `shell:::{05d7b0f4-2121-4eff-bf6b-ed3f69b894d9}` (Notification Area Icons legacy applet)

### URLs
- HebrewFixer repo: https://github.com/Cencyte/HebrewFixer
- AutoHotkey v2: https://www.autohotkey.com/
- Microsoft Learn — Notification area (`Shell_NotifyIcon`): https://learn.microsoft.com/en-us/windows/win32/shell/notification-area
- EarTrumpet issue #460 (notify icon version/struct size): https://github.com/File-New-Project/EarTrumpet/issues/460
- OBS Studio: https://github.com/obsproject/obs-studio

## Glossary of Terms
- **ExplorerPatcher**: Third-party Windows shell modification tool. In this project it was found to be forcing a Windows 10-style taskbar on the test system, invalidating assumptions about stock Windows 11 notification/tray behavior.
- **Overflow shelf**: The hidden tray icons menu (caret `^`) containing non-promoted icons.
- **Tray icon promotion / promoted**: A state where an icon is forced into the visible notification area rather than overflow.
- **`Shell_NotifyIcon`**: Win32 API used to add/modify/remove notification area (tray) icons.
- **`NOTIFYICONDATA` / `NOTIFYICONDATAW`**: Struct passed to `Shell_NotifyIcon`. On Vista+ the wide version’s size is **976 bytes**; incorrect sizing can change shell behavior.
- **`uVersion`**: Notify icon version field. `0` indicates legacy behavior; `NOTIFYICON_VERSION_4` indicates modern behavior.
- **`NIM_SETVERSION`**: `Shell_NotifyIcon` message used to set the notify icon version (e.g., `NOTIFYICON_VERSION_4`).
- **`NOTIFYICON_VERSION_4`**: Modern notification icon behavior version (Windows Vista+).
- **`NIF_SHOWTIP`**: Flag enabling modern tooltip behavior in newer notify icon versions.
- **`NotifyIconSettings`**: Registry location historically used by Explorer for tray icon state.
- **Notification Area Icons (legacy applet)**: Control Panel UI opened via `shell:::{05d7b0f4-2121-4eff-bf6b-ed3f69b894d9}` that enumerates and configures notification icons.
- **DirectComposition**: Windows composition system used by modern UI surfaces; can prevent classic transparency tricks.
- **`IconStreams` / `PastIconsStream`**: Historical tray icon cache values under `TrayNotify` (observed missing on Windows 11 24H2).
- **`NIS_HIDDEN`**: A `Shell_NotifyIcon` behavior/flag name referenced as a possible approach to register a hidden icon without displaying it.
