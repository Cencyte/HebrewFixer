# HebrewFixer Installer — Windows System Tray Icon Persistence / Promotion (Technical Report)

**Audience:** other AI assistants / reverse-engineering + Windows shell experts

**Project:** HebrewFixer (AutoHotkey v2) — RTL Hebrew typing support for Affinity Designer

**Date:** 2026-02-07

---

## Abstract
HebrewFixer ships as a per-user Windows utility with a tray icon. We are building an **Inno Setup 6** installer and want an optional install-time setting: **“Always show HebrewFixer icon in the system tray”**. On Windows 10/11 this corresponds to the icon being **promoted/pinned** to the visible taskbar notification area (not hidden in the overflow shelf).

The core problem: Windows stores tray icon visibility state in `HKCU\Control Panel\NotifyIconSettings\<hash>` and appears to **ignore installer-created entries**, even when the key name/hash and fields (including `IsPromoted=1`) match what Explorer later uses. The only reliable method we found is to **launch the app so Explorer creates the entry**, then set `IsPromoted=1`; however this causes a visible icon appearance/flicker during install, which is unacceptable UX.

---

## TL;DR
- We can compute the `NotifyIconSettings` subkey name via a **FNV-1a 64-bit hash** of the **lowercased executable path** encoded as **UTF-16LE**.
- Pre-creating `HKCU\Control Panel\NotifyIconSettings\<hash>` with `ExecutablePath` and `IsPromoted=1` does **not** cause Windows to honor the setting.
- Windows only lists the entry in **Settings → Taskbar → Other system tray icons** after the app has actually run at least once.
- If we run the app briefly (3s), set `IsPromoted=1`, then exit, the icon becomes promoted — but the icon appears briefly (flicker).

---

## Summary of Current State
### What we want
During installation, when the user selects:
- Task: `trayvisible` = “Always show HebrewFixer icon in the system tray”

…we want the installer to ensure the tray icon is promoted, **without visibly launching** HebrewFixer (no UI, no transient tray icon).

### Why we care
- HebrewFixer is a background utility; users benefit if its state is always visible.
- Windows’s default behavior often puts new tray icons into the overflow; many users never notice them.

---

## Environment / Components
- Windows 10/11
- Tray icon is created by the running HebrewFixer executable (`HebrewFixer.exe`), compiled from AutoHotkey v2 script.
- Installer: Inno Setup 6 script: `Installer/HebrewFixer_Setup.iss`
- Helper: PowerShell script: `Installer/PromoteTrayIcon.ps1`

---

## Relevant Windows Storage Location
Windows tray icon preferences appear stored at:

```reg
HKEY_CURRENT_USER\Control Panel\NotifyIconSettings\<hash>
```

Each subkey name is a large integer-looking string, e.g.:

- `14674881347842443939`

Observed fields:
- `ExecutablePath` (string): full path to the exe
- `IsPromoted` (DWORD): `1` = always visible (promoted), `0` = overflow
- `UID` (DWORD?): identifier
- `InitialTooltip` (string)
- `IconSnapshot` (REG_BINARY): Windows-created entries contain a binary PNG snapshot (~2KB)

Key observation: **Installer-created entries lack `IconSnapshot`** (unless we fabricate it), and Explorer seems to ignore `IsPromoted` on entries it didn’t create.

---

## What We Tried (and Results)

### Attempt 1 — Pre-create registry entry (computed hash)
We computed the key name/hash for an installation path (example):

- Path: `C:\Users\FireSongz\AppData\Local\HebrewFixer\HebrewFixer.exe`
- Hash (expected key name): `14674881347842443939`

We then created:
- `HKCU\Control Panel\NotifyIconSettings\14674881347842443939`
- `ExecutablePath = <full path>`
- `IsPromoted = 1`
- `UID = 0`
- `InitialTooltip = "HebrewFixer"`

**Result:**
- The computed key name appears correct (Explorer later uses the same key name), but Explorer **ignores** our `IsPromoted` setting.
- The entry does **not** appear in Settings UI until the app has run.

**Hypotheses:**
- Explorer may require `IconSnapshot` and/or other hidden fields.
- Explorer may maintain additional caches (memory and/or other registry/db locations).
- Explorer may only honor promotion state for entries it created itself.

#### Hash computation implementation (current)
From `Installer/PromoteTrayIcon.ps1`:

```csharp
const ulong FNV_OFFSET = 14695981039346656037UL;
const ulong FNV_PRIME = 1099511628211UL;
string normalized = path.ToLowerInvariant();
byte[] bytes = Encoding.Unicode.GetBytes(normalized); // UTF-16LE
ulong hash = FNV_OFFSET;
foreach (byte b in bytes) {
    hash ^= b;
    unchecked { hash *= FNV_PRIME; }
}
return hash;
```

PowerShell then creates the key and sets values:

```powershell
New-Item -Path $regPath -Force | Out-Null
Set-ItemProperty -Path $regPath -Name "ExecutablePath" -Value $ExePath -Type String
Set-ItemProperty -Path $regPath -Name "IsPromoted" -Value 1 -Type DWord
Set-ItemProperty -Path $regPath -Name "UID" -Value 0 -Type DWord
Set-ItemProperty -Path $regPath -Name "InitialTooltip" -Value "HebrewFixer" -Type String
```

### Attempt 2 — Let Windows create entry by running the app, then modify
Workflow:
1. Launch HebrewFixer (installer runs it hidden or normal)
2. Wait ~3 seconds
3. Set `IsPromoted=1` in the now-Windows-created key
4. Close app via `/exit`

**Result:** Works consistently, but causes **visible icon flicker** (icon appears briefly in tray).

### Attempt 3 — Delete old entries on reinstall
PowerShell currently does:

```powershell
Get-ChildItem $notifyPath | ForEach-Object {
  $props = Get-ItemProperty $_.PSPath
  if ($props.ExecutablePath -like '*HebrewFixer*') {
    Remove-Item $_.PSPath -Force
  }
}
```

**Result:** Old behavior seems to persist anyway, suggesting:
- Explorer caching, or
- additional persistence not cleared by deleting these keys.

---

## How Installer Currently Invokes the Helper
From `Installer/HebrewFixer_Setup.iss`:

- Task: `trayvisible`
- Post-install code runs PowerShell with the exe path:

```pascal
if WizardIsTaskSelected('trayvisible') then
begin
  PowerShellArgs := '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '" -ExePath "' + ExePath + '"';
  Exec('powershell.exe', PowerShellArgs, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;
```

Currently this triggers **Attempt 1** (pre-create entry), which is known not to work reliably.

---

## Key Observations (Behavioral)
1. If a user manually drags the tray icon from overflow to the taskbar area, the setting persists across reinstalls.
2. Our pre-created key shows `IsPromoted=1` but Explorer behaves as if it’s not promoted.
3. Windows-created entries have `IconSnapshot` (binary PNG data); ours do not.
4. The FNV-1a key name seems correct, matching Explorer’s later chosen key.
5. The entry does not appear in **Settings → Taskbar → Other system tray icons** until the app has run.

---

## Suspected Root Causes / Theories
- **Explorer only trusts entries it created** (might stamp additional data or validate with internal caches).
- `IconSnapshot` might be **required** for UI/visibility/promotion settings to apply.
- There may be an additional store beyond `NotifyIconSettings`, e.g.:
  - `HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\TrayNotify` (historically used)
  - Explorer’s in-memory cache that only updates on icon registration events
  - A database-like blob value (common for shell caches)

---

## Constraints
- Must be per-user install (`PrivilegesRequired=lowest`), no admin.
- Must not flash a UI or tray icon during install.
- Must work on Windows 10 and Windows 11.

---

## Open Questions for Other AIs
1. **Hash algorithm**: Is FNV-1a 64-bit over UTF-16LE lowercase path definitively correct for `NotifyIconSettings` subkeys across Win10/11, or are there variant normalizations (short path, environment expansion, device paths, etc.)?
2. **Required fields**: What minimum set of values causes Explorer to accept an entry? Is `IconSnapshot` mandatory? Are there other values not listed here?
3. **Registration without display**: Is there a supported or semi-supported **Shell API** to register a tray icon entry (or its policy) without actually showing it? (e.g., a hidden `Shell_NotifyIcon` call that doesn’t surface?)
4. **Alternate approaches**:
   - Group Policy / MDM equivalents?
   - Other registry locations or COM APIs?
   - Using `ITrayNotify`/`ITrayNotify8` or undocumented interfaces?
5. **Documentation / RE**: Any known reverse engineering notes for Explorer’s tray icon persistence logic (Windows 10/11), especially regarding `NotifyIconSettings`, `IconStreams`-like blobs, or validation checks?

---

## Reproduction Notes (What to Try Next)
If you want to test hypotheses, these experiments are likely informative:
1. Compare a Windows-created key vs installer-created key for the same exe:
   - Diff all values (including unknown ones) and look for missing fields.
2. Attempt to copy `IconSnapshot` from a Windows-created entry into the pre-created entry and see if `IsPromoted` starts working.
3. Restart Explorer (`taskkill /f /im explorer.exe` then relaunch) after pre-creating the key to see if Explorer ever picks it up on startup.
4. Check for older tray cache locations and whether they are still used:
   - `HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\TrayNotify`

---

## Index
### Files
- `Installer/HebrewFixer_Setup.iss`
- `Installer/PromoteTrayIcon.ps1`
- `src/Current Version/HebrewFixer_BiDiPaste.ahk`
- `PROJECT_MANUSCRIPT.md` (project lifecycle notes)

### Registry paths
- `HKCU\Control Panel\NotifyIconSettings\<hash>`

### URLs
- Inno Setup: https://jrsoftware.org/isinfo.php
- HebrewFixer repo: https://github.com/Cencyte/HebrewFixer

---

## Glossary
- **Tray icon promotion / promoted**: Windows setting that forces a notification icon to appear in the visible taskbar area rather than the overflow/hidden area.
- **Overflow shelf**: The hidden tray icons menu (caret `^`) containing non-promoted icons.
- **NotifyIconSettings**: Per-user registry location used by Explorer for tray icon state.
- **IconSnapshot**: Binary PNG snapshot stored by Explorer for a tray icon entry.
- **FNV-1a**: Fowler–Noll–Vo hash algorithm variant (xor then multiply) used here as a hypothesized key derivation.
