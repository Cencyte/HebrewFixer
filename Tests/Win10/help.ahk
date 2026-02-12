#NoEnv
SendMode Input
SetBatchLines -1

ApplyAccent(hwnd, state) {
    VarSetCapacity(acc, 12, 0)
    NumPut(state, acc, 0, "UInt")
    VarSetCapacity(data, (4 + A_PtrSize + 4), 0)
    NumPut(19, data, 0, "UInt")
    if (A_PtrSize = 8)
        NumPut(NumGet(acc, 0, "Ptr"), data, 4, "Ptr")
    else
        NumPut(&acc, data, 4, "UInt")
    NumPut(12, data, 4 + A_PtrSize, "UInt")
    return DllCall("user32.dll\SetWindowCompositionAttribute", "Ptr", hwnd, "Ptr", &data)
}

GetExplorerTraySettings() {
    WinGet, idList, List, ahk_class CabinetWClass ahk_exe explorer.exe
    Loop, %idList% {
        this_id := idList%A_Index%
        WinGetTitle, title, ahk_id %this_id%
        if InStr(title, "Notification Area Icons")
            return this_id
    }
    return 0
}

^!t::
{
    parent := GetExplorerTraySettings()
    if (!parent) {
        MsgBox, 48, Error, Tray settings window not open.
        return
    }

    WinGet, childList, ControlListHwnd, ahk_id %parent%

    Loop, Parse, childList, `n
    {
        thisHwnd := A_LoopField
        ; try applying transparent accent
        if (ApplyAccent(thisHwnd, 2)) {
            ToolTip Found DComp surface:`nHWND %thisHwnd%
            return
        }
    }

    MsgBox, 48, Failed, No valid composition surface accepted accent.
    return
}

^!r::
{
    parent := GetExplorerTraySettings()
    if (!parent)
        return

    WinGet, childList, ControlListHwnd, ahk_id %parent%
    Loop, Parse, childList, `n
        ApplyAccent(A_LoopField, 0)

    ToolTip Restored.
    return
}
