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

; Invisible tray icon promotion script (based on Win11-2, with registry positioning)
Source: "..\\Tests\\Win11\\PromoteTrayIconInvisible.ps1"; DestDir: "{app}\\InstallerTools"; Flags: ignoreversion overwritereadonly uninsremovereadonly

; Icons for tray (ON and OFF states)
Source: "..\Icon\ICOs\hebrew_fixer_affinity_on.ico"; DestDir: "{app}"; DestName: "hebrew_fixer_on.ico"; Flags: ignoreversion
Source: "..\Icon\ICOs\hebrew_fixer_affinity_off.ico"; DestDir: "{app}"; DestName: "hebrew_fixer_off.ico"; Flags: ignoreversion

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

// Constants
const
  HWND_TOPMOST = -1;
  SWP_NOSIZE = 1;
  SWP_NOMOVE = 2;
  SWP_SHOWWINDOW = $40;

// Win32 API functions (TRect is already defined in Inno Setup)
function SetWindowPos(hWnd: HWND; hWndInsertAfter: HWND; X: Integer; Y: Integer;
  cx: Integer; cy: Integer; uFlags: UINT): BOOL;
  external 'SetWindowPos@user32.dll stdcall';

function GetWindowRect(hWnd: HWND; var lpRect: TRect): BOOL;
  external 'GetWindowRect@user32.dll stdcall';

procedure InitializeWizard;
begin
  // Make the installer window always-on-top
  SetWindowPos(WizardForm.Handle, HWND_TOPMOST, 0, 0, 0, 0, 
    SWP_NOSIZE or SWP_NOMOVE or SWP_SHOWWINDOW);
end;

function InstallLogPath(): String;
begin
  Result := ExpandConstant('{userappdata}\\HebrewFixer\\InstallLogs\\installer_debug.log');
end;

function InstallPSLogPath(): String;
begin
  Result := ExpandConstant('{userappdata}\\HebrewFixer\\InstallLogs\\installer_debug_ps.log');
end;

procedure LogLine(Msg: String); forward;

procedure AppendPSLogToMain(Phase: String);
var
  S: AnsiString;
  L: String;
begin
  if LoadStringFromFile(InstallPSLogPath(), S) then
  begin
    L := GetDateTimeString('yyyy-mm-dd hh:nn:ss.zzz', '-', ':') + ' | ' + Phase + ': begin powershell log dump' + #13#10;
    SaveStringToFile(InstallLogPath(), L, True);
    SaveStringToFile(InstallLogPath(), String(S), True);
    L := GetDateTimeString('yyyy-mm-dd hh:nn:ss.zzz', '-', ':') + ' | ' + Phase + ': end powershell log dump' + #13#10;
    SaveStringToFile(InstallLogPath(), L, True);
  end
  else
  begin
    LogLine(Phase + ': no powershell log file found at ' + InstallPSLogPath());
  end;
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
  Result := '/c ""' + PSExe + '" ' + Args + ' 1>>"' + InstallPSLogPath() + '" 2>>&1"';
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

    // Ensure app is not running; otherwise uninstaller may fail to remove files/dirs.
    Exec('taskkill.exe', '/F /IM HebrewFixer1998.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    LogLine('UNINSTALL: taskkill HebrewFixer1998.exe result=' + IntToStr(ResultCode));

    // On uninstall, revert tray promotion unconditionally (uninstall should leave no pinned state behind).
    // We still keep the marker for install-time decisions, but uninstall always tries to revert.
    PSExe := ExpandConstant('{sys}\\WindowsPowerShell\\v1.0\\powershell.exe');
    PSScript := ExpandConstant('{app}\\InstallerTools\\PromoteTrayIconInvisible.ps1');
    Args :=
      '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + PSScript + '" ' +
      '-AppName "HebrewFixer1998.exe" -CleanupRegistry ' +
      '-LogPath "' + InstallPSLogPath() + '"';
    LogLine('UNINSTALL: running tray revert');
    LogLine('UNINSTALL: PSExe=' + PSExe);
    LogLine('UNINSTALL: Args=' + Args);
    // Run via cmd.exe so stdout+stderr are appended to installer_debug.log
    Exec('cmd.exe', CmdWrapPowerShell(PSExe, Args), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    LogLine('UNINSTALL: Exec result=' + IntToStr(ResultCode));
AppendPSLogToMain('UNINSTALL');

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
  WinRect: TRect;
  WinX, WinY, WinWidth, WinHeight: Integer;
begin
  LogLine('CurStepChanged: step=' + IntToStr(Ord(CurStep)));
  if CurStep = ssPostInstall then
  begin
    LogLine('POSTINSTALL: entered');
    LogLine('POSTINSTALL: trayvisible=' + IntToStr(Ord(WizardIsTaskSelected('trayvisible'))) + ', launchapp=' + IntToStr(Ord(WizardIsTaskSelected('launchapp'))) + ', startup=' + IntToStr(Ord(WizardIsTaskSelected('startup'))));
    ExePath := ExpandConstant('{app}\\HebrewFixer1998.exe');

    // Step 1: Launch HebrewFixer FIRST (hidden) so Windows registers it as a tray app
    LogLine('INSTALL: Launching HebrewFixer (hidden) to register with Windows...');
    Exec(ExePath, '/NoTooltip', '', SW_HIDE, ewNoWait, ResultCode);
    LogLine('INSTALL: HebrewFixer launched (hidden, /NoTooltip), waiting briefly for tray registration...');
    // Tight wait budget (<= 1s total)
    Sleep(500);
    Sleep(500);

    // Step 2: Run tray icon script (Settings spawns invisibly behind installer)
    // Pass -HideIcon if checkbox is unchecked
    if GetWindowRect(WizardForm.Handle, WinRect) then
    begin
      WinX := WinRect.Left;
      WinY := WinRect.Top;
      WinWidth := WinRect.Right - WinRect.Left;
      WinHeight := WinRect.Bottom - WinRect.Top;

      LogLine('INSTALL: Installer bounds: X=' + IntToStr(WinX) + ', Y=' + IntToStr(WinY) + 
              ', Width=' + IntToStr(WinWidth) + ', Height=' + IntToStr(WinHeight));

      PSExe := ExpandConstant('{sys}\\WindowsPowerShell\\v1.0\\powershell.exe');
      PSScript := ExpandConstant('{app}\\InstallerTools\\PromoteTrayIconInvisible.ps1');

      Args :=
        '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + PSScript + '" ' +
        '-InstallerX ' + IntToStr(WinX) + ' ' +
        '-InstallerY ' + IntToStr(WinY) + ' ' +
        '-InstallerWidth ' + IntToStr(WinWidth) + ' ' +
        '-InstallerHeight ' + IntToStr(WinHeight) + ' ' +
        '-AppName \"HebrewFixer1998.exe\" -CleanupRegistry';

      // Add -HideIcon if checkbox is unchecked
      if not WizardIsTaskSelected('trayvisible') then
      begin
        Args := Args + ' -HideIcon';
        LogLine('INSTALL: trayvisible unchecked; will HIDE icon from tray');
      end
      else
      begin
        LogLine('INSTALL: trayvisible checked; will SHOW icon in tray');
      end;

      LogLine('INSTALL: PSExe=' + PSExe);
      LogLine('INSTALL: Args=' + Args);

      // Run via cmd.exe so stdout+stderr are appended to installer_debug.log
      Exec('cmd.exe', CmdWrapPowerShell(PSExe, Args), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      LogLine('INSTALL: Exec result=' + IntToStr(ResultCode));
      AppendPSLogToMain('INSTALL');
    end
    else
    begin
      LogLine('INSTALL: ERROR - GetWindowRect failed, cannot get installer position');
    end;

    // Step 3: If user wants app visible, bring it to foreground (it's already running from Step 1)
    if WizardIsTaskSelected('launchapp') then
    begin
      LogLine('INSTALL: User wants app visible - it is already running from registration step');
      // App is already running from Step 1, no need to launch again
    end
    else
    begin
      LogLine('INSTALL: User does NOT want app visible - killing the registration instance');
      // User didn't check "Launch now", so kill the hidden instance we started for registration
      Exec('taskkill.exe', '/F /IM HebrewFixer1998.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;
end;

