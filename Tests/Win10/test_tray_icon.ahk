; Minimal AHK v2 script - ONLY creates a tray icon, does nothing else
; This tests default Windows behavior for new tray icons

#Requires AutoHotkey v2.0
Persistent

; Set our icon
iconPath := A_ScriptDir . "\Icon\ICOs\hebrew_fixer_affinity_on.ico"
if FileExist(iconPath) {
    TraySetIcon(iconPath)
}

; Set tooltip
A_IconTip := "Test Tray Icon"

; Simple tray menu
A_TrayMenu.Delete()
A_TrayMenu.Add("Exit", (*) => ExitApp())
