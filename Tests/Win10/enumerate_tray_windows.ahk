; AHK v1 - Enumerate all windows that might be the Notification Area Icons dialog
; Press Ctrl+Alt+E to enumerate

#NoEnv
SendMode Input
SetBatchLines -1

^!e::
{
    results := ""
    
    ; Method 1: Look for CabinetWClass with title containing "Notification"
    results .= "=== Method 1: CabinetWClass with Notification title ===`n"
    WinGet, idList, List, ahk_class CabinetWClass ahk_exe explorer.exe
    Loop, %idList% {
        this_id := idList%A_Index%
        WinGetTitle, title, ahk_id %this_id%
        if (InStr(title, "Notification")) {
            results .= "  HWND: " . this_id . " Title: " . title . "`n"
            
            ; Enumerate children
            results .= "  Children:`n"
            WinGet, childList, ControlListHwnd, ahk_id %this_id%
            Loop, Parse, childList, `n
            {
                childHwnd := A_LoopField
                WinGetClass, childClass, ahk_id %childHwnd%
                results .= "    Child HWND: " . childHwnd . " Class: " . childClass . "`n"
            }
        }
    }
    
    ; Method 2: Look for any window with "Notification Area" in title
    results .= "`n=== Method 2: Any window with 'Notification Area' title ===`n"
    WinGet, allList, List
    Loop, %allList% {
        this_id := allList%A_Index%
        WinGetTitle, title, ahk_id %this_id%
        if (InStr(title, "Notification Area")) {
            WinGetClass, class, ahk_id %this_id%
            WinGet, proc, ProcessName, ahk_id %this_id%
            results .= "  HWND: " . this_id . " Class: " . class . " Process: " . proc . " Title: " . title . "`n"
        }
    }
    
    ; Method 3: Use FindWindow for specific class names
    results .= "`n=== Method 3: FindWindow for known classes ===`n"
    classes := ["CabinetWClass", "Intermediate D3D Window", "DirectUIHWND", "DUIViewWndClassName"]
    for i, className in classes {
        hwnd := DllCall("FindWindow", "Str", className, "Ptr", 0, "Ptr")
        if (hwnd) {
            WinGetTitle, title, ahk_id %hwnd%
            results .= "  Class: " . className . " HWND: " . hwnd . " Title: " . title . "`n"
        }
    }
    
    ; Method 4: EnumWindows approach - find all explorer.exe windows
    results .= "`n=== Method 4: All explorer.exe windows ===`n"
    WinGet, expList, List, ahk_exe explorer.exe
    Loop, %expList% {
        this_id := expList%A_Index%
        WinGetTitle, title, ahk_id %this_id%
        WinGetClass, class, ahk_id %this_id%
        if (title != "" || class = "CabinetWClass") {
            results .= "  HWND: " . this_id . " Class: " . class . " Title: " . title . "`n"
        }
    }
    
    ; Show results
    MsgBox, 0, Window Enumeration Results, %results%
    return
}
