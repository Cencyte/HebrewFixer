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

; =============================================================================
; EXPERIMENTAL CONFIG
; =============================================================================
; Set to FALSE to disable all manual RTL reversal logic (arrow keys, backspace,
; delete, selection, etc.) and let the Unicode directional characters (RLM)
; handle RTL behavior on their own.
; =============================================================================
global g_ManualReversalEnabled := false

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

SetupTray()
ToolTip("HebrewFixer (Per-Key v2) loaded`nCtrl+Alt+H to toggle", A_ScreenWidth // 2 - 120, 50)
SetTimer(() => ToolTip(), -2500)

; =============================================================================
; TRAY
; =============================================================================

SetupTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Toggle Hebrew RTL (Ctrl+Alt+H)", (*) => ToggleMode())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Show Buffer (Debug)", (*) => ShowDebug())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    UpdateTray()
}

UpdateTray() {
    global g_Enabled
    A_IconTip := "HebrewFixer: " . (g_Enabled ? "ON" : "OFF")
    try {
        if g_Enabled
            TraySetIcon("shell32.dll", 44)
        else
            TraySetIcon("shell32.dll", 1)
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
    global g_Enabled, g_Buffer
    g_Enabled := !g_Enabled
    g_Buffer := ""
    UpdateTray()
    ToolTip("Hebrew RTL: " . (g_Enabled ? "ON" : "OFF"), A_ScreenWidth // 2 - 60, 50)
    SetTimer(() => ToolTip(), -1500)
}

^!h::ToggleMode()

; =============================================================================
; CORE: ZWS EXPERIMENTAL RTL INSERTION
; =============================================================================
; EXPERIMENTAL: Using Zero-Width Space (U+200B) or Zero-Width Joiner (U+200D)
; to potentially influence cursor positioning without visible movement.
;
; Theory: If we prepend ZWS before the Hebrew char, the text engine might
; handle cursor positioning differently, eliminating the visible flicker
; caused by the explicit {Left} keystroke.
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
    
    ; ZWS EXPERIMENTAL APPROACH:
    ; Unicode control characters that might influence cursor behavior:
    ; - U+200B = Zero-Width Space
    ; - U+200C = Zero-Width Non-Joiner (ZWNJ)
    ; - U+200D = Zero-Width Joiner (ZWJ)
    ; - U+200F = Right-to-Left Mark (RLM)
    ; - U+202B = Right-to-Left Embedding (RLE)
    ; - U+202C = Pop Directional Formatting (PDF)
    ;
    ; Try: RLM before char to signal RTL context
    static RLM := Chr(0x200F)
    static PDF := Chr(0x202C)
    
    ; Insert RLM + char via clipboard for atomic operation
    savedClip := ClipboardAll()
    A_Clipboard := RLM . hebrewChar
    ClipWait(0.3)
    SendInput("^v")
    Sleep(5)
    A_Clipboard := savedClip
}

; =============================================================================
; SPECIAL KEY HANDLERS
; =============================================================================

HandleBackspace() {
    global g_Buffer, g_ManualReversalEnabled
    
    if g_Buffer != "" {
        g_Buffer := SubStr(g_Buffer, 1, -1)
    }
    
    if g_ManualReversalEnabled {
        ; RTL: Swap Backspace → Delete
        Send("{Delete}")
    } else {
        ; Native behavior - let Unicode control chars handle RTL
        Send("{BS}")
    }
}

HandleDelete() {
    global g_Buffer, g_ManualReversalEnabled
    
    if g_Buffer != "" {
        g_Buffer := SubStr(g_Buffer, 2)
    }
    
    if g_ManualReversalEnabled {
        ; RTL: Swap Delete → Backspace
        Send("{BS}")
    } else {
        ; Native behavior - let Unicode control chars handle RTL
        Send("{Delete}")
    }
}

HandleCtrlBackspace() {
    global g_Buffer, g_ManualReversalEnabled
    
    g_Buffer := ""
    
    if g_ManualReversalEnabled {
        ; RTL: Ctrl+Backspace → Ctrl+Delete
        Send("^{Delete}")
    } else {
        ; Native behavior
        Send("^{BS}")
    }
}

HandleCtrlDelete() {
    global g_Buffer, g_ManualReversalEnabled
    
    g_Buffer := ""
    
    if g_ManualReversalEnabled {
        ; RTL: Ctrl+Delete → Ctrl+Backspace
        Send("^{BS}")
    } else {
        ; Native behavior
        Send("^{Delete}")
    }
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
$Left::{
    global g_ManualReversalEnabled
    HandleBufferReset()
    if g_ManualReversalEnabled {
        Send("{Right}")  ; RTL reversed
    } else {
        Send("{Left}")   ; Native behavior
    }
}
$Right::{
    global g_ManualReversalEnabled
    HandleBufferReset()
    if g_ManualReversalEnabled {
        Send("{Left}")   ; RTL reversed
    } else {
        Send("{Right}")  ; Native behavior
    }
}
+Left::{
    global g_ManualReversalEnabled
    if g_ManualReversalEnabled {
        Send("+{Right}")  ; RTL reversed
    } else {
        Send("+{Left}")   ; Native behavior
    }
}
+Right::{
    global g_ManualReversalEnabled
    if g_ManualReversalEnabled {
        Send("+{Left}")   ; RTL reversed
    } else {
        Send("+{Right}")  ; Native behavior
    }
}
^Left::{
    global g_ManualReversalEnabled
    HandleBufferReset()
    if g_ManualReversalEnabled {
        Send("^{Right}")  ; RTL reversed
    } else {
        Send("^{Left}")   ; Native behavior
    }
}
^Right::{
    global g_ManualReversalEnabled
    HandleBufferReset()
    if g_ManualReversalEnabled {
        Send("^{Left}")   ; RTL reversed
    } else {
        Send("^{Right}")  ; Native behavior
    }
}
^+Left::{
    global g_ManualReversalEnabled
    if g_ManualReversalEnabled {
        Send("^+{Right}")  ; RTL reversed
    } else {
        Send("^+{Left}")   ; Native behavior
    }
}
^+Right::{
    global g_ManualReversalEnabled
    if g_ManualReversalEnabled {
        Send("^+{Left}")   ; RTL reversed
    } else {
        Send("^+{Right}")  ; Native behavior
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
; PASTE - For pasting Hebrew text with RTL reversal
; -----------------------------------------------------------------------------
^v::{
    global g_Buffer
    
    ; Get clipboard text
    clipText := A_Clipboard
    
    ; Debug: Show what we got
    ; ToolTip("Clip length: " . StrLen(clipText), 100, 100)
    ; SetTimer(() => ToolTip(), -2000)
    
    ; Check if clipboard contains Hebrew characters (Unicode range 0590-05FF)
    hasHebrew := RegExMatch(clipText, "[\x{0590}-\x{05FF}]")
    
    if hasHebrew {
        ; Reverse the string for proper RTL display in non-RTL-aware apps
        reversed := ""
        chars := StrSplit(clipText)
        Loop chars.Length {
            reversed .= chars[chars.Length - A_Index + 1]
        }
        
        ; Temporarily replace clipboard with reversed text
        savedClip := ClipboardAll()
        A_Clipboard := reversed
        if ClipWait(1) {
            Send("^v")
            Sleep(50)
        }
        A_Clipboard := savedClip
    } else {
        ; No Hebrew - just paste normally
        Send("^v")
    }
    
    g_Buffer := ""
}

; -----------------------------------------------------------------------------
; SPACE - Resets buffer (new word)
; -----------------------------------------------------------------------------
$Space::{
    global g_Buffer
    g_Buffer := ""
    Send("{Space}")
}

#HotIf

; =============================================================================
; END
; =============================================================================
