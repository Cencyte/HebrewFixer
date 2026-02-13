; =============================================================================
; HebrewFixer for Affinity Designer - Per-Key Intercept v2
; =============================================================================
;
; TRUE keystroke interception using physical key mappings.
; O(1) insertion - no accordion effect. Each char is inserted at the
; beginning of the line, creating proper RTL visual flow.
;
; TOGGLE: Ctrl+Alt+H
;
; =============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode("Input")
SetKeyDelay(-1, -1)

; =============================================================================
; GLOBALS
; =============================================================================

global g_Enabled := false
global g_Buffer := ""
global g_AutoEnable := true   ; Auto-enable when Hebrew IME is detected (on by default)
global g_ManualOverride := false  ; True when user manually toggled (overrides auto)
global g_LastIMEState := false  ; Track IME state to detect changes
global g_NoTooltip := false

; Hebrew keyboard layout mapping (US QWERTY physical keys → Hebrew chars)
; Based on standard Israeli Hebrew keyboard layout
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

; =============================================================================
; INITIALIZATION
; =============================================================================

; Check for command-line arguments
for arg in A_Args {
    if (arg = "/NoTooltip" || arg = "-NoTooltip" || arg = "--NoTooltip") {
        g_NoTooltip := true
        continue
    }
    if (arg = "/exit" || arg = "-exit" || arg = "--exit") {
        ; Signal existing instance to exit by sending WM_CLOSE
        DetectHiddenWindows(true)
        if WinExist("HebrewFixer ahk_class AutoHotkey") {
            PostMessage(0x10, 0, 0)  ; WM_CLOSE = 0x10
        }
        ExitApp()
    }
}

; Register cleanup handler for graceful exit
OnExit(CleanupBeforeExit)

SetupTray()
ShowTip("HebrewFixer (Per-Key v2) loaded`nCtrl+Alt+H to toggle", A_ScreenWidth // 2 - 120, 50, 2500)

; Start auto-enable timer (checks every 250ms)
SetTimer(CheckAutoEnable, 250)

; Cleanup function - ensures clean exit
CleanupBeforeExit(ExitReason, ExitCode) {
    ; AHK automatically removes tray icon on normal exit
    ; Just ensure timers are stopped
    SetTimer(CheckAutoEnable, 0)
    return 0  ; Allow exit to proceed
}

; =============================================================================
; TOOLTIP HELPERS
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

; =============================================================================
; TRAY
; =============================================================================

SetupTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Toggle Hebrew RTL (Ctrl+Alt+H)", (*) => ToggleMode())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Auto-enable on Hebrew keyboard", (*) => ToggleAutoEnable())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Show Buffer (Debug)", (*) => ShowDebug())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    UpdateTray()
}

ToggleAutoEnable() {
    global g_AutoEnable
    g_AutoEnable := !g_AutoEnable
    UpdateTray()
    ShowTip("Auto-enable: " . (g_AutoEnable ? "ON" : "OFF"), A_ScreenWidth // 2 - 60, 50, 1500)
}

CheckAutoEnable() {
    global g_AutoEnable, g_Enabled, g_ManualOverride, g_LastIMEState
    
    ; Only act if auto-enable is turned on
    if !g_AutoEnable
        return
    
    ; Check if Hebrew keyboard is active
    isHebrew := IsHebrewKeyboard()
    
    ; If IME state changed, clear manual override (user switched keyboard)
    if (isHebrew != g_LastIMEState) {
        g_ManualOverride := false
        g_LastIMEState := isHebrew
    }
    
    ; If user manually overrode, don't auto-toggle
    if g_ManualOverride
        return
    
    ; Auto-toggle based on IME
    if (isHebrew && !g_Enabled) {
        g_Enabled := true
        UpdateTray()
    } else if (!isHebrew && g_Enabled) {
        g_Enabled := false
        UpdateTray()
    }
}

UpdateTray() {
    global g_Enabled, g_AutoEnable
    
    ; Update checkmark for auto-enable menu item
    if g_AutoEnable
        A_TrayMenu.Check("Auto-enable on Hebrew keyboard")
    else
        A_TrayMenu.Uncheck("Auto-enable on Hebrew keyboard")
    
    ; Update icon and tooltip
    A_IconTip := "HebrewFixer: " . (g_Enabled ? "ON" : "OFF") . (g_AutoEnable ? " [Auto]" : "")
    
    ; Use custom Shin icons from Desktop (or script directory)
    iconPath := A_ScriptDir . "\"
    try {
        if g_Enabled
            TraySetIcon(iconPath . "hebrew_fixer_on.ico")
        else
            TraySetIcon(iconPath . "hebrew_fixer_off.ico")
    } catch {
        ; Fallback to shell32 icons if custom icons not found
        try {
            if g_Enabled
                TraySetIcon("shell32.dll", 44)
            else
                TraySetIcon("shell32.dll", 1)
        }
    }
}

ShowDebug() {
    global g_Buffer, g_Enabled
    MsgBox(
        "Mode: " . (g_Enabled ? "ON" : "OFF") . "`n"
        "Buffer: [" . g_Buffer . "]`n"
        "Length: " . StrLen(g_Buffer),
        "HebrewFixer Debug"
    )
}

; =============================================================================
; UTILITIES
; =============================================================================

IsAffinityActive() {
    try {
        title := WinGetTitle("A")
        return InStr(title, "Affinity Designer")
            || InStr(title, "Affinity Photo")
            || InStr(title, "Affinity Publisher")
    }
    return false
}

; -----------------------------------------------------------------------------
; IME DETECTION - Check if Windows keyboard is set to Hebrew
; Returns true if current keyboard layout is Hebrew (0x040D)
; -----------------------------------------------------------------------------
IsHebrewKeyboard() {
    try {
        ; Get the active window's thread ID
        threadId := DllCall("GetWindowThreadProcessId", "Ptr", WinExist("A"), "Ptr", 0, "UInt")
        ; Get the keyboard layout for that thread
        hkl := DllCall("GetKeyboardLayout", "UInt", threadId, "Ptr")
        ; Extract language ID (low word)
        langId := hkl & 0xFFFF
        ; Hebrew language ID is 0x040D (1037 decimal)
        return (langId = 0x040D)
    }
    return false
}

; =============================================================================
; MODE TOGGLE
; =============================================================================

ToggleMode() {
    global g_Enabled, g_Buffer, g_ManualOverride, g_AutoEnable
    g_Enabled := !g_Enabled
    g_Buffer := ""
    
    ; If auto-enable is on, set manual override so auto doesn't fight the user
    if g_AutoEnable
        g_ManualOverride := true
    
    UpdateTray()
    msg := "Hebrew RTL: " . (g_Enabled ? "ON" : "OFF")
    if (g_AutoEnable && g_ManualOverride)
        msg .= " (override)"
    ShowTip(msg, A_ScreenWidth // 2 - 60, 50, 1500)
}

^!h::ToggleMode()

; =============================================================================
; CORE: CURSOR-RELATIVE RTL INSERTION
; =============================================================================
; Insert character at CURRENT cursor position, then move cursor LEFT.
; This allows mid-text editing while maintaining RTL flow:
; - New chars appear to the LEFT of the previous one
; - Cursor stays at the "typing edge" (left side of newest char)
; =============================================================================

HandleHebrewKey(physicalKey) {
    global g_Buffer, HebrewMap
    
    if !HebrewMap.Has(physicalKey)
        return
    
    ; IME CHECK: Only produce Hebrew if Windows keyboard is set to Hebrew
    ; If user has English IME active, pass through the original key
    if !IsHebrewKeyboard() {
        Send(physicalKey)
        return
    }
    
    hebrewChar := HebrewMap[physicalKey]
    
    ; Track in buffer (for potential future use)
    g_Buffer .= hebrewChar
    
    ; CURSOR-RELATIVE RTL insertion:
    ; Type character, then immediately move cursor left
    ; SetKeyDelay(-1, -1) at script start ensures minimal delay
    ; Two SendInput calls but they get buffered together by Windows
    SendInput("{Raw}" . hebrewChar)
    SendInput("{Left}")
}

; =============================================================================
; SPECIAL KEY HANDLERS
; =============================================================================

HandleBackspace() {
    global g_Buffer
    
    ; Only swap if Hebrew IME is active
    if !IsHebrewKeyboard() {
        Send("{BS}")
        return
    }
    
    ; RTL: Simply swap Backspace → Delete
    if g_Buffer != "" {
        g_Buffer := SubStr(g_Buffer, 1, -1)
    }
    Send("{Delete}")
}

HandleDelete() {
    global g_Buffer
    
    ; Only swap if Hebrew IME is active
    if !IsHebrewKeyboard() {
        Send("{Delete}")
        return
    }
    
    ; RTL: Simply swap Delete → Backspace
    if g_Buffer != "" {
        g_Buffer := SubStr(g_Buffer, 2)
    }
    Send("{BS}")
}

HandleCtrlBackspace() {
    global g_Buffer
    
    ; Only swap if Hebrew IME is active
    if !IsHebrewKeyboard() {
        Send("^{BS}")
        return
    }
    
    ; RTL: Ctrl+Backspace → Ctrl+Delete
    g_Buffer := ""
    Send("^{Delete}")
}

HandleCtrlDelete() {
    global g_Buffer
    
    ; Only swap if Hebrew IME is active
    if !IsHebrewKeyboard() {
        Send("^{Delete}")
        return
    }
    
    ; RTL: Ctrl+Delete → Ctrl+Backspace
    g_Buffer := ""
    Send("^{BS}")
}

HandleBufferReset() {
    global g_Buffer
    g_Buffer := ""
}

; =============================================================================
; CONTEXT: Only when enabled AND in Affinity
; =============================================================================

#HotIf g_Enabled && IsAffinityActive()

; -----------------------------------------------------------------------------
; PHYSICAL KEY MAPPINGS (US QWERTY → Hebrew)
; $ prefix = intercept and block the original key
; -----------------------------------------------------------------------------

$a::HandleHebrewKey("a")
$b::HandleHebrewKey("b")
$c::HandleHebrewKey("c")
$d::HandleHebrewKey("d")
$e::HandleHebrewKey("e")
$f::HandleHebrewKey("f")
$g::HandleHebrewKey("g")
$h::HandleHebrewKey("h")
$i::HandleHebrewKey("i")
$j::HandleHebrewKey("j")
$k::HandleHebrewKey("k")
$l::HandleHebrewKey("l")
$m::HandleHebrewKey("m")
$n::HandleHebrewKey("n")
$o::HandleHebrewKey("o")
$p::HandleHebrewKey("p")
$r::HandleHebrewKey("r")
$s::HandleHebrewKey("s")
$t::HandleHebrewKey("t")
$u::HandleHebrewKey("u")
$v::HandleHebrewKey("v")
$x::HandleHebrewKey("x")
$y::HandleHebrewKey("y")
$z::HandleHebrewKey("z")
$,::HandleHebrewKey(",")
$.::HandleHebrewKey(".")
$;::HandleHebrewKey(";")

; Keys not mapped to Hebrew pass through normally
$q::Send("q")
$w::Send("w")

; -----------------------------------------------------------------------------
; SPECIAL KEYS
; -----------------------------------------------------------------------------

$BS::HandleBackspace()
$Delete::HandleDelete()
^BS::HandleCtrlBackspace()
^Delete::HandleCtrlDelete()

$Enter::{ 
    HandleBufferReset()
    Send("{Enter}")
}
$Tab::{
    HandleBufferReset()
    Send("{Tab}")
}
$Esc::{
    HandleBufferReset()
    Send("{Esc}")
}

; -----------------------------------------------------------------------------
; SPACEBAR - Treat like a character in RTL mode (insert + move left)
; -----------------------------------------------------------------------------
$Space::{
    global g_Buffer
    
    ; If not Hebrew IME, just send space normally
    if !IsHebrewKeyboard() {
        Send("{Space}")
        return
    }
    
    ; In RTL mode, space needs same treatment as Hebrew chars:
    ; Insert space, then move cursor left to maintain RTL flow
    g_Buffer .= " "
    SendInput("{Space}")
    SendInput("{Left}")
}

$Left::{
    HandleBufferReset()
    if IsHebrewKeyboard() {
        Send("{Right}")  ; RTL: reversed
    } else {
        Send("{Left}")   ; Normal
    }
}
$Right::{
    HandleBufferReset()
    if IsHebrewKeyboard() {
        Send("{Left}")   ; RTL: reversed
    } else {
        Send("{Right}")  ; Normal
    }
}
+Left::{
    if IsHebrewKeyboard() {
        Send("+{Right}")  ; RTL: reversed
    } else {
        Send("+{Left}")   ; Normal
    }
}
+Right::{
    if IsHebrewKeyboard() {
        Send("+{Left}")   ; RTL: reversed
    } else {
        Send("+{Right}")  ; Normal
    }
}
^Left::{
    HandleBufferReset()
    if IsHebrewKeyboard() {
        Send("^{Right}")  ; RTL: reversed
    } else {
        Send("^{Left}")   ; Normal
    }
}
^Right::{
    HandleBufferReset()
    if IsHebrewKeyboard() {
        Send("^{Left}")   ; RTL: reversed
    } else {
        Send("^{Right}")  ; Normal
    }
}
^+Left::{
    if IsHebrewKeyboard() {
        Send("^+{Right}")  ; RTL: reversed
    } else {
        Send("^+{Left}")   ; Normal
    }
}
^+Right::{
    if IsHebrewKeyboard() {
        Send("^+{Left}")   ; RTL: reversed
    } else {
        Send("^+{Right}")  ; Normal
    }
}
$Up::{
    HandleBufferReset()
    Send("{Up}")
}
$Down::{
    HandleBufferReset()
    Send("{Down}")
}
$Home::{
    HandleBufferReset()
    Send("{Home}")
}
$End::{
    HandleBufferReset()
    Send("{End}")
}

^a::{
    HandleBufferReset()
    Send("^a")
}
^z::{
    HandleBufferReset()
    Send("^z")
}
^y::{
    HandleBufferReset()
    Send("^y")
}

; -----------------------------------------------------------------------------
; PASTE - BiDi-aware paste for mixed Hebrew/English text
; -----------------------------------------------------------------------------
; Implements a simplified BiDi algorithm:
; 1. Split text into directional runs (Hebrew RTL vs non-Hebrew LTR)
; 2. Reverse the order of runs
; 3. Reverse characters within Hebrew runs only
; 4. Preserve character order within non-Hebrew runs
; -----------------------------------------------------------------------------
^v::{
    global g_Buffer
    
    clipText := A_Clipboard
    
    ; Check if clipboard contains Hebrew characters
    if !RegExMatch(clipText, "[\x{0590}-\x{05FF}]") {
        ; No Hebrew - just paste normally
        Send("^v")
        g_Buffer := ""
        return
    }
    
    ; Process with BiDi algorithm
    processed := BiDiProcess(clipText)
    
    ; Paste the processed text
    savedClip := ClipboardAll()
    A_Clipboard := processed
    if ClipWait(1) {
        Send("^v")
        Sleep(50)
    }
    A_Clipboard := savedClip
    g_Buffer := ""
}

; -----------------------------------------------------------------------------
; BiDi Processing Function
; -----------------------------------------------------------------------------
BiDiProcess(text) {
    ; Split into directional runs
    runs := []
    currentRun := ""
    currentIsHebrew := false
    
    chars := StrSplit(text)
    
    for i, char in chars {
        charIsHebrew := IsHebrewChar(char)
        
        if (i = 1) {
            ; First character starts first run
            currentRun := char
            currentIsHebrew := charIsHebrew
        } else if (charIsHebrew = currentIsHebrew) {
            ; Same direction - extend current run
            currentRun .= char
        } else {
            ; Direction changed - save current run, start new one
            runs.Push({text: currentRun, isHebrew: currentIsHebrew})
            currentRun := char
            currentIsHebrew := charIsHebrew
        }
    }
    
    ; Don't forget the last run
    if (currentRun != "") {
        runs.Push({text: currentRun, isHebrew: currentIsHebrew})
    }
    
    ; Keep run order the same, only reverse chars within Hebrew runs
    ; (The BiDi algorithm displays runs in logical order for RTL base direction,
    ; but reverses character order within RTL runs)
    
    ; Build result: reverse chars within Hebrew runs, preserve non-Hebrew
    result := ""
    for i, run in runs {
        if run.isHebrew {
            ; Reverse characters within Hebrew run
            runChars := StrSplit(run.text)
            Loop runChars.Length {
                result .= runChars[runChars.Length - A_Index + 1]
            }
        } else {
            ; Keep non-Hebrew run as-is
            result .= run.text
        }
    }
    
    return result
}

; -----------------------------------------------------------------------------
; Check if character is Hebrew (U+0590 to U+05FF)
; -----------------------------------------------------------------------------
IsHebrewChar(char) {
    code := Ord(char)
    return (code >= 0x0590 && code <= 0x05FF)
}

#HotIf

; =============================================================================
; END
; =============================================================================
