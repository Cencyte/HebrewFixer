; =============================================================================
; HebrewFixer - Affinity Designer BiDi workaround (Per-Key + Clipboard)
; =============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode("Input")
SetKeyDelay(-1, -1)

; -------------------- constants --------------------
global HF_VERSION := "0.9.0-dev"
; Increment this when debugging build/source mismatches.
global HF_BUILD_STAMP := "2026-02-15-mixed-script-token-algo-v2"
global HF_HEBREW_RE := "[\x{0590}-\x{05FF}]"  ; Hebrew Unicode range

; Unicode whitespace class (explicit list; avoid regex ranges which can fail to compile on some systems)
global HF_WSCLASS := "[ \t\x{00A0}\x{1680}\x{2000}\x{2001}\x{2002}\x{2003}\x{2004}\x{2005}\x{2006}\x{2007}\x{2008}\x{2009}\x{200A}\x{202F}\x{205F}\x{3000}]"

; Default toggle hotkey (store AHK syntax internally; show human string in UI)
global HF_DEFAULT_TOGGLE_HOTKEY_AHK := "^!h"
global HF_DEFAULT_TOGGLE_HOTKEY_HUMAN := "Ctrl+Alt+H"

; -------------------- runtime state --------------------
global g_Enabled := false
global g_Buffer := ""  ; (legacy)

; Debug feature: Undo buffer (Ctrl+Z sends the correct number of undos)
global g_UndoBufferEnabled := true  ; now integral (no toggle)
; Stack of undo "cost" per tracked keystroke:
; - 1 for normal keystrokes
; - 2 for RTL-injected Hebrew keystrokes (char + caret move)
global g_UndoStack := []
; Single-level redo snapshot for the debug undo buffer feature.
; When Ctrl+Z consumes the whole buffer, we save its costs here so Ctrl+Y can restore it.
global g_LastUndoSnapshot := []


global g_AutoEnable := true
global g_AutoEnableAllApps := false
global g_Whitelist := Map()  ; procName -> true

; When manual override is active, this is the preferred Enabled state when NOT focused on a whitelisted app.

global g_LastIMEState := false
; Last known global keyboard layout state as reported by WM_INPUTLANGCHANGE.
global g_LastKnownIsHebrew := IsHebrewHKL(DllCall("GetKeyboardLayout", "UInt", 0, "UPtr"))
global g_LastActiveHwnd := 0
; Manual toggle pause: after hotkey, polling is paused until focus changes.
global g_PollPaused := false
global g_PollPauseHwnd := 0

; Stable layout polling state (Option B: accept change after 2 consecutive polls)
global g_LastStableLangId := 0
global g_CandidateLangId := 0
global g_CandidateHits := 0

global g_NoTooltip := false

global g_ToggleHotkey := HF_DEFAULT_TOGGLE_HOTKEY_AHK

global g_CheckUpdatesOnStartup := true

global g_ConfigDir := ""
global g_ConfigIni := ""

global g_UpdateMenuLabel := ""

global g_GithubRepoUrl := "https://github.com/Cencyte/HebrewFixer"

; Hebrew keyboard layout mapping (US QWERTY physical keys → Hebrew chars)
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
    "f", "ך",
    "k", "ל",
    "n", "מ",
    "o", "ם",
    "b", "נ",
    "i", "ן",
    "x", "ס",
    "g", "ע",
    "p", "פ",
    ";", "ף",
    "m", "צ",
    ".", "ץ",
    "e", "ק",
    "r", "ר",
    "a", "ש",
    ",", "ת"
)

; =============================================================================
; INIT
; =============================================================================

InitConfigPaths()
LoadSettings()

for arg in A_Args {
    if (arg = "/NoTooltip" || arg = "-NoTooltip" || arg = "--NoTooltip") {
        g_NoTooltip := true
        continue
    }
    if (arg = "/exit" || arg = "-exit" || arg = "--exit") {
        DetectHiddenWindows(true)
        if WinExist("HebrewFixer ahk_class AutoHotkey")
            PostMessage(0x10, 0, 0)
        ExitApp()
    }
}

OnExit(CleanupBeforeExit)

; React instantly to keyboard layout changes (more reliable than polling alone)
OnMessage(0x51, WM_INPUTLANGCHANGE)  ; WM_INPUTLANGCHANGE

SetupTray()
RegisterToggleHotkey(g_ToggleHotkey)

if g_CheckUpdatesOnStartup
    SetTimer(CheckForUpdatesOnStartup, -750)

ShowTip("HebrewFixer loaded`n" . HotkeyHumanReadable(g_ToggleHotkey) . " to toggle", A_ScreenWidth // 2 - 160, 50, 2200)
SetTimer(CheckAutoEnable, 250)

CleanupBeforeExit(*) {
    SetTimer(CheckAutoEnable, 0)
}

; =============================================================================
; UI helpers
; =============================================================================

ShowTip(msg, x := unset, y := unset, durationMs := 1500) {
    global g_NoTooltip
    if g_NoTooltip
        return
    if IsSet(x) && IsSet(y)
        ToolTip(msg, x, y)
    else
        ToolTip(msg)
    SetTimer(() => ToolTip(), -durationMs)
}

LooksLikeHumanHotkey(s) {
    s := Trim(s)
    if (s = "")
        return false
    ; If it contains words like Ctrl/Alt/Shift/Win with + separators, treat as human.
    return RegExMatch(s, "i)\\b(ctrl|control|alt|shift|win|windows)\\b")
}

HotkeyHumanReadable(hk) {
    ; If it's already human-friendly, don't try to re-format.
    if LooksLikeHumanHotkey(hk)
        return hk

    s := Trim(hk)
    if (s = "")
        return ""

    mods := []

    ; Parse leading AHK modifier symbols (order-insensitive).
    while (StrLen(s) > 0) {
        ch := SubStr(s, 1, 1)
        if (ch = "^") {
            mods.Push("Ctrl")
        } else if (ch = "!") {
            mods.Push("Alt")
        } else if (ch = "+") {
            mods.Push("Shift")
        } else if (ch = "#") {
            mods.Push("Win")
        } else {
            break
        }
        s := SubStr(s, 2)
    }

    key := s
    if (key = "")
        key := "?"

    ; Normalize display casing
    if (StrLen(key) = 1)
        key := StrUpper(key)

    ; De-duplicate while preserving order
    seen := Map()
    out := ""
    for _, m in mods {
        if !seen.Has(m) {
            seen[m] := true
            out .= m . "+"
        }
    }

    return out . key
}

HumanHotkeyToAhk(human) {
    ; Accept: Ctrl+Alt+H, Control+Alt+H, Win+Shift+Z, etc.
    ; Also accept already-AHK-looking strings like ^!h.

    s := Trim(human)
    if (s = "")
        throw Error("Empty hotkey")

    ; If user already typed AHK syntax, accept it.
    ; (Human-friendly strings like "Alt+Shift+H" also contain "+", so only treat it as AHK
    ; if it *starts* with AHK modifier symbols.)
    if RegExMatch(s, "^[\^!\+#]")
        return s

    parts := StrSplit(s, "+")
    mods := ""
    key := ""

    for _, p in parts {
        p := Trim(p)
        if (p = "")
            continue

        pU := StrUpper(p)
        if (pU = "CTRL" || pU = "CONTROL") {
            if !InStr(mods, "^")
                mods .= "^"
            continue
        }
        if (pU = "ALT") {
            if !InStr(mods, "!")
                mods .= "!"
            continue
        }
        if (pU = "SHIFT") {
            if !InStr(mods, "+")
                mods .= "+"
            continue
        }
        if (pU = "WIN" || pU = "WINDOWS") {
            if !InStr(mods, "#")
                mods .= "#"
            continue
        }

        ; remainder is key
        key := p
    }

    if (key = "")
        throw Error("Missing key")

    ; Normalize some key names
    keyU := StrUpper(key)
    if (StrLen(key) = 1) {
        key := StrLower(key)
    } else if RegExMatch(keyU, "^F\d{1,2}$") {
        key := keyU
    } else if (keyU = "ESC" || keyU = "ESCAPE") {
        key := "Esc"
    } else if (keyU = "ENTER" || keyU = "RETURN") {
        key := "Enter"
    } else if (keyU = "TAB") {
        key := "Tab"
    } else if (keyU = "SPACE") {
        key := "Space"
    } else {
        ; Let AHK try to interpret it as a key name.
        key := key
    }

    return mods . key
}

CaptureHotkeyHuman(updateCtrl := "") {
    ; Records a shortcut as:
    ; - user may tap modifiers in any order (Ctrl/Alt/Shift/Win)
    ; - recording ends when a non-modifier key is pressed
    ; - Esc cancels

    ih := InputHook("L1")
    ih.KeyOpt("{All}", "E")
    ih.Timeout := 15

    ; Map EndKey -> canonical modifier name
    modMap := Map(
        "LShift", "Shift", "RShift", "Shift", "Shift", "Shift",
        "LCtrl", "Ctrl", "RCtrl", "Ctrl", "Ctrl", "Ctrl",
        "LAlt", "Alt", "RAlt", "Alt", "Alt", "Alt",
        "LWin", "Win", "RWin", "Win"
    )

    selected := Map()  ; canonical modifier -> true

    UpdatePreview(key := "") {
        if (updateCtrl = "")
            return
        order := ["Ctrl", "Alt", "Shift", "Win"]
        out := ""
        for _, m in order {
            if selected.Has(m)
                out .= m . "+"
        }
        if (key != "")
            out .= key
        updateCtrl.Value := out
    }

    UpdatePreview()

    Loop {
        ih.Start()
        ih.Wait()

        if (ih.EndReason = "Timeout")
            return ""

        k := ih.EndKey
        if (k = "Escape" || k = "Esc")
            return ""

        if modMap.Has(k) {
            m := modMap[k]
            ; Toggle modifier (tap again to remove)
            if selected.Has(m)
                selected.Delete(m)
            else
                selected[m] := true
            UpdatePreview()
            continue
        }

        ; Non-modifier key terminates recording.
        break
    }

    ; Normalize key name for display
    if (StrLen(k) = 1) {
        key := StrUpper(k)
    } else if (k = "Return") {
        key := "Enter"
    } else {
        key := k
    }

    ; Ordered modifiers for readability
    order := ["Ctrl", "Alt", "Shift", "Win"]
    out := ""
    for _, m in order {
        if selected.Has(m)
            out .= m . "+"
    }

    out := out . key
    UpdatePreview(key)
    return out
}

; =============================================================================
; CONFIG (EnvGet + UTF-8 INI normalization)
; =============================================================================

InitConfigPaths() {
    global g_ConfigDir, g_ConfigIni

    appData := EnvGet("APPDATA")
    localAppData := EnvGet("LOCALAPPDATA")

    ; prefer roaming
    g_ConfigDir := appData . "\HebrewFixer"

    try {
        if !DirExist(g_ConfigDir)
            DirCreate(g_ConfigDir)
        FileAppend("", g_ConfigDir . "\.write_test", "UTF-8")
        FileDelete(g_ConfigDir . "\.write_test")
    } catch {
        g_ConfigDir := localAppData . "\HebrewFixer"
        if !DirExist(g_ConfigDir)
            DirCreate(g_ConfigDir)
    }

    g_ConfigIni := g_ConfigDir . "\settings.ini"

    ; Migrate any legacy encodings and normalize to UTF-8 without BOM.
    NormalizeIniEncoding()

    try FileAppend("[" . FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") . "] ConfigDir=" . g_ConfigDir . " | Ini=" . g_ConfigIni . "`n", g_ConfigDir . "\hf_startup.log", "UTF-8")
}

LoadSettings() {
    global g_ConfigIni
    global g_AutoEnable, g_AutoEnableAllApps, g_ToggleHotkey, g_CheckUpdatesOnStartup

    firstRun := !FileExist(g_ConfigIni)

    g_AutoEnable := IniRead(g_ConfigIni, "General", "AutoEnable", "1") = "1"
    g_AutoEnableAllApps := IniRead(g_ConfigIni, "General", "AutoEnableAllApps", "0") = "1"

    hkRaw := IniRead(g_ConfigIni, "General", "ToggleHotkey", HF_DEFAULT_TOGGLE_HOTKEY_AHK)
    ; Migration: if the INI contains a human-style hotkey (Ctrl+Alt+H), convert it to AHK syntax.
    try {
        g_ToggleHotkey := LooksLikeHumanHotkey(hkRaw) ? HumanHotkeyToAhk(hkRaw) : hkRaw
    } catch {
        g_ToggleHotkey := HF_DEFAULT_TOGGLE_HOTKEY_AHK
    }

    g_CheckUpdatesOnStartup := IniRead(g_ConfigIni, "General", "CheckUpdatesOnStartup", "1") = "1"

    LoadWhitelistFromIni()

    if firstRun {
        SaveSettings()
    } else {
        ; If we migrated the hotkey, persist it in AHK syntax.
        if (g_ToggleHotkey != hkRaw)
            SaveSettings()
    }
}

SaveSettings() {
    global g_ConfigIni
    global g_AutoEnable, g_AutoEnableAllApps, g_ToggleHotkey, g_CheckUpdatesOnStartup

    IniWrite(g_AutoEnable ? "1" : "0", g_ConfigIni, "General", "AutoEnable")
    IniWrite(g_AutoEnableAllApps ? "1" : "0", g_ConfigIni, "General", "AutoEnableAllApps")
    IniWrite(g_ToggleHotkey, g_ConfigIni, "General", "ToggleHotkey")
    IniWrite(g_CheckUpdatesOnStartup ? "1" : "0", g_ConfigIni, "General", "CheckUpdatesOnStartup")

    SaveWhitelistToIni()

    ; keep human-editable
    NormalizeIniEncoding()
}

LoadWhitelistFromIni() {
    global g_ConfigIni, g_Whitelist
    g_Whitelist := Map()

    raw := IniRead(g_ConfigIni, "Whitelist", "Processes", "")
    raw := StrReplace(raw, "`r", "")

    for _, line in StrSplit(raw, "`n") {
        p := Trim(line)
        if (p != "")
            g_Whitelist[p] := true
    }

    ; Defaults (no-config). Also include Sara's Designer.exe
    ; (installed at C:\Program Files\Affinity\Designer\Designer.exe)
    if (g_Whitelist.Count = 0) {
        g_Whitelist["AffinityDesigner.exe"] := true
        g_Whitelist["AffinityPhoto.exe"] := true
        g_Whitelist["AffinityPublisher.exe"] := true
        g_Whitelist["Designer.exe"] := true
    } else {
        ; Non-destructive migration: ensure Designer.exe is present for Sara.
        if !g_Whitelist.Has("Designer.exe")
            g_Whitelist["Designer.exe"] := true
    }
}

SaveWhitelistToIni() {
    global g_ConfigIni, g_Whitelist
    raw := ""
    for proc, _ in g_Whitelist
        raw .= proc . "`n"
    raw := RTrim(raw, "`n")
    IniWrite(raw, g_ConfigIni, "Whitelist", "Processes")
}

; Ensure settings.ini is UTF-8 without BOM (and convert UTF-16LE if needed).
NormalizeIniEncoding() {
    global g_ConfigIni

    if !FileExist(g_ConfigIni)
        return

    try buf := FileRead(g_ConfigIni, "RAW")
    catch {
        return
    }

    ; detect UTF-16LE by NUL bytes
    isUtf16 := false
    Loop buf.Size {
        if (NumGet(buf, A_Index - 1, "UChar") = 0) {
            isUtf16 := true
            break
        }
    }

    try txt := isUtf16 ? StrGet(buf, "UTF-16") : StrGet(buf, "UTF-8")
    catch {
        return
    }

    ; Strip any leading U+FEFF characters
    while (SubStr(txt, 1, 1) = Chr(0xFEFF))
        txt := SubStr(txt, 2)

    ; For UTF-8, also strip repeated UTF-8 BOM bytes if present.
    if !isUtf16 {
        start := 0
        while (buf.Size - start >= 3
            && NumGet(buf, start, "UChar") = 0xEF
            && NumGet(buf, start+1, "UChar") = 0xBB
            && NumGet(buf, start+2, "UChar") = 0xBF) {
            start += 3
        }
        if (start > 0) {
            try txt := StrGet(SubBuffer(buf, start, buf.Size - start), "UTF-8")
            catch {
                return
            }
            while (SubStr(txt, 1, 1) = Chr(0xFEFF))
                txt := SubStr(txt, 2)
        }
    }

    ; Write back as UTF-8 without BOM.
    try {
        FileDelete(g_ConfigIni)
        FileAppend(txt, g_ConfigIni, "UTF-8-RAW")
    } catch {
        return
    }
}

SubBuffer(buf, offset, size) {
    nb := Buffer(size)
    DllCall("RtlMoveMemory", "Ptr", nb.Ptr, "Ptr", buf.Ptr + offset, "UPtr", size)
    return nb
}

; =============================================================================
; TRAY + SETTINGS
; =============================================================================

SetupTray() {
    A_TrayMenu.Delete()

    A_TrayMenu.Add("Toggle Hebrew RTL (" . HotkeyHumanReadable(g_ToggleHotkey) . ")", (*) => ToggleMode())
    A_TrayMenu.Add()

    A_TrayMenu.Add("Auto-enable on Hebrew keyboard", (*) => ToggleAutoEnable())
    A_TrayMenu.Add("Settings…", (*) => ShowSettingsGui())

    A_TrayMenu.Add()
    A_TrayMenu.Add("Copy diagnostic info", (*) => CopyDiagnosticInfo())

    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", (*) => ExitApp())

    UpdateTray()
}

UpdateTray() {
    global g_Enabled, g_AutoEnable, g_AutoEnableAllApps

    if g_AutoEnable
        A_TrayMenu.Check("Auto-enable on Hebrew keyboard")
    else
        A_TrayMenu.Uncheck("Auto-enable on Hebrew keyboard")

    ; (Tray menu no longer includes "Auto-enable: All apps"; setting remains in Settings GUI)

    A_IconTip := "HebrewFixer: " . (g_Enabled ? "ON" : "OFF")
    if g_AutoEnable
        A_IconTip .= " [Auto" . (g_AutoEnableAllApps ? ":All]" : ":Whitelist]")

    ; When running as a raw .ahk script, the icon isn't embedded like the compiled EXE.
    ; Use repo icons (relative to this file: src\Current Version -> ..\..\Icon\ICOs).
    iconDir := A_ScriptDir . "\\..\\..\\Icon\\ICOs\\"

    ; Prefer Affinity-branded icons.
    onIco := iconDir . "hebrew_fixer_affinity_on.ico"
    offIco := iconDir . "hebrew_fixer_affinity_off.ico"
    ; Fallback to generic icons if needed.
    if !FileExist(onIco)
        onIco := iconDir . "hebrew_fixer_on.ico"
    if !FileExist(offIco)
        offIco := iconDir . "hebrew_fixer_off.ico"

    try TraySetIcon(g_Enabled ? onIco : offIco)
    catch {
        ; ignore
    }
}

ToggleAutoEnable() {
    global g_AutoEnable
    g_AutoEnable := !g_AutoEnable
    SaveSettings()
    UpdateTray()
}

ToggleAllApps() {
    global g_AutoEnableAllApps
    g_AutoEnableAllApps := !g_AutoEnableAllApps
    SaveSettings()
    UpdateTray()
}

ClearUndoBuffer() {
    global g_UndoStack, g_LastUndoSnapshot
    g_UndoStack := []
    g_LastUndoSnapshot := []
}

TrackUndoKey(paired := false) {
    global g_UndoBufferEnabled, g_UndoStack, g_LastUndoSnapshot
    if !g_UndoBufferEnabled
        return

    ; Any new typing invalidates redo snapshot.
    g_LastUndoSnapshot := []

    g_UndoStack.Push(paired ? 2 : 1)
}

; Keep boundary hook as a no-op tracker (boundaries are still keystrokes)
TrackUndoBoundary() {
    TrackUndoKey(false)
}


ShowSettingsGui() {
    global g_AutoEnable, g_AutoEnableAllApps, g_Whitelist, g_ToggleHotkey, g_CheckUpdatesOnStartup

    settingsGui := Gui("+MinSize420x360", "HebrewFixer Settings")
    settingsGui.SetFont("s9")

    settingsGui.AddText("xm ym", "Toggle hotkey:")
    ; Accept either AHK syntax (^!h) or human format (Ctrl+Alt+H)
    hotkeyEdit := settingsGui.AddEdit("x+10 yp-2 w200", HotkeyHumanReadable(g_ToggleHotkey))
    btnRecord := settingsGui.AddButton("x+6 yp-1 w90", "Record…")
    settingsGui.AddText("xm y+6 c606060", "Tip: click Record…, then press your shortcut (Esc cancels).")

    cbAuto := settingsGui.AddCheckbox("xm y+14", "Auto-enable on Hebrew keyboard")
    cbAuto.Value := g_AutoEnable

    cbAll := settingsGui.AddCheckbox("xm y+6", "All apps (ignore whitelist)")
    cbAll.Value := g_AutoEnableAllApps

    cbUpd := settingsGui.AddCheckbox("xm y+10", "Check for updates on startup")
    cbUpd.Value := g_CheckUpdatesOnStartup

    settingsGui.AddText("xm y+16", "Whitelist (process names like AffinityDesigner.exe):")
    lv := settingsGui.AddListView("xm y+6 w400 r8", ["Process"])
    for proc, _ in g_Whitelist
        lv.Add(, proc)
    lv.ModifyCol(1, 380)

    btnAdd := settingsGui.AddButton("xm y+10 w90", "Add")
    btnRemove := settingsGui.AddButton("x+6 yp w90", "Remove")
    btnSave := settingsGui.AddButton("xm y+14 w90 Default", "Save")
    btnCancel := settingsGui.AddButton("x+6 yp w90", "Cancel")

    btnAdd.OnEvent("Click", (*) => (
        ib := InputBox("Enter process name (e.g. AffinityDesigner.exe):", "Add whitelist entry"),
        (ib.Result = "OK" && Trim(ib.Value) != "") ? lv.Add(, Trim(ib.Value)) : 0
    ))

    btnRemove.OnEvent("Click", (*) => (
        row := lv.GetNext(0),
        row ? lv.Delete(row) : 0
    ))

    btnRecord.OnEvent("Click", (*) => (
        hk := CaptureHotkeyHuman(hotkeyEdit),
        (hk != "") ? (hotkeyEdit.Value := hk) : 0
    ))

    btnSave.OnEvent("Click", (*) => (
        SettingsGuiSave(settingsGui, hotkeyEdit, cbAuto, cbAll, cbUpd, lv)
    ))
    btnCancel.OnEvent("Click", (*) => settingsGui.Destroy())

    settingsGui.Show()
}

SettingsGuiSave(settingsGui, hotkeyEdit, cbAuto, cbAll, cbUpd, lv) {
    global g_AutoEnable, g_AutoEnableAllApps, g_CheckUpdatesOnStartup
    global g_Whitelist

    newHotkeyHuman := Trim(hotkeyEdit.Value)
    if (newHotkeyHuman = "")
        newHotkeyHuman := HF_DEFAULT_TOGGLE_HOTKEY_HUMAN

    ; Convert human-friendly (Ctrl+Alt+H) to AHK syntax (^!h).
    newHotkey := HumanHotkeyToAhk(newHotkeyHuman)

    g_AutoEnable := cbAuto.Value = 1
    g_AutoEnableAllApps := cbAll.Value = 1
    g_CheckUpdatesOnStartup := cbUpd.Value = 1

    newWL := Map()
    Loop lv.GetCount() {
        p := Trim(lv.GetText(A_Index, 1))
        if (p != "")
            newWL[p] := true
    }
    if (newWL.Count = 0) {
        newWL["AffinityDesigner.exe"] := true
        newWL["AffinityPhoto.exe"] := true
        newWL["AffinityPublisher.exe"] := true
        newWL["Designer.exe"] := true
    }
    g_Whitelist := newWL

    try {
        RegisterToggleHotkey(newHotkey)
    } catch as e {
        MsgBox("Invalid hotkey: " . newHotkeyHuman . "`n`n" . e.Message, "HebrewFixer", "Iconx")
        return
    }

    SaveSettings()
    SetupTray()  ; rebuild tray menu so the hotkey label updates immediately
    settingsGui.Destroy()
}

; =============================================================================
; HOTKEY REGISTRATION
; =============================================================================

RegisterToggleHotkey(newHotkey) {
    global g_ToggleHotkey

    if (g_ToggleHotkey != "") {
        try Hotkey(g_ToggleHotkey, "Off")
    }

    g_ToggleHotkey := newHotkey
    Hotkey(g_ToggleHotkey, (*) => ToggleMode(), "On")
}

; =============================================================================
; WINDOW / IME
; =============================================================================

IsAffinityActive() {
    ; Whitelist-driven gating.
    ; Note: Sara's Affinity Designer is installed at:
    ;   C:\Program Files\Affinity\Designer\Designer.exe
    ; which appears as the process name "Designer.exe".
    global g_Whitelist

    proc := GetActiveProcessName()
    return (proc != "" && g_Whitelist.Has(proc))
}

GetActiveProcessName() {
    try {
        hwnd := WinExist("A")
        if !hwnd
            return ""
        return WinGetProcessName("ahk_id " . hwnd)
    } catch {
        return ""
    }
}

GetActiveWindowTitle() {
    try {
        hwnd := WinExist("A")
        if !hwnd
            return ""
        return WinGetTitle("ahk_id " . hwnd)
    } catch {
        return ""
    }
}

IsAutoEnableAllowedForActiveApp() {
    global g_AutoEnableAllApps, g_Whitelist

    if g_AutoEnableAllApps
        return true

    proc := GetActiveProcessName()
    if (proc = "")
        return false

    return g_Whitelist.Has(proc)
}

IsHebrewHKL(hkl) {
    try {
        langId := hkl & 0xFFFF
        return (langId = 0x040D)
    } catch {
        return false
    }
}

; Foreground HKL polling was causing Notepad-specific layout discrepancies.
; We keep keyboard polling but base it on the script thread HKL instead.
GetForegroundHKL() {
    try {
        hwnd := DllCall("GetForegroundWindow", "Ptr")
        if !hwnd
            return 0
        tid := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
        return DllCall("GetKeyboardLayout", "UInt", tid, "UPtr")
    } catch {
        return 0
    }
}

GetForegroundLangId() {
    hkl := GetForegroundHKL()
    return hkl & 0xFFFF
}

IsHebrewKeyboard() {
    ; Poll-based source of truth: foreground thread layout.
    return (GetForegroundLangId() = 0x040D)
}

; WM_INPUTLANGCHANGE handler kept, but auto-enable is primarily polling-driven.
WM_INPUTLANGCHANGE(wParam, lParam, msg, hwnd) {
    ; Fires when keyboard layout changes. lParam is the new HKL.
    ; Force this script thread to adopt the layout so GetKeyboardLayout(0) polling is correct.
    global g_LastIMEState, g_LastKnownIsHebrew

    try DllCall("ActivateKeyboardLayout", "Ptr", lParam, "UInt", 0)

    g_LastKnownIsHebrew := IsHebrewHKL(lParam)
    g_LastIMEState := g_LastKnownIsHebrew

    ; No state flip here; polling loop owns enable/disable.
}

; =============================================================================
; AUTO ENABLE
; =============================================================================

CheckAutoEnable() {
    ; Poll-driven state machine.
    ; Manual toggle pauses polling until focus changes.
    global g_AutoEnable, g_Enabled
    global g_PollPaused, g_PollPauseHwnd
    global g_LastActiveHwnd
    global g_LastStableLangId, g_CandidateLangId, g_CandidateHits

    if !g_AutoEnable
        return

    hwnd := WinExist("A")

    ; If paused, only resume when focus changes.
    if g_PollPaused {
        if (hwnd && hwnd != g_PollPauseHwnd) {
            g_PollPaused := false
            g_PollPauseHwnd := 0
        } else {
            return
        }
    }

    ; Stable keyboard-layout polling (2 consecutive polls required).
    ; Poll foreground layout (stable-for-2-polls)
    lang := GetForegroundLangId()
    if (g_LastStableLangId = 0) {
        g_LastStableLangId := lang
        g_CandidateLangId := 0
        g_CandidateHits := 0
    } else if (lang != g_LastStableLangId) {
        if (g_CandidateLangId = lang) {
            g_CandidateHits += 1
        } else {
            g_CandidateLangId := lang
            g_CandidateHits := 1
        }

        if (g_CandidateHits >= 2) {
            old := g_LastStableLangId
            g_LastStableLangId := lang
            g_CandidateLangId := 0
            g_CandidateHits := 0
            try DebugLog("LangStable: " . Format("0x{:04X}", old) . " -> " . Format("0x{:04X}", lang) . " proc=" . GetActiveProcessName())
        }
    } else {
        g_CandidateLangId := 0
        g_CandidateHits := 0
    }

    isHeb := (g_LastStableLangId = 0x040D)

    ; Enforce invariant: enabled follows stable keyboard state.
    desired := isHeb

    if (g_Enabled != desired) {
        g_Enabled := desired
        UpdateTray()
    }

    g_LastActiveHwnd := hwnd
}


ToggleMode() {
    global g_Enabled, g_AutoEnable
    global g_PollPaused, g_PollPauseHwnd

    g_Enabled := !g_Enabled

    ; Manual toggle = pause polling until focus changes.
    if g_AutoEnable {
        g_PollPaused := true
        g_PollPauseHwnd := WinExist("A")
    }

    UpdateTray()
    ShowTip("Hebrew RTL: " . (g_Enabled ? "ON" : "OFF"), A_ScreenWidth // 2 - 80, 50, 1200)
}

; =============================================================================
; PER-KEY RTL TYPING (Affinity only)
; =============================================================================

HandleHebrewKey(physicalKey) {
    global HebrewMap
    global g_UndoBufferEnabled

    if !HebrewMap.Has(physicalKey)
        return

    ; Never interfere with application shortcuts.
    ; If Ctrl or Alt is physically down, pass through the keystroke unchanged.
    if GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P") {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}" . physicalKey)
        return
    }

    ; If not Hebrew keyboard, pass through as a normal keystroke.
    if !IsHebrewKeyboard() {
        Send("{Blind}" . physicalKey)
        TrackUndoKey(false)
        return
    }

    ; Respect Shift+Letter to allow typing Latin uppercase while Hebrew keyboard is active.
    ; This is important for mixed RTL/LTR strings.
    if GetKeyState("Shift", "P") && RegExMatch(physicalKey, "^[a-z]$") {
        Send("{Blind}" . physicalKey)   ; Shift will produce uppercase
        SendInput("{Left}")
        TrackUndoKey(true)
        return
    }

    hebrewChar := HebrewMap[physicalKey]
    SendInput("{Raw}" . hebrewChar)
    SendInput("{Left}")

    TrackUndoKey(true)
}

HandleBackspace() {
    if !IsHebrewKeyboard() {
        Send("{BS}")
        return
    }
    Send("{Delete}")
}

HandleDelete() {
    if !IsHebrewKeyboard() {
        Send("{Delete}")
        return
    }
    Send("{BS}")
}

; =============================================================================
; DEBUG LOG (silent)
; =============================================================================

ShouldBypassShortcuts() {
    return GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P")
}

global g_LastTransformStage := ""

SetTransformStage(s) {
    global g_LastTransformStage
    g_LastTransformStage := s
}

DebugLog(msg) {
    global g_ConfigDir
    try {
        line := "[" . FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") . "] " . msg . "`n"
        FileAppend(line, g_ConfigDir . "\\hf_debug.log", "UTF-8")
    } catch {
        ; ignore
    }
}

; =============================================================================
; CLIPBOARD TRANSFORM (multi-line)
; =============================================================================

ClipboardContainsHebrew(text) {
    global HF_HEBREW_RE
    return RegExMatch(text, HF_HEBREW_RE)
}

FixBidiPastePerLine(text) {
    ; For each line:
    ; 1) reverse token order (word-level)
    ; 2) reverse Hebrew character order within tokens (run-level) so Affinity displays letters correctly
    ; This combination is involutive (applying it again returns original).

    text := StrReplace(text, "`r`n", "`n")
    text := StrReplace(text, "`r", "`n")

    lines := StrSplit(text, "`n", false)
    out := ""

    for idx, line in lines {
        out .= FixBidiPasteLine(line)
        if (idx < lines.Length)
            out .= "`n"
    }

    return out
}

FixBidiPasteLine(line) {
    SetTransformStage("FixBidiPasteLine:start")
    ; Mixed-script handling:
    ; If the line contains any Latin letters, we DO NOT reverse token order.
    ; Reversing token order in mixed Hebrew+English tends to produce mirrored sentence-level swaps.
    ; In that case we only fix Hebrew letter order inside Hebrew runs (run-level reversal).
    SetTransformStage("FixBidiPasteLine:latinCheck")
    if RegExMatch(line, "[A-Za-z]") {
        ; Mixed Latin+Hebrew: do NOT use full token reversal or Windows BiDi.
        ; Use HebrewFixer mixed-script token algorithm:
        ; - preserve whitespace
        ; - reverse Hebrew runs within tokens
        ; - reverse order of Hebrew tokens only within Hebrew-token runs
        ; - apply a narrow boundary repair for the common pattern: <Latin><Hebrew> + <Hebrew><Latin>
        SetTransformStage("FixBidiPasteLine:MixedScriptTokenAlgo")
        return FixMixedScriptLine(line)
    }

    ; Otherwise (Hebrew-only / no Latin), reverse token order per line while preserving whitespace,
    ; and also fix letter order inside Hebrew runs within each token.

    wsClass := HF_WSCLASS

    if RegExMatch(line, "^(" . wsClass . "*)(.*?)((?:" . wsClass . ")*)$", &m) {
        lead := m[1], core := m[2], trail := m[3]
    } else {
        lead := "", core := line, trail := ""
    }

    ; If core has no non-whitespace characters, return original.
    if !RegExMatch(core, "[^ \t\x{00A0}\x{1680}\x{2000}\x{2001}\x{2002}\x{2003}\x{2004}\x{2005}\x{2006}\x{2007}\x{2008}\x{2009}\x{200A}\x{202F}\x{205F}\x{3000}]")
        return line

    tokens := []
    seps := []  ; whitespace following each token

    pos := 1
    pat := "([^ \t\x{00A0}\x{1680}\x{2000}\x{2001}\x{2002}\x{2003}\x{2004}\x{2005}\x{2006}\x{2007}\x{2008}\x{2009}\x{200A}\x{202F}\x{205F}\x{3000}]+)(" . wsClass . "*)"
    while RegExMatch(core, pat, &mm, pos) {
        tokens.Push(mm[1])
        seps.Push(mm[2])
        pos := mm.Pos[0] + mm.Len[0]
    }

    if (tokens.Length <= 1) {
        ; Still fix letter-order inside the single token, but keep whitespace untouched.
        fixed := FixTokenRTL(tokens.Length = 1 ? tokens[1] : core)
        return lead . fixed . (seps.Length ? seps[seps.Length] : "") . trail
    }

    trailingSep := seps[seps.Length]
    seps.Pop()

    out := ""
    Loop tokens.Length {
        tok := tokens[tokens.Length - A_Index + 1]
        tok := FixTokenRTL(tok)
        out .= tok
        if (A_Index < tokens.Length) {
            sepIdx := seps.Length - A_Index + 1
            out .= seps[sepIdx]
        }
    }
    out .= trailingSep

    return lead . out . trail
}

ReverseStringSimple(s) {
    out := ""
    i := StrLen(s)
    while (i >= 1) {
        out .= SubStr(s, i, 1)
        i -= 1
    }
    return out
}

FixTokenRTL(tok) {
    ; Fix a single token for RTL display in a non-BiDi renderer.
    ; - Hebrew letters: reverse inside Hebrew runs
    ; - Digits: keep digit run order ("34" stays "34")
    ; - Punctuation: considered RTL-affecting (moves with Hebrew/digits)
    ; - Latin letters: treated as LTR anchors (do not reorder across Hebrew)

    if (tok = "")
        return tok

    ; Build runs: {kind, text}
    runs := []
    i := 1
    while (i <= StrLen(tok)) {
        ch := SubStr(tok, i, 1)
        kind := "punct"
        if IsHebrewChar(ch)
            kind := "heb"
        else if RegExMatch(ch, "[0-9]")
            kind := "digit"
        else if RegExMatch(ch, "[A-Za-z]")
            kind := "latin"

        j := i
        while (j <= StrLen(tok)) {
            ch2 := SubStr(tok, j, 1)
            kind2 := "punct"
            if IsHebrewChar(ch2)
                kind2 := "heb"
            else if RegExMatch(ch2, "[0-9]")
                kind2 := "digit"
            else if RegExMatch(ch2, "[A-Za-z]")
                kind2 := "latin"
            if (kind2 != kind)
                break
            j += 1
        }

        txt := SubStr(tok, i, j - i)
        runs.Push({k: kind, t: txt})
        i := j
    }

    ; Reverse Hebrew letters inside heb runs
    for idx, r in runs {
        if (r.k = "heb")
            r.t := ReverseStringSimple(r.t)
        runs[idx] := r
    }

    ; Reorder runs: reverse the sequence of RTL-affecting runs (heb/digit/punct) as a whole,
    ; but keep latin runs anchored in place.
    rtlIdx := []
    for idx, r in runs {
        if (r.k != "latin")
            rtlIdx.Push(idx)
    }

    a := 1
    b := rtlIdx.Length
    while (a < b) {
        ia := rtlIdx[a], ib := rtlIdx[b]
        tmp := runs[ia]
        runs[ia] := runs[ib]
        runs[ib] := tmp
        a += 1
        b -= 1
    }

    out := ""
    for _, r in runs
        out .= r.t
    return out
}

ReverseHebrewRuns(s) {
    ; Reverse characters only within contiguous Hebrew runs, using codepoint checks (no regex ranges).
    out := ""
    i := 1
    while (i <= StrLen(s)) {
        ch := SubStr(s, i, 1)
        if IsHebrewChar(ch) {
            j := i
            while (j <= StrLen(s) && IsHebrewChar(SubStr(s, j, 1)))
                j += 1
            run := SubStr(s, i, j - i)
            ; reverse run
            k := StrLen(run)
            while (k >= 1) {
                out .= SubStr(run, k, 1)
                k -= 1
            }
            i := j
        } else {
            out .= ch
            i += 1
        }
    }
    return out
}

FixMixedScriptLine(line) {
    ; Mixed-script token algorithm (for lines containing Latin letters):
    ; - preserve whitespace exactly
    ; - narrow boundary repair for <LatinPrefix><HebrewTail> + <HebrewChar><LatinRun>
    ; - reverse Hebrew runs within tokens
    ; IMPORTANT: no token reordering for mixed-script lines

    global HF_WSCLASS
    wsClass := HF_WSCLASS
    wsChars := SubStr(wsClass, 2, StrLen(wsClass) - 2)  ; strip surrounding [ ]

    tokens := []
    seps := []

    pos := 1
    pat := "([^" . wsChars . "]+)([" . wsChars . "]*)"
    while RegExMatch(line, pat, &m, pos) {
        tokens.Push(m[1])
        seps.Push(m[2])
        pos := m.Pos[0] + m.Len[0]
    }

    if (tokens.Length = 0)
        return line

    ; Boundary repair: if token[i] is LatinPrefix+HebTail (all Hebrew) and token[i+1] is HebChar+LatinRun,
    ; move the HebChar into token[i] after the LatinPrefix, and leave token[i+1] as LatinRun.
    Loop tokens.Length - 1 {
        iTok := A_Index
        t1 := tokens[iTok]
        t2 := tokens[iTok+1]

        if RegExMatch(t1, "^([A-Za-z]{2,})(.+)$", &m1) {
            latinPrefix := m1[1]
            hebTail := m1[2]

            allHeb := true
            k := 1
            while (k <= StrLen(hebTail)) {
                if !IsHebrewChar(SubStr(hebTail, k, 1)) {
                    allHeb := false
                    break
                }
                k += 1
            }

            if allHeb {
                if (StrLen(t2) >= 2 && IsHebrewChar(SubStr(t2, 1, 1))) {
                    heb1 := SubStr(t2, 1, 1)
                    rest := SubStr(t2, 2)
                    if RegExMatch(rest, "^[A-Za-z]+$") {
                        ; IMPORTANT mixed-script boundary repair:
                        ; Split into: <LatinPrefix><Heb1>  and  <HebTail><LatinRun>
                        ; This yields e.g. "FFF" + "ד" and "םםםדדגללל" + "D".
                        tokens[iTok] := latinPrefix . heb1
                        tokens[iTok+1] := hebTail . rest
                    }
                }
            }
        }
    }

    ; Reverse Hebrew runs within tokens
    ; Also log before/after for the first few tokens to prove the reversal is happening.
    Loop Min(3, tokens.Length) {
        idx := A_Index
        before := tokens[idx]
        after := FixTokenRTL(before)
        tokens[idx] := after

        if (before != after)
            DebugLog("MixedScript tok" . idx . " before=" . before . " | after=" . after)
        else if ClipboardContainsHebrew(before)
            DebugLog("MixedScript tok" . idx . " contains Hebrew but did not change (check IsHebrewChar/ReverseHebrewRuns)")
    }

    ; Apply reversal for remaining tokens
    if (tokens.Length > 3) {
        i := 4
        while (i <= tokens.Length) {
            tokens[i] := ReverseHebrewRuns(tokens[i])
            i += 1
        }
    }

    out := ""
    Loop tokens.Length {
        out .= tokens[A_Index]
        if (A_Index <= seps.Length)
            out .= seps[A_Index]
    }

    return out
}



IsHebrewChar(ch) {
    code := Ord(ch)
    return (code >= 0x0590 && code <= 0x05FF)
}

ReverseString(s) {
    chars := StrSplit(s)
    out := ""
    Loop chars.Length {
        out .= chars[chars.Length - A_Index + 1]
    }
    return out
}

; =============================================================================
; HOTKEYS (Affinity only, enabled)
; =============================================================================

#HotIf g_Enabled && IsAutoEnableAllowedForActiveApp()
; (Per-key typing / navigation / undo-buffer remain whitelisted-only)


; Mouse click likely changes selection/caret; clear undo buffer.
~LButton::{
    global g_UndoBufferEnabled
    if g_UndoBufferEnabled
        ClearUndoBuffer()
}

; Home/End/PageUp/PageDown and other navigation keys can be idempotent; clear buffer.
; We override Home/End below to swap for RTL; keep PgUp/PgDn as passthrough invalidators.
~PgUp::(g_UndoBufferEnabled ? ClearUndoBuffer() : 0)
~PgDn::(g_UndoBufferEnabled ? ClearUndoBuffer() : 0)

; Home/End navigation should respect RTL direction.
; Note: some keyboards send NumpadHome/NumpadEnd when NumLock is off.
HandleHomeEndCombo(navKey, ctrl := false, shift := false) {
    global g_UndoBufferEnabled
    if g_UndoBufferEnabled
        ClearUndoBuffer()

    heb := IsHebrewKeyboard()
    DebugLog("HomeEnd combo: key=" . navKey . " ctrl=" . (ctrl?"1":"0") . " shift=" . (shift?"1":"0") . " heb=" . (heb?"1":"0"))

    target := navKey
    if heb {
        if (navKey = "Home")
            target := "End"
        else if (navKey = "End")
            target := "Home"
    }

    prefix := "{Blind}"
    if ctrl
        prefix .= "^"
    if shift
        prefix .= "+"

    Send(prefix . "{" . target . "}")
}

$Home::HandleHomeEndCombo("Home")
$End::HandleHomeEndCombo("End")
$NumpadHome::HandleHomeEndCombo("Home")
$NumpadEnd::HandleHomeEndCombo("End")

$^Home::HandleHomeEndCombo("Home", true, false)
$^End::HandleHomeEndCombo("End", true, false)
$^NumpadHome::HandleHomeEndCombo("Home", true, false)
$^NumpadEnd::HandleHomeEndCombo("End", true, false)

$+Home::HandleHomeEndCombo("Home", false, true)
$+End::HandleHomeEndCombo("End", false, true)
$+NumpadHome::HandleHomeEndCombo("Home", false, true)
$+NumpadEnd::HandleHomeEndCombo("End", false, true)

$^+Home::HandleHomeEndCombo("Home", true, true)
$^+End::HandleHomeEndCombo("End", true, true)
$^+NumpadHome::HandleHomeEndCombo("Home", true, true)
$^+NumpadEnd::HandleHomeEndCombo("End", true, true)

; Function keys: untracked, but F1 and F10 invalidate because they change UI interaction mode.
~F1::(g_UndoBufferEnabled ? ClearUndoBuffer() : 0)
~F10::(g_UndoBufferEnabled ? ClearUndoBuffer() : 0)

; Modifiers alone do NOT invalidate. We only invalidate on specific risky actions (mouse/nav/edit)
; and on function keys that alter UI state (F1/F10), including modifier+F1/F10 combos.

; per-key mappings
$*a::HandleHebrewKey("a")
$*b::HandleHebrewKey("b")
$*c::HandleHebrewKey("c")
$*d::HandleHebrewKey("d")
$*e::HandleHebrewKey("e")
$*f::HandleHebrewKey("f")
$*g::HandleHebrewKey("g")
$*h::HandleHebrewKey("h")
$*i::HandleHebrewKey("i")
$*j::HandleHebrewKey("j")
$*k::HandleHebrewKey("k")
$*l::HandleHebrewKey("l")
$*m::HandleHebrewKey("m")
$*n::HandleHebrewKey("n")
$*o::HandleHebrewKey("o")
$*p::HandleHebrewKey("p")
$*r::HandleHebrewKey("r")
$*s::HandleHebrewKey("s")
$*t::HandleHebrewKey("t")
$*u::HandleHebrewKey("u")
$*v::HandleHebrewKey("v")
$*x::HandleHebrewKey("x")
$*y::HandleHebrewKey("y")
$*z::HandleHebrewKey("z")
$,::HandleHebrewKey(",")
$.::HandleHebrewKey(".")
$;::HandleHebrewKey(";")

$*q::{
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}q")
        return
    }
    Send("{Blind}q")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*w::{
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}w")
        return
    }
    Send("{Blind}w")
    if g_UndoBufferEnabled
        TrackUndoKey()
}

; Digits & common punctuation: track as non-paired.
$*1:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}1")
        return
    }

    Send("{Blind}1")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*2:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}2")
        return
    }

    Send("{Blind}2")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*3:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}3")
        return
    }

    Send("{Blind}3")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*4:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}4")
        return
    }

    Send("{Blind}4")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*5:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}5")
        return
    }

    Send("{Blind}5")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*6:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}6")
        return
    }

    Send("{Blind}6")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*7:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}7")
        return
    }

    Send("{Blind}7")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*8:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}8")
        return
    }

    Send("{Blind}8")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*9:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}9")
        return
    }

    Send("{Blind}9")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*0:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}0")
        return
    }

    Send("{Blind}0")
    if g_UndoBufferEnabled
        TrackUndoKey()
}

$*-:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}-")
        return
    }

    Send("{Blind}-")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*=:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}=")
        return
    }

    Send("{Blind}=")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*[:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}[")
        return
    }

    Send("{Blind}[")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*]:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}]")
        return
    }

    Send("{Blind}]")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*\:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}\")
        return
    }

    Send("{Blind}\\")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*':: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}/")
        return
    }

    Send("{Blind}'")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
$*/:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}{Text}``")
        return
    }

    Send("{Blind}/")
    if g_UndoBufferEnabled
        TrackUndoKey()
}
; Backtick/tilde key tracking: use scancode to avoid escaping issues.
$*SC029:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        ; Let app shortcuts like Ctrl+` pass through
        Send("{Blind}{Text}``")
        return
    }
    ; Send a literal backtick. Shift+SC029 will produce ~ naturally due to {Blind}.
    Send("{Blind}{Text}``")
    if g_UndoBufferEnabled
        TrackUndoKey()
}

; Comma/period/semicolon are already handled via HebrewMap physical keys (, . ;) above.

; Enter and Tab: track as non-paired (do NOT invalidate buffer).
$Enter:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}{Enter}")
        return
    }
    Send("{Blind}{Enter}")
    if g_UndoBufferEnabled {
        TrackUndoKey()
        TrackUndoBoundary()
    }
}
$Tab:: {
    global g_UndoBufferEnabled
    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}{Tab}")
        return
    }
    Send("{Blind}{Tab}")
    if g_UndoBufferEnabled {
        TrackUndoKey()
        TrackUndoBoundary()
    }
}

$BS::{
    global g_UndoBufferEnabled
    if g_UndoBufferEnabled
        ClearUndoBuffer()
    HandleBackspace()
}
$Delete::{
    global g_UndoBufferEnabled
    if g_UndoBufferEnabled
        ClearUndoBuffer()
    HandleDelete()
}

; Ctrl+Backspace / Ctrl+Delete should respect RTL direction too.
$^BS::{
    global g_UndoBufferEnabled
    if g_UndoBufferEnabled
        ClearUndoBuffer()

    if IsHebrewKeyboard()
        Send("{Blind}^{Delete}")  ; delete word to the RIGHT
    else
        Send("{Blind}^{BS}")
}
$^Delete::{
    global g_UndoBufferEnabled
    if g_UndoBufferEnabled
        ClearUndoBuffer()

    if IsHebrewKeyboard()
        Send("{Blind}^{BS}")      ; delete word to the LEFT
    else
        Send("{Blind}^{Delete}")
}

; Space needs RTL treatment too (insert + move left) when Hebrew keyboard is active.
$Space::{
    global g_UndoBufferEnabled

    if ShouldBypassShortcuts() {
        if g_UndoBufferEnabled
            ClearUndoBuffer()
        Send("{Blind}{Space}")
        return
    }

    if !IsHebrewKeyboard() {
        Send("{Space}")
        if g_UndoBufferEnabled {
            TrackUndoKey()
            TrackUndoBoundary()
        }
        return
    }
    SendInput("{Space}")
    SendInput("{Left}")
    if g_UndoBufferEnabled {
        TrackUndoKey()
        TrackUndoBoundary()
    }
}

; Arrow keys feel reversed in Affinity when doing RTL work.
; BUT: they can be idempotent / desync undo; clear paired-undo buffer on any arrow use.
$Left::{
    global g_UndoBufferEnabled
    if g_UndoBufferEnabled
        ClearUndoBuffer()

    if IsHebrewKeyboard()
        Send("{Right}")
    else
        Send("{Left}")
}
$Right::{
    global g_UndoBufferEnabled
    if g_UndoBufferEnabled
        ClearUndoBuffer()

    if IsHebrewKeyboard()
        Send("{Left}")
    else
        Send("{Right}")
}

; Shift+Arrow character selection should also respect RTL direction.
$+Left::{
    global g_UndoBufferEnabled
    if g_UndoBufferEnabled
        ClearUndoBuffer()

    if IsHebrewKeyboard()
        Send("{Blind}+{Right}")
    else
        Send("{Blind}+{Left}")
}
$+Right::{
    global g_UndoBufferEnabled
    if g_UndoBufferEnabled
        ClearUndoBuffer()

    if IsHebrewKeyboard()
        Send("{Blind}+{Left}")
    else
        Send("{Blind}+{Right}")
}

; Ctrl+Arrow word navigation should also respect RTL direction.
$^Left::{
    global g_UndoBufferEnabled
    if g_UndoBufferEnabled
        ClearUndoBuffer()

    if IsHebrewKeyboard()
        Send("{Blind}^{Right}")
    else
        Send("{Blind}^{Left}")
}
$^Right::{
    global g_UndoBufferEnabled
    if g_UndoBufferEnabled
        ClearUndoBuffer()

    if IsHebrewKeyboard()
        Send("{Blind}^{Left}")
    else
        Send("{Blind}^{Right}")
}

; Ctrl+Shift+Arrow word selection should also respect RTL direction.
$^+Left::{
    global g_UndoBufferEnabled
    if g_UndoBufferEnabled
        ClearUndoBuffer()

    if IsHebrewKeyboard()
        Send("{Blind}^+{Right}")
    else
        Send("{Blind}^+{Left}")
}
$^+Right::{
    global g_UndoBufferEnabled
    if g_UndoBufferEnabled
        ClearUndoBuffer()

    if IsHebrewKeyboard()
        Send("{Blind}^+{Left}")
    else
        Send("{Blind}^+{Right}")
}

; Ctrl+Z / Ctrl+Y fix (debug feature):
; One Ctrl+Z consumes the WHOLE current buffer and sends Ctrl+Z the total required times.
; One Ctrl+Y restores the WHOLE last undone buffer and sends Ctrl+Y the same total times.
$^z::{
    global g_UndoBufferEnabled, g_UndoStack, g_LastUndoSnapshot

    if !g_UndoBufferEnabled {
        Send("{Blind}^z")
        return
    }

    if (g_UndoStack.Length = 0) {
        Send("{Blind}^z")
        return
    }

    ; Save snapshot for redo, then clear live stack.
    g_LastUndoSnapshot := g_UndoStack.Clone()
    g_UndoStack := []

    total := 0
    for _, c in g_LastUndoSnapshot
        total += c

    Loop total {
        Send("{Blind}^z")
        Sleep(10)
    }
}

$^y::{
    global g_UndoBufferEnabled, g_UndoStack, g_LastUndoSnapshot

    if !g_UndoBufferEnabled {
        Send("{Blind}^y")
        return
    }

    if (g_LastUndoSnapshot.Length = 0) {
        Send("{Blind}^y")
        return
    }

    total := 0
    for _, c in g_LastUndoSnapshot
        total += c

    Loop total {
        Send("{Blind}^y")
        Sleep(10)
    }

    ; Restore buffer tracking state so a subsequent Ctrl+Z can undo it again.
    g_UndoStack := g_LastUndoSnapshot.Clone()
    g_LastUndoSnapshot := []
}

; Paste
$^v::{
    global g_UndoBufferEnabled

    clipText := A_Clipboard
    DebugLog("BUILD=" . HF_BUILD_STAMP)
    DebugLog("Paste hotkey fired. proc=" . GetActiveProcessName() . " | title=" . GetActiveWindowTitle())
    DebugLog("Paste clipLen=" . StrLen(clipText) . " sample=" . SubStr(clipText, 1, 60))

    if !ClipboardContainsHebrew(clipText) {
        DebugLog("Paste: no Hebrew detected; pass-through")
        Send("{Blind}^v")
        return
    }

    savedClip := ClipboardAll()
    processed := ""

    try {
        processed := FixBidiPastePerLine(clipText)
        DebugLog("Paste stage=" . g_LastTransformStage)
    DebugLog("Paste processedLen=" . StrLen(processed) . " sample=" . SubStr(processed, 1, 60))

        if (processed = "") {
            throw Error("Transform returned empty string")
        }

        A_Clipboard := processed
        if ClipWait(1) {
            Send("{Blind}^v")
            Sleep(50)
        }
    } catch as e {
        DebugLog("Paste ERROR at stage=" . g_LastTransformStage)
        DebugLog("Paste ERROR: " . e.Message)
        try DebugLog("Paste ERROR extra: " . e.Extra)
        try DebugLog("Paste ERROR what: " . e.What)
        try DebugLog("Paste ERROR file/line: " . e.File . ":" . e.Line)

        ; Fallback: restore original clipboard and paste normally
        A_Clipboard := clipText
        ClipWait(1)
        Send("{Blind}^v")
    } finally {
        A_Clipboard := savedClip
    }

    ; Paste can alter undo history unpredictably; invalidate.
    if g_UndoBufferEnabled
        ClearUndoBuffer()
}

; Copy
$^c::{
    A_Clipboard := ""
    Send("{Blind}^c")
    if !ClipWait(0.7)
        return

    if ClipboardContainsHebrew(A_Clipboard) {
        A_Clipboard := FixBidiPastePerLine(A_Clipboard)
        ClipWait(0.4)
    }

    ; Copy shouldn't affect undo, but selection might have; be conservative.
    if g_UndoBufferEnabled
        ClearUndoBuffer()
}

#HotIf

; =============================================================================
; DIAGNOSTICS
; =============================================================================

CopyDiagnosticInfo() {
    global HF_VERSION, g_Enabled, g_AutoEnable, g_AutoEnableAllApps, g_ToggleHotkey, g_CheckUpdatesOnStartup
    global g_ConfigIni

    proc := GetActiveProcessName()
    title := GetActiveWindowTitle()

    diag := "HebrewFixer Diagnostic Report`n"
    diag .= "Generated: " . FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") . "`n`n"
    diag .= "Version: " . HF_VERSION . "`n"
    diag .= "Script/Exe: " . A_ScriptFullPath . "`n"
    diag .= "Config INI: " . g_ConfigIni . "`n`n"
    diag .= "State:`n"
    diag .= "- Enabled: " . (g_Enabled ? "Yes" : "No") . "`n"
    diag .= "- Auto-enable: " . (g_AutoEnable ? "Yes" : "No") . "`n"
    diag .= "- Auto-enable All apps: " . (g_AutoEnableAllApps ? "Yes" : "No") . "`n"
    diag .= "- Toggle hotkey (human): " . HotkeyHumanReadable(g_ToggleHotkey) . "`n"
    diag .= "- Toggle hotkey (ahk): " . g_ToggleHotkey . "`n"
    diag .= "- Active process: " . proc . "`n"
    diag .= "- Active window title: " . title . "`n"
    diag .= "- Check updates on startup: " . (g_CheckUpdatesOnStartup ? "Yes" : "No") . "`n"

    A_Clipboard := diag
    ClipWait(0.5)
    ShowTip("Diagnostic info copied", A_ScreenWidth // 2 - 100, 50, 1500)
}

; =============================================================================
; UPDATE CHECK + BANNER
; =============================================================================

CheckForUpdatesOnStartup() {
    global HF_VERSION, g_ConfigIni
    static checkedThisRun := false

    bootId := GetBootId()

    ; Harden: only do the network check once per boot.
    lastCheckedBoot := IniRead(g_ConfigIni, "Updates", "LastCheckedBootId", "")
    if (bootId != "" && lastCheckedBoot = bootId)
        return
    if (bootId = "" && checkedThisRun)
        return

    checkedThisRun := true

    ; Record that we checked on this boot (even if no update is found).
    if (bootId != "") {
        IniWrite(bootId, g_ConfigIni, "Updates", "LastCheckedBootId")
        NormalizeIniEncoding()
    }

    url := "https://api.github.com/repos/Cencyte/HebrewFixer/releases/latest"

    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.Open("GET", url, true)
        http.SetRequestHeader("User-Agent", "HebrewFixer")
        http.Send()
        http.WaitForResponse(2)

        if (http.Status != 200)
            return

        body := http.ResponseText
        if !RegExMatch(body, '"tag_name"\\s*:\\s*"([^"]+)"', &m)
            return

        latest := m[1]
        if (latest = "" || latest = HF_VERSION)
            return

        ; Show the banner only once per boot.
        lastShownBoot := IniRead(g_ConfigIni, "Updates", "LastBannerBootId", "")
        if (bootId != "" && lastShownBoot = bootId)
            return

        if (bootId != "") {
            IniWrite(bootId, g_ConfigIni, "Updates", "LastBannerBootId")
            NormalizeIniEncoding()
        }

        ShowUpdateBanner(latest)
        EnsureUpdateMenuItem(latest)
    } catch {
        return
    }
}

EnsureUpdateMenuItem(latestTag) {
    global g_UpdateMenuLabel, g_GithubRepoUrl

    newLabel := "Update available (" . latestTag . ")"
    if (g_UpdateMenuLabel = newLabel)
        return

    if (g_UpdateMenuLabel != "") {
        try A_TrayMenu.Delete(g_UpdateMenuLabel)
    }

    A_TrayMenu.Add()
    A_TrayMenu.Add(newLabel, (*) => Run(g_GithubRepoUrl))
    g_UpdateMenuLabel := newLabel
}

GetBootId() {
    ; Stable boot identifier.
    ; 1) Prefer WMI Win32_OperatingSystem.LastBootUpTime.
    ; 2) Fallback: compute boot time using system uptime (GetTickCount64).

    try {
        wmi := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\\\.\\root\\cimv2")
        for os in wmi.ExecQuery("SELECT LastBootUpTime FROM Win32_OperatingSystem") {
            s := os.LastBootUpTime
            ; WMI format: yyyymmddHHMMSS.mmmmmmsUUU
            id := SubStr(s, 1, 14)
            if (id != "")
                return id
        }
    } catch {
        ; ignore
    }

    ; Fallback: A_NowUTC - uptimeSeconds
    try {
        uptimeMs := DllCall("GetTickCount64", "Int64")
        uptimeSec := Floor(uptimeMs / 1000)
        bootUtc := DateAdd(A_NowUTC, -uptimeSec, "Seconds")
        return SubStr(bootUtc, 1, 14)
    } catch {
        return ""
    }
}

ShowUpdateBanner(latestTag) {
    global g_GithubRepoUrl

    ; A small, notification-like banner.
    w := 340, h := 74
    x := A_ScreenWidth - w - 18
    y := 18

    banner := Gui("-Caption +ToolWindow +AlwaysOnTop +Border", "")
    banner.BackColor := "FFFFFF"
    banner.MarginX := 12
    banner.MarginY := 10

    ; close button
    banner.SetFont("s10", "Segoe UI")
    btnClose := banner.AddText("x" . (w - 24) . " y8 w16 h16 Center c808080", "×")
    btnClose.OnEvent("Click", (*) => banner.Destroy())

    ; Info icon from imageres.dll (best-effort; icon index may vary by Windows version)
    hasIcon := false
    try {
        banner.AddPicture("x12 y12 w16 h16 Icon81", "imageres.dll")
        hasIcon := true
    } catch {
        try {
            banner.AddPicture("x12 y12 w16 h16 Icon2", "imageres.dll")
            hasIcon := true
        } catch {
            hasIcon := false
        }
    }

    title := "Update available"
    if (latestTag != "")
        title .= " (" . latestTag . ")"

    banner.SetFont("s9 Bold", "Segoe UI")
    tx := hasIcon ? 36 : 12
    t := banner.AddText("x" . tx . " y10 w" . (w - tx - 28), title)

    banner.SetFont("s9 Norm", "Segoe UI")
    t2 := banner.AddText("x" . tx . " y+4 w" . (w - tx - 20) . " c404040", "Click to open GitHub")

    open := (*) => (Run(g_GithubRepoUrl), banner.Destroy())
    t.OnEvent("Click", open)
    t2.OnEvent("Click", open)
    banner.OnEvent("Click", open)

    banner.Show("x" . x . " y" . y . " w" . w . " h" . h . " NoActivate")

    ; Rounded corners (best-effort)
    try WinSetRegion("0-0 w" . w . " h" . h . " R12-12", banner.Hwnd)

    SetTimer(() => (banner.Destroy()), -10000)
}