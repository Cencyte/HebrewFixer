; HebrewFixer Installer Script for Inno Setup 6
; RTL Hebrew typing support for Affinity Designer
; https://github.com/Cencyte/HebrewFixer

[Setup]
AppName=HebrewFixer
AppVersion=1.0.0
AppVerName=HebrewFixer 1.0.0
AppPublisher=Cencyte
AppPublisherURL=https://github.com/Cencyte/HebrewFixer
AppSupportURL=https://github.com/Cencyte/HebrewFixer/issues
AppUpdatesURL=https://github.com/Cencyte/HebrewFixer/releases
; Install to %LOCALAPPDATA%\HebrewFixer (user-level, no admin required)
DefaultDirName={localappdata}\HebrewFixer
DefaultGroupName=HebrewFixer
OutputDir=..\bin
OutputBaseFilename=HebrewFixer_Setup
SetupIconFile=..\Icon\ICOs\hebrew_fixer_affinity_on.ico
UninstallDisplayIcon={app}\HebrewFixer.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; No admin privileges required - installs per-user
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Uninstall settings
UninstallDisplayName=HebrewFixer
CreateUninstallRegKey=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startmenu"; Description: "Create a Start Menu entry"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "Start HebrewFixer automatically when Windows starts"; GroupDescription: "Startup Options:"
Name: "trayvisible"; Description: "Always show HebrewFixer icon in the system tray (recommended)"; GroupDescription: "System Tray:"

[Files]
; Main executable (from bin folder)
Source: "..\bin\HebrewFixer.exe"; DestDir: "{app}"; Flags: ignoreversion

; Icons for tray (ON and OFF states) - script looks for these in its directory
Source: "..\Icon\ICOs\hebrew_fixer_affinity_on.ico"; DestDir: "{app}"; DestName: "hebrew_fixer_on.ico"; Flags: ignoreversion
Source: "..\Icon\ICOs\hebrew_fixer_affinity_off.ico"; DestDir: "{app}"; DestName: "hebrew_fixer_off.ico"; Flags: ignoreversion

[Icons]
; Start Menu entries (optional)
Name: "{group}\HebrewFixer"; Filename: "{app}\HebrewFixer.exe"; IconFilename: "{app}\hebrew_fixer_on.ico"; Tasks: startmenu
Name: "{group}\Uninstall HebrewFixer"; Filename: "{uninstallexe}"; Tasks: startmenu
; Desktop shortcut (optional)
Name: "{autodesktop}\HebrewFixer"; Filename: "{app}\HebrewFixer.exe"; IconFilename: "{app}\hebrew_fixer_on.ico"; Tasks: desktopicon
; Startup folder entry (runs at Windows startup)
Name: "{userstartup}\HebrewFixer"; Filename: "{app}\HebrewFixer.exe"; Tasks: startup

[Registry]
; Make tray icon always visible in Windows 10/11 notification area
; This sets the "Promote" value for the HebrewFixer.exe to always show in tray
; Key: HKCU\Control Panel\NotifyIconSettings\<hash>
; Unfortunately, Windows generates a unique hash per executable path, so we use a different approach:
; We add to the "Past Icons Stream" / user preference via a run-once script instead
; For now, we'll document this as a manual step or use the alternative explorer shell approach

; Alternative: Add to "always show" via TrayNotify (requires binary manipulation - not reliable)
; Instead, we'll create a simple notification on first run asking user to pin the icon

[Run]
; Launch after installation
Filename: "{app}\HebrewFixer.exe"; Description: "Launch HebrewFixer"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Clean up any generated files
Type: files; Name: "{app}\*.log"
Type: dirifempty; Name: "{app}"

[Code]
// Show a message about pinning the tray icon if user selected that option
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if WizardIsTaskSelected('trayvisible') then
    begin
      MsgBox('To keep HebrewFixer visible in your system tray:' + #13#10 + #13#10 +
             '1. Click the ^ arrow in your taskbar (bottom-right)' + #13#10 +
             '2. Find the HebrewFixer icon (Hebrew letter Shin)' + #13#10 +
             '3. Drag it onto your taskbar' + #13#10 + #13#10 +
             'This ensures you can always see when Hebrew mode is active.',
             mbInformation, MB_OK);
    end;
  end;
end;
