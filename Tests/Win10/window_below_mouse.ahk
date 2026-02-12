^!8::
MouseGetPos,,, winID, controlHwnd, 2
WinGetClass, class, ahk_id %winID%
WinGetTitle, title, ahk_id %winID%
WinGet, process, ProcessName, ahk_id %winID%
WinGet, pid, PID, ahk_id %winID%
WinGet, style, Style, ahk_id %winID%
WinGet, exstyle, ExStyle, ahk_id %winID%

info =
(
HWND: %winID%
Control HWND: %controlHwnd%

Title: %title%
Class: %class%
Process: %process%
PID: %pid%

Style: %style%
ExStyle: %exstyle%
)

MsgBox %info%
return
