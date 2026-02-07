; =============================================================================
; HebrewFixer for Affinity Designer - v2.0 (Experimental)
; =============================================================================
;
; Provides proper RTL (Right-to-Left) Hebrew text input in Affinity Designer.
;
; FEATURES:
;   - Live Hebrew typing with correct RTL display
;   - Smart paste: only reverses Hebrew segments, preserves English/numbers
;   - Proper backspace handling with display rebuild
;   - Mixed Hebrew/English support
;   - Punctuation handling (keeps punctuation in correct position)
;   - Visual feedback via tray icon
;   - Works with Affinity Designer, Photo, and Publisher
;
; USAGE:
;   Ctrl+Alt+H  - Toggle Hebrew RTL mode ON/OFF
;
; REQUIREMENTS:
;   - AutoHotkey v2.0+
;   - Windows 11 with Hebrew keyboard layout installed
;   - Affinity Designer/Photo/Publisher
;
; =============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode("Input")
SetKeyDelay(-1, -1)

; =============================================================================
; CONFIGURATION
; =============================================================================

class Config {
    ; Hebrew Unicode range (U+0590 to U+05FF)
    static HEB_START := 0x0590
    static HEB_END := 0x05FF
    
    ; Hebrew vowels/cantillation marks (nikud) - subset of Hebrew block
    static NIKUD_START := 0x0591
    static NIKUD_END := 0x05C7
    
    ; Punctuation that should stay with Hebrew text
    static HEB_PUNCTUATION := '.,;:!?"' . "'" . '()-[]{}״׳'
    
    ; Key timing (ms)
    static KEY_DELAY := 0
    static REBUILD_DELAY := 2
}

; =============================================================================
; GLOBAL STATE
; =============================================================================

global g_Enabled := false
global g_Buffer := ""           ; Logical buffer (typing order)
global g_Hook := ""             ; InputHook object
global g_LastActivity := 0      ; Tick count of last Hebrew input

; =============================================================================
; INITIALIZATION
; =============================================================================

Initialize()
return

Initialize() {
    SetupTray()
    ShowNotification("HebrewFixer loaded`nCtrl+Alt+H to toggle", 2500)
    
    ; Register cleanup on exit
    OnExit(Cleanup)
}

Cleanup(exitReason, exitCode) {
    global g_Hook, g_Enabled
    if g_Hook {
        g_Hook.Stop()
        g_Hook := ""
    }
    g_Enabled := false
    return 0
}

; =============================================================================
; TRAY MENU
; =============================================================================

SetupTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Toggle Hebrew RTL (Ctrl+Alt+H)", (*) => ToggleMode())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Show Buffer (Debug)", (*) => ShowBufferDebug())
    A_TrayMenu.Add()
    A_TrayMenu.Add("About", (*) => ShowAbout())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    UpdateTrayIcon()
}

UpdateTrayIcon() {
    global g_Enabled
    if g_Enabled {
        try TraySetIcon("shell32.dll", 44)  ; Checkmark icon
        A_IconTip := "HebrewFixer: ON`nCtrl+Alt+H to toggle"
    } else {
        try TraySetIcon("shell32.dll", 1)   ; Default
        A_IconTip := "HebrewFixer: OFF`nCtrl+Alt+H to toggle"
    }
}

ShowAbout() {
    MsgBox(
        "HebrewFixer for Affinity Designer v2.0`n"
        "`n"
        "Enables proper Right-to-Left Hebrew typing in`n"
        "Affinity Designer, Photo, and Publisher.`n"
        "`n"
        "Features:`n"
        "• Live RTL typing`n"
        "• Smart paste (preserves English/numbers)`n"
        "• Proper backspace handling`n"
        "`n"
        "Toggle: Ctrl+Alt+H`n"
        "`n"
        "Created for the community.",
        "About HebrewFixer",
        "Iconi"
    )
}

ShowBufferDebug() {
    global g_Buffer, g_Enabled
    MsgBox(
        "Mode: " . (g_Enabled ? "ON" : "OFF") . "`n"
        "Buffer: [" . g_Buffer . "]`n"
        "Length: " . StrLen(g_Buffer) . "`n"
        "Reversed: [" . ReverseString(g_Buffer) . "]",
        "HebrewFixer Debug",
        "Iconi"
    )
}

ShowNotification(text, duration := 1500) {
    ToolTip(text, A_ScreenWidth // 2 - 80, 50)
    SetTimer(ClearToolTip, -duration)
}

ClearToolTip() {
    ToolTip()
}

; =============================================================================
; UTILITY FUNCTIONS
; =============================================================================

; Check if character is Hebrew letter or nikud
IsHebrew(char) {
    if StrLen(char) != 1
        return false
    code := Ord(char)
    return (code >= Config.HEB_START && code <= Config.HEB_END)
}

; Check if character is Hebrew letter (not nikud)
IsHebrewLetter(char) {
    if StrLen(char) != 1
        return false
    code := Ord(char)
    ; Hebrew letters are 0x05D0 (א) to 0x05EA (ת)
    return (code >= 0x05D0 && code <= 0x05EA)
}

; Check if char is punctuation that can appear in Hebrew text
IsHebrewPunctuation(char) {
    return InStr(Config.HEB_PUNCTUATION, char)
}

; Check if we should treat this char as part of Hebrew sequence
IsHebrewSequenceChar(char) {
    return IsHebrew(char) || IsHebrewPunctuation(char)
}

; Reverse a string
ReverseString(str) {
    result := ""
    Loop Parse str
        result := A_LoopField . result
    return result
}

; Smart reverse: only reverse Hebrew segments, keep LTR segments in place
SmartReverse(str) {
    if str = ""
        return ""
    
    result := ""
    segment := ""
    isHebrewSegment := false
    
    Loop Parse str {
        char := A_LoopField
        charIsHebrew := IsHebrew(char)
        
        if A_Index = 1 {
            ; First character sets the segment type
            segment := char
            isHebrewSegment := charIsHebrew
            continue
        }
        
        if charIsHebrew = isHebrewSegment {
            ; Same type, add to current segment
            segment .= char
        } else {
            ; Type changed, process previous segment and start new
            if isHebrewSegment
                result .= ReverseString(segment)
            else
                result .= segment
            
            segment := char
            isHebrewSegment := charIsHebrew
        }
    }
    
    ; Process final segment
    if segment != "" {
        if isHebrewSegment
            result .= ReverseString(segment)
        else
            result .= segment
    }
    
    return result
}

; Check if string contains any Hebrew
ContainsHebrew(str) {
    Loop Parse str {
        if IsHebrew(A_LoopField)
            return true
    }
    return false
}

; Check if active window is Affinity app
IsAffinityActive() {
    try {
        title := WinGetTitle("A")
        exe := WinGetProcessName("A")
        
        ; Check by window title
        if InStr(title, "Affinity Designer")
            || InStr(title, "Affinity Photo")
            || InStr(title, "Affinity Publisher")
            return true
        
        ; Check by executable name
        if InStr(exe, "Designer")
            || InStr(exe, "Photo")
            || InStr(exe, "Publisher")
            return true
    }
    return false
}

; =============================================================================
; MODE TOGGLE
; =============================================================================

ToggleMode() {
    global g_Enabled, g_Buffer, g_Hook
    
    g_Enabled := !g_Enabled
    g_Buffer := ""  ; Always reset buffer on toggle
    
    if g_Enabled {
        StartInputHook()
        ShowNotification("Hebrew RTL: ON ✓", 1200)
    } else {
        StopInputHook()
        ShowNotification("Hebrew RTL: OFF", 1200)
    }
    
    UpdateTrayIcon()
}

; =============================================================================
; INPUT HOOK MANAGEMENT
; =============================================================================

StartInputHook() {
    global g_Hook, g_Buffer
    
    g_Buffer := ""
    
    ; Create InputHook
    ; Options: V = visible (keys reach window), I1 = ignore SendLevel 1+
    g_Hook := InputHook("V I1")
    g_Hook.OnChar := OnCharHandler
    g_Hook.OnKeyDown := OnKeyDownHandler
    g_Hook.NotifyNonText := true
    g_Hook.KeyOpt("{All}", "N")  ; Notify on all keys
    g_Hook.Start()
}

StopInputHook() {
    global g_Hook, g_Buffer
    
    if g_Hook {
        g_Hook.Stop()
        g_Hook := ""
    }
    g_Buffer := ""
}

; =============================================================================
; INPUT HANDLERS
; =============================================================================

OnCharHandler(hook, char) {
    global g_Buffer, g_Enabled, g_LastActivity
    
    ; Only process when enabled and in Affinity
    if !g_Enabled || !IsAffinityActive()
        return
    
    ; Hebrew character handling
    if IsHebrew(char) {
        g_LastActivity := A_TickCount
        
        ; The character was already typed (V mode)
        ; We need to: delete all, add to buffer, re-type reversed
        
        oldLen := StrLen(g_Buffer)
        g_Buffer .= char
        newLen := StrLen(g_Buffer)
        
        ; Delete all characters (old ones + the one just typed)
        if newLen > 0 {
            ; Send backspaces to clear
            Loop newLen
                Send("{BS}")
            
            ; Small delay for Affinity to process
            Sleep(Config.REBUILD_DELAY)
            
            ; Send reversed buffer
            SendText(ReverseString(g_Buffer))
        }
        return
    }
    
    ; Non-Hebrew: Check if it's punctuation that should stay with Hebrew
    if g_Buffer != "" && IsHebrewPunctuation(char) {
        ; Punctuation after Hebrew - add to buffer and rebuild
        g_LastActivity := A_TickCount
        
        oldLen := StrLen(g_Buffer)
        g_Buffer .= char
        newLen := StrLen(g_Buffer)
        
        ; Rebuild display
        Loop newLen
            Send("{BS}")
        Sleep(Config.REBUILD_DELAY)
        SendText(ReverseString(g_Buffer))
        return
    }
    
    ; Any other character resets the buffer
    ; (char already typed, we just clear our tracking)
    g_Buffer := ""
}

OnKeyDownHandler(hook, vk, sc) {
    global g_Buffer, g_Enabled
    
    if !g_Enabled || !IsAffinityActive()
        return true  ; Let key through
    
    ; === BACKSPACE (0x08) ===
    if vk = 0x08 {
        if g_Buffer != "" {
            ; Remove last character from logical buffer
            g_Buffer := SubStr(g_Buffer, 1, -1)
            
            ; The backspace will delete from the DISPLAY (which is reversed)
            ; In RTL display, backspace deletes the leftmost char (visually)
            ; which is actually the LAST char we typed (rightmost in buffer)
            ; So the default backspace behavior is correct!
            
            ; If buffer still has content, we need to rebuild
            if g_Buffer != "" {
                ; Let the backspace go through first
                Sleep(Config.REBUILD_DELAY)
                
                ; Now delete remaining displayed chars and rebuild
                bufLen := StrLen(g_Buffer)
                Loop bufLen
                    Send("{BS}")
                Sleep(Config.REBUILD_DELAY)
                SendText(ReverseString(g_Buffer))
            }
        }
        return true  ; Let backspace through
    }
    
    ; === DELETE (0x2E) ===
    if vk = 0x2E {
        ; Delete key behavior in RTL is complex - just reset buffer
        g_Buffer := ""
        return true
    }
    
    ; === ENTER (0x0D) ===
    if vk = 0x0D {
        g_Buffer := ""
        return true
    }
    
    ; === ESCAPE (0x1B) ===
    if vk = 0x1B {
        g_Buffer := ""
        return true
    }
    
    ; === TAB (0x09) ===
    if vk = 0x09 {
        g_Buffer := ""
        return true
    }
    
    ; === ARROW KEYS (0x25-0x28) ===
    if vk >= 0x25 && vk <= 0x28 {
        ; Arrow movement invalidates our buffer tracking
        g_Buffer := ""
        return true
    }
    
    ; === HOME (0x24) / END (0x23) ===
    if vk = 0x24 || vk = 0x23 {
        g_Buffer := ""
        return true
    }
    
    ; === PAGE UP (0x21) / PAGE DOWN (0x22) ===
    if vk = 0x21 || vk = 0x22 {
        g_Buffer := ""
        return true
    }
    
    return true  ; Let all other keys through
}

; =============================================================================
; HOTKEYS
; =============================================================================

; Global toggle hotkey
^!h::ToggleMode()

; =============================================================================
; PASTE HANDLER
; =============================================================================

#HotIf g_Enabled && IsAffinityActive()

; Smart paste - only reverse Hebrew portions
^v::{
    global g_Buffer
    
    originalClip := A_Clipboard
    
    ; Check if clipboard contains Hebrew
    if !ContainsHebrew(originalClip) {
        ; No Hebrew - paste normally
        Send("^v")
        return
    }
    
    ; Smart reverse: reverse Hebrew segments, keep English/numbers in place
    processed := SmartReverse(originalClip)
    
    ; Temporarily set clipboard and paste
    A_Clipboard := processed
    ClipWait(1)
    Send("^v")
    
    ; Restore original clipboard after delay
    Sleep(100)
    A_Clipboard := originalClip
    
    ; Reset buffer (pasted text is separate from typed text)
    g_Buffer := ""
}

; Ctrl+A - Select All resets buffer (cursor position unknown after)
^a::{
    global g_Buffer
    g_Buffer := ""
    Send("^a")
}

; Ctrl+Z - Undo resets buffer
^z::{
    global g_Buffer
    g_Buffer := ""
    Send("^z")
}

; Ctrl+Y - Redo resets buffer
^y::{
    global g_Buffer
    g_Buffer := ""
    Send("^y")
}

#HotIf

; =============================================================================
; END OF SCRIPT
; =============================================================================
