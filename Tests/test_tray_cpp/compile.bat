@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
cd /d "C:\Users\FireSongz\Desktop\HebrewFixer\test_tray_cpp"
cl /EHsc /Fe:TestTray_Cpp.exe test_tray.cpp shell32.lib user32.lib
