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
; SetupIconFile=..\Icon\ICOs\hebrew_fixer_affinity_on.ico
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
Name: "launchapp"; Description: "Launch HebrewFixer now"; GroupDescription: "After Installation:"

[Files]
; Main executable (from bin folder)
Source: "..\bin\HebrewFixer.exe"; DestDir: "{app}"; DestName: "HebrewFixer1998.exe"; Flags: ignoreversion

; Win11 tray icon promotion helper (registry-only, no GUI)
Source: "..\\Tests\\Win11\\Set-NotificationAreaIconBehavior-Win11-3.ps1"; DestDir: "{app}\\InstallerTools"; DestName: "Set-NotificationAreaIconBehavior-Win11-3-INSTALLER.ps1"; Flags: ignoreversion overwritereadonly

; Icons for tray (ON and OFF states)
Source: "..\Icon\ICOs\hebrew_fixer_affinity_on.ico"; DestDir: "{app}"; DestName: "hebrew_fixer_on.ico"; Flags: ignoreversion
Source: "..\Icon\ICOs\hebrew_fixer_affinity_off.ico"; DestDir: "{app}"; DestName: "hebrew_fixer_off.ico"; Flags: ignoreversion

[Registry]
; Marker used to know whether THIS installer applied tray promotion, so we can safely revert.
; On uninstall, we delete the whole HKCU\Software\HebrewFixer key (see entry below).
Root: HKCU; Subkey: "Software\HebrewFixer"; ValueType: dword; ValueName: "TrayVisibleApplied"; ValueData: "0"; Flags: uninsdeletevalue

; Ensure no installer marker remains after uninstall.
Root: HKCU; Subkey: "Software\HebrewFixer"; Flags: uninsdeletekey

[Icons]
; Start Menu entries (optional)
Name: "{group}\HebrewFixer"; Filename: "{app}\HebrewFixer1998.exe"; IconFilename: "{app}\hebrew_fixer_on.ico"; Tasks: startmenu
Name: "{group}\Uninstall HebrewFixer"; Filename: "{uninstallexe}"; Tasks: startmenu
; Desktop shortcut (optional)
Name: "{autodesktop}\HebrewFixer"; Filename: "{app}\HebrewFixer1998.exe"; IconFilename: "{app}\hebrew_fixer_on.ico"; Tasks: desktopicon
; Startup folder entry (runs at Windows startup)
Name: "{userstartup}\HebrewFixer"; Filename: "{app}\HebrewFixer1998.exe"; Tasks: startup

[UninstallDelete]
; Clean up any generated files
Type: files; Name: "{app}\*.log"
Type: filesandordirs; Name: "{app}\InstallerTools"
; Remove entire install dir even if not empty (user-level install directory)
Type: filesandordirs; Name: "{app}"

[Code]

function InstallLogPath(): String;
begin
  Result := ExpandConstant('{userappdata}\\HebrewFixer\\InstallLogs\\installer_debug.log');
end;

procedure LogLine(Msg: String);
var
  L: String;
begin
  ForceDirectories(ExpandConstant('{userappdata}\\HebrewFixer\\InstallLogs'));
  L := GetDateTimeString('yyyy-mm-dd hh:nn:ss.zzz', '-', ':') + ' | ' + Msg + #13#10;
  SaveStringToFile(InstallLogPath(), L, True);
end;

function CmdWrapPowerShell(PSExe, Args: String): String;
begin
  // Robust cmd.exe quoting:
  // cmd /c ""<PSExe>" <Args> 1>>"<log>" 2>>&1"
  Result := '/c ""' + PSExe + '" ' + Args + ' 1>>"' + InstallLogPath() + '" 2>>&1"';
end;

function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  LogLine('InitializeSetup: start | BUILD=DEBUG_LOG_V2');
  // Kill any running HebrewFixer processes before installation
  Exec('taskkill.exe', '/F /IM HebrewFixer1998.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  LogLine('InitializeSetup: taskkill result=' + IntToStr(ResultCode));
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
  PSExe: String;
  PSScript: String;
  Args: String;
  Marker: Cardinal;
begin
  LogLine('CurUninstallStepChanged: step=' + IntToStr(Ord(CurUninstallStep)));
  if CurUninstallStep = usUninstall then
  begin
    LogLine('UNINSTALL: entered');
    // On uninstall, revert tray promotion unconditionally (uninstall should leave no pinned state behind).
    // We still keep the marker for install-time decisions, but uninstall always tries to revert.
    PSExe := ExpandConstant('{sys}\\WindowsPowerShell\\v1.0\\powershell.exe');
    PSScript := ExpandConstant('{app}\\InstallerTools\\Set-NotificationAreaIconBehavior-Win11-3.ps1');
    Args :=
      '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + PSScript + '" ' +
      '-Match "HebrewFixer1998.exe" -LiteralMatch -DesiredSetting 0 -FailIfMissing 0 ' +
      '-LogPath "' + InstallLogPath() + '"';
    LogLine('UNINSTALL: running tray revert');
    LogLine('UNINSTALL: PSExe=' + PSExe);
    LogLine('UNINSTALL: Args=' + Args);
    // Run via cmd.exe so stdout+stderr are appended to installer_debug.log
    Exec('cmd.exe', CmdWrapPowerShell(PSExe, Args), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    LogLine('UNINSTALL: Exec result=' + IntToStr(ResultCode));

    // Best-effort reset marker (key itself is removed by uninsdeletekey).
    RegWriteDWordValue(HKEY_CURRENT_USER, 'Software\\HebrewFixer', 'TrayVisibleApplied', 0);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  ExePath: String;
  PSExe: String;
  PSScript: String;
  Args: String;
  Marker: Cardinal;
begin
  LogLine('CurStepChanged: step=' + IntToStr(Ord(CurStep)));
  if CurStep = ssPostInstall then
  begin
    LogLine('POSTINSTALL: entered');
    LogLine('POSTINSTALL: trayvisible=' + IntToStr(Ord(WizardIsTaskSelected('trayvisible'))) + ', launchapp=' + IntToStr(Ord(WizardIsTaskSelected('launchapp'))) + ', startup=' + IntToStr(Ord(WizardIsTaskSelected('startup'))));
    ExePath := ExpandConstant('{app}\\HebrewFixer1998.exe');

    // Apply Win11 tray icon pinning ONLY if user selected it
    if WizardIsTaskSelected('trayvisible') then
    begin
      // ------------------------------------------------------------------
      // Win11 tray icon pinning (zero-GUI approach)
      //
      // Installer requirement:
      // - Do NOT launch HebrewFixer during install (can flash UI / appear on taskbar).
      //
      // Instead:
      // - Apply the HKCU NotifyIconSettings IsPromoted=1 setting if the entry already exists.
      // - If no entry exists yet, this is non-fatal; the user can launch HebrewFixer once and
      //   re-run a "Repair" later (or we can add a self-healing check at app startup).
      // ------------------------------------------------------------------

      PSExe := ExpandConstant('{sys}\\WindowsPowerShell\\v1.0\\powershell.exe');
      PSScript := ExpandConstant('{app}\\InstallerTools\\Set-NotificationAreaIconBehavior-Win11-3.ps1');

      // Do not fail install if the entry isn't present yet; log will show it.
      Args :=
        '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + PSScript + '" ' +
        '-Match "HebrewFixer1998.exe" -LiteralMatch -DesiredSetting 1 -FailIfMissing 0 ' +
        '-LogPath "' + InstallLogPath() + '"';

      LogLine('INSTALL: trayvisible checked; running promotion');
      LogLine('INSTALL: PSExe=' + PSExe);
      LogLine('INSTALL: Args=' + Args);
      // Run via cmd.exe so stdout+stderr are appended to installer_debug.log
      Exec('cmd.exe', CmdWrapPowerShell(PSExe, Args), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      LogLine('INSTALL: Exec result=' + IntToStr(ResultCode));

      // Record that we applied tray promotion
      RegWriteDWordValue(HKEY_CURRENT_USER, 'Software\\HebrewFixer', 'TrayVisibleApplied', 1);
    end
    else
    begin
      // If user UNchecked trayvisible but we had previously applied it, revert to default (IsPromoted=0)
      if RegQueryDWordValue(HKEY_CURRENT_USER, 'Software\\HebrewFixer', 'TrayVisibleApplied', Marker) and (Marker = 1) then
      begin
        PSExe := ExpandConstant('{sys}\\WindowsPowerShell\\v1.0\\powershell.exe');
        PSScript := ExpandConstant('{app}\\InstallerTools\\Set-NotificationAreaIconBehavior-Win11-3.ps1');
        Args :=
          '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + PSScript + '" ' +
          '-Match "HebrewFixer1998.exe" -LiteralMatch -DesiredSetting 0 -FailIfMissing 0 ' +
          '-LogPath "' + InstallLogPath() + '"';

        LogLine('INSTALL: trayvisible unchecked but marker=1; running revert');
        LogLine('INSTALL: PSExe=' + PSExe);
        LogLine('INSTALL: Args=' + Args);
        // Run via cmd.exe so stdout+stderr are appended to installer_debug.log
        Exec('cmd.exe', CmdWrapPowerShell(PSExe, Args), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
        LogLine('INSTALL: Exec result=' + IntToStr(ResultCode));

        // Reset marker
        RegWriteDWordValue(HKEY_CURRENT_USER, 'Software\\HebrewFixer', 'TrayVisibleApplied', 0);
      end;
    end;

    // Launch app if user requested it
    if WizardIsTaskSelected('launchapp') then
    begin
      Exec(ExePath, '', '', SW_SHOW, ewNoWait, ResultCode);
    end;
  end;
end;

