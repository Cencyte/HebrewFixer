; Makes the Notification Area Icons window transparent
; Ctrl+Alt+T to apply transparency
; Ctrl+Alt+R to restore
; Ctrl+Alt+I for info

#NoEnv
SendMode Input
SetWorkingDir %A_ScriptDir%
SetBatchLines -1

; ========== CONFIGURATION ==========
; Transparency percentage (0 = fully transparent, 100 = fully opaque)
global TransparencyPercent := 50

; Convert percentage to alpha (0-255)
GetAlphaFromPercent(percent) {
    return Round((percent / 100) * 255)
}

; ========== WINDOW FINDING ==========
GetNotificationAreaIconsWindow() {
    WinGet, idList, List, ahk_class CabinetWClass ahk_exe explorer.exe
    Loop, %idList% {
        this_id := idList%A_Index%
        WinGetTitle, title, ahk_id %this_id%
        if (InStr(title, "Notification Area Icons")) {
            return this_id
        }
    }
    return 0
}

; Get ALL child windows
EnumAllChildren(parentHwnd, ByRef childList) {
    WinGet, directChildren, ControlListHwnd, ahk_id %parentHwnd%
    Loop, Parse, directChildren, `n
    {
        if (A_LoopField = "")
            continue
        childList.Push(A_LoopField)
    }
}

; ========== TRANSPARENCY FUNCTIONS ==========
MakeTransparent(hwnd, alphaValue) {
    GWL_EXSTYLE := -20
    WS_EX_LAYERED := 0x80000
    LWA_ALPHA := 0x2
    
    style := DllCall("GetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Int")
    DllCall("SetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Int", style | WS_EX_LAYERED)
    return DllCall("user32.dll\SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0, "UChar", alphaValue, "UInt", LWA_ALPHA)
}

RestoreOpacity(hwnd) {
    GWL_EXSTYLE := -20
    WS_EX_LAYERED := 0x80000
    LWA_ALPHA := 0x2
    
    ; Set alpha back to 255 (fully opaque)
    DllCall("user32.dll\SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0, "UChar", 255, "UInt", LWA_ALPHA)
    
    ; Remove layered style
    style := DllCall("GetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Int")
    DllCall("SetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Int", style & ~WS_EX_LAYERED)
}

; ========== HOTKEYS ==========

; Ctrl+Alt+T - Make transparent
^!t::
{
    parentHwnd := GetNotificationAreaIconsWindow()
    if (!parentHwnd) {
        MsgBox, 48, Error, Notification Area Icons window not found.`n`nOpen it with: shell:::{05d7b0f4-2121-4eff-bf6b-ed3f69b894d9}
        return
    }
    
    alpha := GetAlphaFromPercent(TransparencyPercent)
    
    ; Get all child windows
    children := []
    EnumAllChildren(parentHwnd, children)
    
    ; Make parent transparent
    MakeTransparent(parentHwnd, alpha)
    
    ; Make all children transparent
    childCount := 0
    for i, childHwnd in children {
        MakeTransparent(childHwnd, alpha)
        childCount++
    }
    
    TrayTip, Transparency Applied, Made window %TransparencyPercent%`% transparent (%childCount% children)., 2000
    return
}

; Ctrl+Alt+R - Restore opacity
^!r::
{
    parentHwnd := GetNotificationAreaIconsWindow()
    if (!parentHwnd) {
        MsgBox, 48, Error, Notification Area Icons window not found.
        return
    }
    
    ; Get all child windows
    children := []
    EnumAllChildren(parentHwnd, children)
    
    ; Restore parent
    RestoreOpacity(parentHwnd)
    
    ; Restore all children
    childCount := 0
    for i, childHwnd in children {
        RestoreOpacity(childHwnd)
        childCount++
    }
    
    TrayTip, Restored, Opacity restored to all %childCount% windows., 2000
    return
}

; Ctrl+Alt+I - Info/Help
^!i::
{
    MsgBox, 64, Transparency Tool, 
(
Notification Area Icons Transparency Tool

Current transparency: %TransparencyPercent%`%

Hotkeys:
  Ctrl+Alt+T - Apply transparency
  Ctrl+Alt+R - Restore opacity
  Ctrl+Alt+D - Debug (show child windows)
  Ctrl+Alt+I - This help

To open the target window:
  Win+R -> shell:::{05d7b0f4-2121-4eff-bf6b-ed3f69b894d9}
)
    return
}

; Ctrl+Alt+D - Debug
^!d::
{
    parentHwnd := GetNotificationAreaIconsWindow()
    if (!parentHwnd) {
        MsgBox, 48, Error, Window not found.
        return
    }
    
    children := []
    EnumAllChildren(parentHwnd, children)
    
    result := "Parent HWND: " . parentHwnd . "`n`nChildren (" . children.Length() . "):`n"
    for i, childHwnd in children {
        WinGetClass, cls, ahk_id %childHwnd%
        result .= i . ": " . childHwnd . " - " . cls . "`n"
        if (i > 25) {
            result .= "... (truncated, " . children.Length() . " total)`n"
            break
        }
    }
    
    MsgBox, 0, Debug - Child Windows, %result%
    return
}
