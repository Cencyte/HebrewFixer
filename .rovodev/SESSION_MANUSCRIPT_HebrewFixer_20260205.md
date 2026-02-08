# SESSION MANUSCRIPT — HebrewFixer — 2026-02-05 (Thu)

**HebrewFixer Manuscripts Series:** Volume 2/4  
**Document type:** Session log (core RTL typing + BiDi paste)

**Requested save path (user machine):** `C:\Users\FireSongz\Desktop\SESSION_MANUSCRIPT_HebrewFixer_20260205.md`  
**Workspace file (this repo/session):** `SESSION_MANUSCRIPT_HebrewFixer_20260205.md`

---

## Abstract
HebrewFixer is an AutoHotkey v2 solution that simulates right-to-left (RTL) Hebrew text entry inside **Affinity Designer**, an application that lacks native BiDi (bidirectional) text support. This session focused on: (1) setting up MCP-based automation and vision tooling to test GUI behavior, (2) implementing core RTL usability fixes (cursor-relative insertion, key reversal behaviors, IME detection), and (3) delivering a practical BiDi-aware paste feature to better handle mixed Hebrew/English content. The work targets a real client, **Sara**, an elderly community member who needs to type Hebrew in Affinity Designer.

## TLDR
- Built a working **Affinity-specific RTL typing hack** in AHK v2 by inserting characters at the cursor and then moving the cursor left.
- Implemented **IME detection** so the script only activates when Windows keyboard layout is Hebrew.
- Made all key handlers **IME-aware** (RTL remaps only apply when Hebrew IME is active; English passes through normally).
- Reversed/swapped navigation + deletion keys (arrows, shift-selection, ctrl-word movement, ctrl-word deletion) to match RTL expectations.
- Added **spacebar RTL handler** (space then `{Left}` in Hebrew mode) to keep the caret position correct in right-aligned frames.
- Added **BiDi-aware paste**: split clipboard into directional runs; reverse only Hebrew runs; preserve run order.
- Added **Auto-enable on Hebrew keyboard** mode with manual override support.
- Built/iterated on a full **custom icon set** (generic rounded-rect and Affinity-branded variants) and exported multi-size ICOs.
- Fixed a PowerShell **WinGet predictor / CommandNotFound** crash by disabling the problematic module import.
- Documented GUI-testing discovery: in Affinity Designer, **double-click is required** to enter text frame edit mode.

## Summary (Key Points)
- **Session date:** Thursday, February 5th, 2026
- **Client:** Sara (community member; needs Hebrew in Affinity Designer)
- **Primary outcome:** `HebrewFixer_BiDiPaste.ahk` is the most complete/current best script and now includes auto-enable + IME-guarded key handlers.
- **UX outcome:** added a spacebar RTL fix and tightened up all remaps so English layout is unaffected.
- **Branding/shipping outcome:** created multiple production-quality icon variants (generic + Affinity-branded) with proper multi-resolution ICO exports.
- **Tooling outcome:** MCP tooling configured (computer-use + desktop-commander + vision-agent) and the `computer-user.md` guide updated with the Affinity double-click requirement.
- **Environment outcome:** fixed a noisy PowerShell profile crash caused by the WinGet `CommandNotFound` predictor module.

---

## Body (Detailed Session Record)

### 1) Context & Problem Statement
- Affinity Designer has **no BiDi/RTL** text engine support.
- Hebrew characters are displayed LTR, cursoring behaves incorrectly, and Unicode directional control characters are ignored.
- Goal: produce a v1 script that enables usable Hebrew typing for Sara **without changing Affinity Designer**.

### 2) MCP Server Setup & Automation Testing
**Objective:** enable automated GUI testing and observation to validate behavior in Affinity Designer.

#### Actions Taken
- Configured **`computer-use-mcp`** for GUI automation testing.
- Configured **desktop-commander**:
  - Required a **global npm install**.
  - Used a **direct path** to the executable for reliability.
- Configured **`vision-agent-mcp`** using a Landing AI API key.
- Removed an invalid/non-existent **windows-cli** MCP server entry.

#### Key Discovery (Affinity Designer Input)
- Affinity Designer’s text frames require **double-click** to enter edit mode.
  - Single click selects the frame but does not reliably place the insertion caret for typing.
  - This impacts automation scripts and any user instructions.

#### Documentation Added
- Created a new subagent guide: `C:\Users\FireSongz\.rovodev\subagents\computer-user.md`
  - Captures how to use `computer-use-mcp`.
  - Records the **double-click requirement** as an important operational detail.

### 3) Core Script Fixes Implemented (RTL Simulation)
**Design constraint:** Affinity Designer ignores BiDi; therefore the script must **simulate RTL** purely by keyboard event logic.

#### 3.1 IME / Keyboard Layout Detection
- Added `IsHebrewKeyboard()` implemented via Windows API `GetKeyboardLayout()`.
- Behavior: HebrewFixer logic only produces Hebrew when the **Windows keyboard layout is set to Hebrew**.
- Benefit: avoids accidental remapping while user is in English layout.

#### 3.2 Deletion & Navigation Behaviors (RTL Feel)
Implemented consistent RTL ergonomics by remapping:
- **Backspace/Delete swap**
  - Backspace sends Delete
  - Delete sends Backspace
- **Arrow key reversal**
  - Left sends Right
  - Right sends Left
- **Shift+Arrow selection reversal**
  - Ensures selection direction matches RTL expectations.
- **Ctrl+Arrow word navigation reversal**
  - Word jumps align with RTL.
- **Ctrl+Shift+Arrow word selection reversal**
  - Word selection aligns with RTL.
- **Ctrl+Backspace/Ctrl+Delete word deletion swap**
  - Word deletion aligns with RTL visual model.

#### 3.3 Cursor-Relative Insertion (Major Behavior Change)
- Replaced the prior `{Home}`-based strategy (which forced the caret to start-of-line) with:
  1. Type the character at the current caret position
  2. Move caret left
- Outcome: characters now insert **at cursor position**, supporting mid-line edits.

### 4) BiDi-Aware Paste (New Feature)
**File:** `HebrewFixer_BiDiPaste.ahk`

#### Goal
Make paste operations handle mixed-direction text in a way that matches typical BiDi rendering expectations, despite Affinity’s lack of BiDi.

#### Implementation Summary
- Clipboard text is split into **directional runs**:
  - Hebrew vs non-Hebrew (e.g., Latin letters, numbers, punctuation)
- The script:
  - **preserves run order**
  - **reverses characters only within Hebrew runs**
  - leaves non-Hebrew runs as-is

#### Example (Observed)
- Input clipboard: `םםGGSדג`
- Smart paste output: `םםGGSגד`
- Result matches Notepad’s expected visual display behavior for that mixed string.

### 5) Experimental Approaches Tested

#### 5.1 Unicode Directional Control Character Experiment
**File:** `HebrewFixer_ZWS_Experiment.ahk`
- Tested inserting Unicode directional marks (notably **RLM U+200F**) to attempt eliminating caret flicker and/or coerce RTL.
- Finding: **Affinity Designer ignores BiDi control characters entirely**.
- Conclusion: manual reversal logic is not a workaround—it is the *entire* mechanism required for RTL simulation in Affinity.

#### 5.2 Manual Reversal Toggle for Debugging
- Added `g_ManualReversalEnabled` in the experimental script.
- Purpose: quickly toggle all reversal logic on/off for A/B testing.

### 6) Cursor Flicker Investigation
**Symptom:** visible caret “twitch” while typing.

#### Root Cause
- The RTL hack requires: **send character → move cursor left**.
- This results in a perceptible caret move after each keystroke.

#### Attempted Mitigations
- `SendInput` tuning and `SetKeyDelay(-1, -1)`
- Clipboard paste with RLM control characters

#### Result
- Flicker persisted.
- Conclusion: flicker appears **unavoidable in pure AHK** without deeper OS-level interception.

#### Noted True Fix Directions
- C++ low-level keyboard hook / DLL approach
- Hidden RichEdit control approach (native RTL engine) that then transmits text to Affinity

### 7) Windows Tray Icon Investigation

#### 7.1 Goal (Installer UX)
- In the Inno Setup installer, provide an option: **“Always show HebrewFixer icon in the system tray (recommended)”**.
- Desired behavior: ensure the tray icon is **promoted/pinned to the visible taskbar notification area** (not hidden in the overflow) **without** visibly launching the app during installation (no flicker).

#### 7.2 Windows Storage (Observed)
- Windows 10/11 stores tray icon visibility preferences at:
  - `HKCU\\Control Panel\\NotifyIconSettings\\<hash>`
- Each subkey name is a large numeric string and appears derived from the exe path.
- Values encountered:
  - `ExecutablePath` (string)
  - `IsPromoted` (DWORD; 1=visible, 0=overflow)
  - `UID`
  - `InitialTooltip`
  - `IconSnapshot` (REG_BINARY PNG) — present on Windows-created entries

#### 7.3 Current Implementation
- Installer script: `Desktop/HebrewFixer/Installer/HebrewFixer_Setup.iss`
  - Task name: `trayvisible`
  - Post-install invokes PowerShell hidden:
    - `powershell.exe -NoProfile -ExecutionPolicy Bypass -File {app}\\PromoteTrayIcon.ps1 -ExePath {app}\\HebrewFixer.exe`
- PowerShell helper: `Desktop/HebrewFixer/Installer/PromoteTrayIcon.ps1`
  - Computes FNV-1a 64-bit hash over lowercase UTF-16LE path.
  - Pre-creates `NotifyIconSettings\\<hash>` and sets `IsPromoted=1`.

#### 7.4 What Works vs What Doesn’t
- **Pre-creating** the `NotifyIconSettings` key with correct hash + `IsPromoted=1`:
  - Key appears correct, but Explorer **ignores** the promotion.
  - Entry doesn’t appear in Settings UI until the app has run.
- **Running the app briefly** so Windows creates the entry, then setting `IsPromoted=1`:
  - Works, but causes **visible tray icon flicker** during installation (unacceptable UX).
- **Deleting old entries** before reinstall:
  - Does not reliably reset behavior (suggests additional Explorer caching or other storage).

#### 7.5 Working Notes / Next Research Targets
- Determine if `IconSnapshot` or additional hidden fields are required.
- Identify any other persistence locations (historical: `...TrayNotify`).
- Investigate whether any Shell API/COM interface can register an icon entry without visible display.
- A standalone shareable report was created: `Desktop/HebrewFixer/Installer/REPORT_Windows_TrayIcon_Persistence.md`.
- Attempted to force the tray icon to always be visible.
- Finding: Windows associates tray visibility preferences with the hosting process (e.g., `AutoHotkey64.exe`) rather than a raw `.ahk` script.
- Practical implication: compiling to `.exe` is needed for distinct identity.

---

## Deliverables / Artifacts (This Session)

### Desktop (Per User Report)
- `HebrewFixer_PerKey.ahk` — main working script (modified)
- `HebrewFixer_PerKey_WORKING_BACKUP.ahk` — backup
- `HebrewFixer_ZWS_Experiment.ahk` — RLM/control-char experiment
- `HebrewFixer_BiDiPaste.ahk` — BiDi-aware paste version (**current best**)

### Subagent Documentation
- `C:\Users\FireSongz\.rovodev\subagents\computer-user.md` — `computer-use-mcp` usage guide

---

### 8) Continued Session Progress (Icons, Auto-Enable, IME-Guarded Handlers)

#### 8.1 Icon Creation Journey
After the core script functionality was stable, significant time went into producing **custom tray/app icons** suitable for an eventual compiled `.exe` + installer.

1) **First attempt — extract Shin (ש) glyph from font**
- Used Python **fonttools** to extract the Shin glyph from `FrankRuehlCLM-Bold.otf` as SVG.
- Required Cairo support; resolved by adding GIMP’s `bin` directory to `PATH`:
  - `C:\Program Files\GIMP 3\bin`
- Output: `shin_icon.svg`.

2) **White rounded rectangle icons**
- Created:
  - `hebrew_fixer_on.ico`: white rounded rectangle, black border, black Shin.
  - `hebrew_fixer_off.ico`: same base icon + red diagonal strikethrough (NE→SW), with a white border then black border for contrast.
- Ensured the strikethrough remains **within rounded-rectangle bounds**.

3) **Affinity Designer branded icons**
- Extracted an Affinity Designer logo from `Designer.exe` (initially 32×32; upscaled for iteration).
- User provided a high-resolution `Designer.png` export.
- Extracted a preferred Shin glyph from `frank.ttf` (FrankRuehl font with the distinctive **rectangular middle stem**).
- Final composition was done manually in Affinity Designer:
  - `finally.png` → `hebrew_fixer_affinity_on.ico` (white Shin with black outline on Affinity logo)
  - `finally2.png` → `hebrew_fixer_affinity_off.ico` (disabled state indicated with an “A”)
- Converted PNG → ICO (multi-size) via ImageMagick:
  - `magick input.png -define icon:auto-resize=256,128,64,48,32,16 output.ico`

#### 8.2 PowerShell Predictor Fix (WinGet CommandNotFound Crash)
- Traced recurring PowerShell errors to the WinGet predictor / `CommandNotFound` module.
- Fixed by commenting out:
  - `Import-Module -Name Microsoft.WinGet.CommandNotFound`
- This was associated with a PowerToys-style CommandNotFound integration that can crash in **non-interactive** sessions.

#### 8.3 Auto-Enable on Hebrew Keyboard (New Feature)
Added an “Auto-enable on Hebrew keyboard” mode:
- New tray menu toggle option.
- A timer runs every **250ms** calling `IsHebrewKeyboard()`.
- Behavior when Auto-enable is ON:
  - If Hebrew IME detected: HebrewFixer enables itself.
  - If English IME detected: HebrewFixer disables itself.
- Manual override supported:
  - `Ctrl+Alt+H` can override the auto state.
  - Override clears when the user switches IME.
- UI feedback:
  - Tooltip shows an `[Auto]` suffix when auto mode is enabled.
  - Tooltip shows `(override)` when manually overridden.

#### 8.4 IME-Aware Key Handlers (Critical Bug Fix)
All remappings now explicitly check `IsHebrewKeyboard()` before applying RTL behavior:
- Backspace/Delete swap only when Hebrew IME active.
- Arrow key reversal (and variants: Shift/Ctrl/Ctrl+Shift) only when Hebrew IME active.
- Ctrl+Backspace/Ctrl+Delete swap only when Hebrew IME active.
- When English IME is active: keys pass through normally.

#### 8.5 Spacebar RTL Handler
- Added a spacebar handler for right-aligned Hebrew typing:
  - Hebrew mode: send `Space` then `{Left}` to maintain RTL cursor position.
  - English mode: send a normal space.
- Fixes the observed issue where a plain space could become effectively “idempotent” in certain right-aligned Affinity text frames.

#### 8.6 Files Created / Updated During This Continued Session
**Icons (final outputs):**
- `C:\Users\FireSongz\Desktop\hebrew_fixer_on.ico`
- `C:\Users\FireSongz\Desktop\hebrew_fixer_off.ico`
- `C:\Users\FireSongz\Desktop\hebrew_fixer_affinity_on.ico`
- `C:\Users\FireSongz\Desktop\hebrew_fixer_affinity_off.ico`

**Icon intermediates / sources:**
- `C:\Users\FireSongz\Desktop\shin_icon.svg`
- `C:\Users\FireSongz\Desktop\shin_frank.svg`
- `C:\Users\FireSongz\Desktop\shin_frank_black.png`
- `C:\Users\FireSongz\Desktop\shin_frank_white.png`
- `C:\Users\FireSongz\Desktop\Designer.png`
- `C:\Users\FireSongz\Desktop\finally.png`
- `C:\Users\FireSongz\Desktop\finally2.png`

**Scripts:**
- `C:\Users\FireSongz\Desktop\HebrewFixer_BiDiPaste.ahk` (continued improvements; best current version)
- `C:\Users\FireSongz\Desktop\tmp_extract_shin_v2.py`

**Subagents:**
- `C:\Users\FireSongz\.rovodev\subagents\computer-user.md` (updated: Affinity requires double-click to enter text edit mode)

#### 8.7 Next Steps (Planned)
1. Compile `HebrewFixer_BiDiPaste.ahk` to `.exe` using **Ahk2Exe**.
2. Create an installer using **Inno Setup**.
3. Bundle icons with the installer.
4. Add a registry entry for persistent tray icon visibility.
5. Clean up temporary/intermediate Desktop files.
6. Deliver to Sara with concise usage + install instructions.

#### 8.8 Technical Notes
- ImageMagick ICO command:
  - `magick input.png -define icon:auto-resize=256,128,64,48,32,16 output.ico`
- Cairo library path used for Python tooling:
  - `C:\Program Files\GIMP 3\bin`
- FrankRuehl font note:
  - `frank.ttf` contains the distinctive rectangular-stem Shin glyph that matches expectations better than other FrankRuehl variants.
- Automation/tooling quirk:
  - `computer-use-mcp` workflows need **double-click** to enter text edit mode in Affinity Designer.

## Current Project Status (End of Session)
**Best current script:** `HebrewFixer_BiDiPaste.ahk`

Implemented and working:
- Hebrew key mapping (US QWERTY → Hebrew)
- Affinity-specific activation via `#HotIf`
- IME detection (`IsHebrewKeyboard()` + `GetKeyboardLayout()`)
- Cursor-relative RTL insertion (type char then move caret left)
- Swapped Backspace/Delete
- Reversed arrow keys and modified variants (Shift/Ctrl/Ctrl+Shift)
- Swapped Ctrl+Backspace/Ctrl+Delete word deletion semantics
- BiDi-aware paste for mixed Hebrew/English

Known limitation:
- Minor but visible cursor flicker while typing (cosmetic)

---

## Future To‑Do

### Immediate (Sara Delivery)
1. Compile `HebrewFixer_BiDiPaste.ahk` to `HebrewFixer.exe` with Ahk2Exe
2. Package an installer (e.g., Inno Setup) for easy installation and startup registration
3. Add a tray icon visibility strategy (likely via compiled EXE + user guidance; registry option if appropriate)
4. Write simple end-user instructions (large font, minimal steps) for Sara

### Future Enhancements (V2)
1. Hidden RichEdit control approach (native RTL) to eliminate flicker and enable truer BiDi
2. C++ DLL with keyboard hooks for flicker-free behavior and richer control
3. Generalize to other non-BiDi apps beyond Affinity Designer

### Known Edge Cases / Unverified
- Niqqud (Hebrew vowel points) untested
- Complex nested BiDi scenarios may not be perfect
- Mixed RTL/LTR inside the same “word” may behave unexpectedly

---

## Client Communication Notes
- Met Sara at the library on Monday prior to this session.
- She reported frustration with unhelpful advice and lack of workable solutions.
- Plan: send an email including a GIF demo of the working script.
- V1 is considered functional enough to deliver soon.

---

## Conclusion
This session produced a practical v1 Hebrew RTL typing workflow for Affinity Designer using AutoHotkey v2, plus critical supporting tooling for testing and debugging. While the AHK approach cannot remove caret flicker (due to the necessary “type then move left” simulation), it delivers functional Hebrew entry with intuitive RTL navigation/deletion behavior and a notably improved BiDi-aware paste operation. The next milestone is packaging (compile + installer) and creating user-friendly instructions for Sara.

---

## Index

### Files (Referenced)
- `C:\Users\FireSongz\Desktop\HebrewFixer_PerKey.ahk`
- `C:\Users\FireSongz\Desktop\HebrewFixer_PerKey_WORKING_BACKUP.ahk`
- `C:\Users\FireSongz\Desktop\HebrewFixer_ZWS_Experiment.ahk`
- `C:\Users\FireSongz\Desktop\HebrewFixer_BiDiPaste.ahk`
- `C:\Users\FireSongz\Desktop\tmp_extract_shin_v2.py`
- `C:\Users\FireSongz\Desktop\hebrew_fixer_on.ico`
- `C:\Users\FireSongz\Desktop\hebrew_fixer_off.ico`
- `C:\Users\FireSongz\Desktop\hebrew_fixer_affinity_on.ico`
- `C:\Users\FireSongz\Desktop\hebrew_fixer_affinity_off.ico`
- `C:\Users\FireSongz\Desktop\shin_icon.svg`
- `C:\Users\FireSongz\Desktop\shin_frank.svg`
- `C:\Users\FireSongz\Desktop\shin_frank_black.png`
- `C:\Users\FireSongz\Desktop\shin_frank_white.png`
- `C:\Users\FireSongz\Desktop\Designer.png`
- `C:\Users\FireSongz\Desktop\finally.png`
- `C:\Users\FireSongz\Desktop\finally2.png`
- `C:\Users\FireSongz\.rovodev\subagents\computer-user.md`

### Folders (Referenced)
- `C:\Users\FireSongz\Desktop\`
- `C:\Users\FireSongz\.rovodev\subagents\`

### Tools / Services / URLs
- AutoHotkey v2 (AHK v2)
- ImageMagick (`magick`) for multi-resolution ICO generation
- Python `fonttools` (glyph extraction)
- Cairo (provided via GIMP runtime; added `C:\Program Files\GIMP 3\bin` to `PATH`)
- Affinity Designer (target application)
- MCP servers:
  - `computer-use-mcp`
  - `desktop-commander`
  - `vision-agent-mcp` (Landing AI)

---

## Glossary of Terms
- **AHK / AutoHotkey v2:** Windows automation scripting language used to intercept/remap keys.
- **Affinity Designer:** Design application lacking BiDi/RTL text support.
- **Ahk2Exe:** AutoHotkey compiler used to bundle `.ahk` scripts into a standalone Windows `.exe`.
- **Auto-enable (Hebrew keyboard):** A HebrewFixer mode where a timer toggles script behavior based on active IME/layout.
- **Manual override:** User-forced enable/disable state (e.g., via `Ctrl+Alt+H`) that temporarily supersedes auto-enable until IME changes.
- **BiDi:** Bidirectional text handling (mixing RTL and LTR scripts) governed by the Unicode BiDi algorithm.
- **RTL (Right-to-Left):** Text direction used by Hebrew/Arabic scripts.
- **IME (Input Method Editor):** Windows input system / keyboard layout selection used here to detect Hebrew vs English typing mode.
- **Logical order:** The internal stored character order (generally the order typed).
- **Visual order:** The on-screen rendering order after applying BiDi rules.
- **RLM (U+200F):** Right-to-Left Mark; Unicode directional formatting character.
- **Directional run:** A contiguous sequence of characters treated as a single direction segment for processing.
- **MCP (Model Context Protocol):** Tooling ecosystem used here for GUI automation and vision-assisted testing.
- **Caret flicker/twitch:** Visible cursor movement caused by sending a character then moving the caret left to simulate RTL.
- **CommandNotFound / WinGet predictor:** PowerShell module (`Microsoft.WinGet.CommandNotFound`) that can suggest commands but was causing crashes/errors in this environment.
- **Inno Setup:** Windows installer builder planned for packaging HebrewFixer for distribution.
