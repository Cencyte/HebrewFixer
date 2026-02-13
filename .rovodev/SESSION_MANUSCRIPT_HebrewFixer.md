# HebrewFixer — Project Lifecycle Manuscript

**HebrewFixer Manuscripts Series:** Volume 3/6  
**Document type:** Early lifecycle log (per-key intercept origins)

## Abstract
HebrewFixer is an AutoHotkey (AHK) project intended to improve right-to-left (RTL) Hebrew typing workflows (notably for design apps like Affinity Designer). This manuscript tracks the project’s lifecycle: goals, implementation iterations, Git history, file changes, and outstanding issues.

## TLDR
- Initial v1.0 (`master`) provided basic RTL Hebrew support.
- A v2.0 experiment (`cencyte_experimental`) used `InputHook("V I1")` and was abandoned due to visual glitching from “let through then delete/rebuild”.
- Current work (`cencyte_perkey_intercept`) uses per-key `$`-prefixed hotkeys for true interception and an O(1) RTL insertion pattern: `{Home}` + `SendText(char)`.
- Major win: the “accordion effect” is eliminated.
- Remaining work: IME detection gating, first-character cursor behavior, swap backspace/delete, reverse arrow keys.

## Summary (Key Points)
- Hotkeys must be bound to *physical keys* (e.g., `a`, `b`, `c`), not Hebrew characters directly.
- O(n) delete-and-retype approaches are unusable (glitch/accordion).
- O(1) insertion is viable and stable: move to line start then insert one character.
- Correct behavior must be conditional on Windows IME layout state (Hebrew vs English) and an explicit toggle.

## Body (Chronological Log)

### 2026-02-05 — Late Session (FireSongz)
**Goal:** Achieve reliable RTL Hebrew typing by intercepting keystrokes and inserting mapped Hebrew characters without visual artifacts.

#### Iteration 1 — `cencyte_experimental` (InputHook “V mode”)
- **Approach:** AHK v2 `InputHook("V I1")`.
- **Observed result:** “Beyond horrible” visual glitching / accordion-like behavior.
- **Root cause:** `V` mode allows characters through, then script attempts to delete/rebuild. This leads to flicker, cursor instability, and cumulative visual artifacts.
- **Outcome:** Approach deemed fundamentally wrong for this problem.

#### Iteration 2 — `cencyte_perkey_intercept` (v1)
- **Approach:** Individual `$` hotkeys for true interception (prevent native keystroke from reaching the app).
- **Problems found:**
  1. **Layout misalignment:** Attempted to catch Hebrew characters instead of physical keys.
  2. **Accordion effect:** O(n) delete-all + retype-all per keystroke.
- **Outcome:** Directionally correct (true interception), but needed correct physical mapping + constant-time insertion.

#### Iteration 3 — `cencyte_perkey_intercept` (v2)
- **Fix 1: Physical key mapping:**
  - Bind hotkeys to physical keys (e.g., `a`, `b`, `c`).
  - Use an explicit map from physical key → Hebrew character.
- **Fix 2: O(1) insertion:**
  - Insert without rebuilding a buffer.
  - Pattern: `{Home}` + `SendText(char)`.
- **Result:** **Accordion problem 100% fixed.**

#### Remaining issues (queued for next session)
1. **IME detection missing**
   - Current behavior: Hebrew replacement happens even when Windows IME is English.
   - Requirement: only replace when (IME == Hebrew) AND (HebrewFixer toggle == ON).
   - Likely solution space: Windows APIs such as `GetKeyboardLayout()` / AHK wrappers.

2. **First character cursor bug**
   - Symptom: first character advances cursor by one; subsequent characters keep cursor stationary as intended.
   - Expected: first character should *not* advance cursor.

3. **Delete key behavior wrong**
   - Desired RTL semantics: swap backspace/delete behaviors.
   - Target behavior:
     - `Delete` should act like normal `Backspace`.
     - `Backspace` should act like normal `Delete`.

4. **Arrow keys not reversed**
   - Desired: swap left/right arrows for RTL navigation.


## Git / Repo State (Verified from workspace)
- **Repo path:** `/home/firesongz/Source/HebrewFixer`
- **Working tree files (top-level):**
  - `Source/HebrewFixer/HebrewFixer.ahk`
  - `Source/HebrewFixer/HebrewFixer_PerKey.ahk`

### Branches
- `master` @ `d177f95` — “Initial commit: HebrewFixer v1.0 - RTL Hebrew support for Affinity Designer”
- `cencyte_experimental` @ `1dd23ee` — “v2.0 Experimental: Major improvements to RTL handling”
- `cencyte_perkey_intercept` @ `7f26090` — “v2: O(1) insertion + physical key mapping” (**current HEAD**)

### Recent commits (from `git log --oneline -n 20`)
- `7f26090` (HEAD -> `cencyte_perkey_intercept`) v2: O(1) insertion + physical key mapping
- `8e0b6d4` Per-Key Intercept version: True keystroke blocking
- `d177f95` (`master`) Initial commit: HebrewFixer v1.0 - RTL Hebrew support for Affinity Designer

## Implementation Notes / Code Excerpts (Verified)

### Per-key intercept + physical-key map
- File: `Source/HebrewFixer/HebrewFixer_PerKey.ahk`
- Mapping is defined as `HebrewMap := Map(...)` from US-QWERTY physical keys to Hebrew characters (Israeli layout).

```autohotkey
global HebrewMap := Map(
    "t", "א",
    "c", "ב",
    "d", "ג",
    "s", "ד",
    "v", "ה",
    "u", "ו",
    "z", "ז",
    "j", "ח",
    "y", "ט",
    "h", "י",
    "l", "כ",
    "f", "ך",  ; final kaf
    "k", "ל",
    "n", "מ",
    "o", "ם",  ; final mem
    "b", "נ",
    "i", "ן",  ; final nun
    "x", "ס",
    "g", "ע",
    "p", "פ",
    ";", "ף",  ; final pe
    "m", "צ",
    ".", "ץ",  ; final tsadi
    "e", "ק",
    "r", "ר",
    "a", "ש",
    ",", "ת"
)
```

### O(1) insertion core
This is the current constant-time insertion strategy that eliminated the accordion effect:

```autohotkey
Send("{Home}")
SendText(hebrewChar)
```

### Current special-key logic (ties to open issues)
- Backspace handler currently does `Send("{Home}{Delete}")` when buffer has content.
- Delete handler currently does `Send("{End}{BS}")` when buffer has content.
- Arrow keys are currently passed through as-is (`$Left:: Send("{Left}")`, `$Right:: Send("{Right}")`).

These blocks are the likely touchpoints for:
- swapping backspace/delete semantics for RTL
- swapping left/right arrows
- buffering/cursor behavior for the first character

## Conclusion
The project has validated a stable technical core: true per-key interception combined with O(1) RTL insertion using `{Home}` + `SendText`. The remaining tasks are correctness/UX refinements (IME gating, first-key cursor quirk, and RTL-expected key semantics for delete/backspace and arrows).

## Index
### Files (workspace paths)
- `Source/HebrewFixer/HebrewFixer.ahk`
- `Source/HebrewFixer/HebrewFixer_PerKey.ahk`
- `Desktop/SESSION_MANUSCRIPT_HebrewFixer.md`

### Folders
- `Source/HebrewFixer/`

### External paths / deployment targets (user-reported)
- `/mnt/Laptop/Desktop/HebrewFixer_PerKey.ahk` (deployed for testing)

### URLs
- (none captured in this session)

## Glossary of Terms
- **AHK / AutoHotkey:** Windows automation and hotkey scripting tool (v2 used here).
- **InputHook:** AHK input-capture API; `V` mode permits characters to pass through before processing.
- **Per-key intercept:** Approach using individual hotkeys (often with `$` to force hook) to block and replace keystrokes.
- **Accordion effect:** Visual/glitch artifact where each keystroke triggers delete/retype of the entire buffer, causing flicker and unstable cursor movement.
- **IME:** Input Method Editor / keyboard input method (Windows layout state like English vs Hebrew).
- **O(1) insertion pattern:** Constant-time insertion per keystroke; here `{Home}` + `SendText(char)`.
