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
    
    ; RTL: Simply swap Backspace → Delete
    ; Let the native key do the work, just reversed
    if g_Buffer != "" {
        g_Buffer := SubStr(g_Buffer, 1, -1)  ; Remove newest char from buffer
    }
    Send("{Delete}")
}

HandleDelete() {
    global g_Buffer
    
    ; RTL: Simply swap Delete → Backspace
    ; Let the native key do the work, just reversed
    if g_Buffer != "" {
        g_Buffer := SubStr(g_Buffer, 2)  ; Remove oldest char from buffer
    }
    Send("{BS}")
}

HandleCtrlBackspace() {
    global g_Buffer
    
    ; RTL: Ctrl+Backspace deletes word → swap to Ctrl+Delete
    g_Buffer := ""
    Send("^{Delete}")
}

HandleCtrlDelete() {
    global g_Buffer
    
    ; RTL: Ctrl+Delete deletes word → swap to Ctrl+Backspace
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
$Left::{
    ; RTL: Left arrow moves toward OLDER text (visually right), so send Right
    HandleBufferReset()
    Send("{Right}")
}
$Right::{
    ; RTL: Right arrow moves toward NEWER text (visually left), so send Left
    HandleBufferReset()
    Send("{Left}")
}
+Left::{
    ; RTL: Shift+Left selects toward OLDER text, so send Shift+Right
    Send("+{Right}")
}
+Right::{
    ; RTL: Shift+Right selects toward NEWER text, so send Shift+Left
    Send("+{Left}")
}
^Left::{
    ; RTL: Ctrl+Left jumps word toward OLDER text, so send Ctrl+Right
    HandleBufferReset()
    Send("^{Right}")
}
^Right::{
    ; RTL: Ctrl+Right jumps word toward NEWER text, so send Ctrl+Left
    HandleBufferReset()
    Send("^{Left}")
}
^+Left::{
    ; RTL: Ctrl+Shift+Left selects word toward OLDER text, so send Ctrl+Shift+Right
    Send("^+{Right}")
}
^+Right::{
    ; RTL: Ctrl+Shift+Right selects word toward NEWER text, so send Ctrl+Shift+Left
    Send("^+{Left}")
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
