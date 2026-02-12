; AHK v1 script - point at the window/surface you want hidden, press Ctrl+Alt+T
; Ctrl+Alt+R restores (disables the accent)
; Save as HideDCompSurface.ahk and run.

#NoEnv
SendMode Input
SetWorkingDir %A_ScriptDir%
SetBatchLines -1

; ---------- Helpers ----------
GetHwndUnderMouse() {
    MouseGetPos,,, hwnd
    return hwnd
}

ApplyAccent(hwnd, accentState, gradientColor := 0x00000000) {
    ; ACCENT_POLICY { int AccentState; int AccentFlags; int GradientColor; int AnimationId; }
    ; WINDOWCOMPOSITIONATTRIBDATA { int Attribute; PVOID Data; int SizeOfData; }
    GWL := -20

    ; build ACCENT_POLICY (12 bytes)
    VarSetCapacity(acc, 12, 0)
    NumPut(accentState, acc, 0, "UInt")          ; AccentState
    NumPut(0, acc, 4, "UInt")                    ; AccentFlags
    NumPut(gradientColor, acc, 8, "UInt")        ; GradientColor (ARGB)

    ; build WINDOWCOMPOSITIONATTRIBDATA
    ; Attribute = 19 (WCA_ACCENT_POLICY)
    VarSetCapacity(data, (4 + A_PtrSize + 4), 0)
    NumPut(19, data, 0, "UInt")                  ; Attribute = WCA_ACCENT_POLICY
    ; pointer to acc
    if (A_PtrSize = 8)
        NumPut(NumGet(acc, 0, "Ptr"), data, 4, "Ptr")
    else
        NumPut(&acc, data, 4, "UInt")
    NumPut(12, data, 4 + A_PtrSize, "UInt")     ; SizeOfData = sizeof(ACCENT_POLICY)=12

    ; call SetWindowCompositionAttribute
    ; BOOL SetWindowCompositionAttribute(HWND, WINDOWCOMPOSITIONATTRIBDATA*)
    ret := DllCall("user32.dll\SetWindowCompositionAttribute", "Ptr", hwnd, "Ptr", &data)
    return ret
}

; ---------- Hotkeys ----------
^!t::   ; Ctrl+Alt+T -> make window under mouse fully transparent
{
    hwnd := GetHwndUnderMouse()
    if (!hwnd) {
        MsgBox, 48, Error, Couldn't find a window under mouse.
        return
    }
    ; Try a sequence that tends to produce full transparency:
    ; 2 = ACCENT_ENABLE_TRANSPARENTGRADIENT (transparent)
    ; 3 = ACCENT_ENABLE_BLURBEHIND (sometimes gives best invisibility when DComp is in play)
    ; For transparent ARGB, set alpha byte to 0 (0x00RRGGBB)
    ; Here we set gradientColor = 0x00000000 (fully transparent)
    if (ApplyAccent(hwnd, 2, 0x00000000)) {
        TrayTip, HideSurface, Applied ACCENT_ENABLE_TRANSPARENTGRADIENT to hwnd %hwnd%, 2000
    } else if (ApplyAccent(hwnd, 3, 0x00000000)) {
        TrayTip, HideSurface, Applied ACCENT_ENABLE_BLURBEHIND to hwnd %hwnd%, 2000
    } else {
        ; fallback to layered alpha (if surface responds)
        ; set WS_EX_LAYERED then SetLayeredWindowAttributes to alpha 0
        GWL_EXSTYLE := -20
        WS_EX_LAYERED := 0x80000
        LWA_ALPHA := 0x2
        style := DllCall("GetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Int")
        DllCall("SetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Int", style | WS_EX_LAYERED)
        ok := DllCall("user32.dll\SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0, "UChar", 0, "UInt", LWA_ALPHA)
        if (ok) {
            TrayTip, HideSurface, Applied layered alpha to hwnd %hwnd%, 2000
        } else {
            MsgBox, 48, Failed, Couldn't force transparency on hwnd %hwnd% (ret=%ok%).
        }
    }
    return
}

^!r::   ; Ctrl+Alt+R -> restore (disable accent)
{
    hwnd := GetHwndUnderMouse()
    if (!hwnd) {
        MsgBox, 48, Error, Couldn't find a window under mouse.
        return
    }
    ; Disable accent (AccentState = 0)
    if (ApplyAccent(hwnd, 0, 0x00000000)) {
        TrayTip, HideSurface, Restored composition attributes for hwnd %hwnd%, 2000
    } else {
        ; try removing layered style
        GWL_EXSTYLE := -20
        WS_EX_LAYERED := 0x80000
        style := DllCall("GetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Int")
        newStyle := style & ~WS_EX_LAYERED
        DllCall("SetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Int", newStyle)
        TrayTip, HideSurface, Cleared WS_EX_LAYERED for hwnd %hwnd%, 2000
    }
    return
}

; Help hotkey
^!h::MsgBox, 64, Usage, Hover the mouse over the D3D surface (Notification Area Icons content) and press ^!T to make it transparent. Press ^!R to restore.
