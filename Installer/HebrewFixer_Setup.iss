; HebrewFixer Installer Script for Inno Setup 6

; Private build toggle: enable/disable Settings GUI + UI automation stage.
; Set to 1 to include UI automation, 0 to do registry-only behavior.
#ifndef HF_ENABLE_UI_AUTOMATION
  ; 0 = do NOT launch Settings / UI Automation (avoid explorer.exe + ms-settings instability)
  ; 1 = enable full Settings UI automation during install
  #define HF_ENABLE_UI_AUTOMATION 0
#endif

; RTL Hebrew typing support for Affinity Designer
; https://github.com/Cencyte/HebrewFixer

[Setup]
AppName=HebrewFixer
AppVersion=1.0.8
AppVerName=HebrewFixer 1.0.8
AppPublisher=Cencyte
AppPublisherURL=https://github.com/Cencyte/HebrewFixer
AppSupportURL=https://github.com/Cencyte/HebrewFixer/issues
AppUpdatesURL=https://github.com/Cencyte/HebrewFixer/releases
; Install to %LOCALAPPDATA%\HebrewFixer (user-level, no admin required)
DefaultDirName={localappdata}\HebrewFixer
DefaultGroupName=HebrewFixer
OutputDir=..\bin
OutputBaseFilename=HebrewFixer_Setup
SetupIconFile=..\Icon\ICOs\hebrew_fixer_affinity_off.ico
; Programs & Features icon (appwiz.cpl) is taken from this path.
; NOTE: Our installed EXE is renamed to HebrewFixer1998.exe in [Files].
UninstallDisplayIcon={app}\HebrewFixer1998.exe
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
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startmenu"; Description: "Create a Start Menu entry"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "Start HebrewFixer automatically when Windows starts"; GroupDescription: "Startup Options:"
Name: "trayvisible"; Description: "Always show HebrewFixer icon in the system tray (recommended)"; GroupDescription: "System Tray:"
Name: "launchapp"; Description: "Launch HebrewFixer now"; GroupDescription: "After Installation:"; Flags: unchecked

[Files]
; Main executable (from bin folder)
Source: "..\bin\HebrewFixer.exe"; DestDir: "{app}"; DestName: "HebrewFixer1998.exe"; Flags: ignoreversion

; Tray icon promotion script (does registry sanitize and optionally Settings UI automation)
Source: "..\\Tests\\Win11\\PromoteTrayIconInvisible.ps1"; DestDir: "{app}\\InstallerTools"; Flags: ignoreversion overwritereadonly uninsremovereadonly

; Registry-only cleanup script (NO UI automation) for uninstall
Source: "CleanupNotifyIconSettings.ps1"; DestDir: "{app}\\InstallerTools"; Flags: ignoreversion overwritereadonly uninsremovereadonly

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
; Remove persisted settings/logs on uninstall
Type: filesandordirs; Name: "{userappdata}\\HebrewFixer"

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

var
  RunId: String;

// Win32 API functions (TRect is already defined in Inno Setup)
function SetWindowPos(hWnd: HWND; hWndInsertAfter: HWND; X: Integer; Y: Integer;
  cx: Integer; cy: Integer; uFlags: UINT): BOOL;
  external 'SetWindowPos@user32.dll stdcall';

function GetWindowRect(hWnd: HWND; var lpRect: TRect): BOOL;
  external 'GetWindowRect@user32.dll stdcall';

function GetCurrentProcessId(): Integer;
  external 'GetCurrentProcessId@kernel32.dll stdcall';

procedure InitializeWizard;
begin
  // Make the installer window always-on-top
  SetWindowPos(WizardForm.Handle, HWND_TOPMOST, 0, 0, 0, 0, 
    SWP_NOSIZE or SWP_NOMOVE or SWP_SHOWWINDOW);
end;

function InstallLogPath(): String;
begin
  // Unique per run to avoid file locking and preserve all runs.
  Result := ExpandConstant('{userappdata}\\HebrewFixer\\InstallLogs\\installer_debug_' + RunId + '.log');
end;

function InstallPSLogPath(): String;
begin
  // Unique per run to avoid file locking and preserve all runs.
  Result := ExpandConstant('{userappdata}\\HebrewFixer\\InstallLogs\\installer_debug_ps_' + RunId + '.log');
end;

function NotificationLogPath(): String;
begin
  // Unique per run to avoid file locking and preserve all runs.
  Result := ExpandConstant('{userappdata}\\HebrewFixer\\InstallLogs\\notification_area_icons_installer_' + RunId + '.log');
end;

function CleanupBootstrapLogPath(): String;
begin
  // Captures PowerShell stdout/stderr even if the script fails before it can create its own log.
  Result := ExpandConstant('{userappdata}\\HebrewFixer\\InstallLogs\\cleanup_bootstrap_' + RunId + '.log');
end;

function CmdWrapRedirect(ExePath, ExeArgs, OutPath: String): String;
begin
  // cmd /c ""<ExePath>" <ExeArgs> 1>>"<OutPath>" 2>>&1"
  Result := '/c ""' + ExePath + '" ' + ExeArgs + ' 1>>"' + OutPath + '" 2>>&1"';
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

// NOTE: We intentionally do NOT wrap PowerShell via cmd.exe redirection.
// Instead, we pass -LogPath into the script so it writes installer-friendly logs itself.

function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  // Create per-run unique ID based on local timestamp + tick suffix.
  // Use WinAPI GetTickCount via kernel32.dll for uniqueness.
  RunId := IntToStr(GetCurrentProcessId());

  LogLine('InitializeSetup: start | BUILD=DEBUG_LOG_V2');
  LogLine('InitializeSetup: RunId=' + RunId);
  LogLine('InitializeSetup: InstallLogPath=' + InstallLogPath());
  LogLine('InitializeSetup: InstallPSLogPath=' + InstallPSLogPath());
  LogLine('InitializeSetup: NotificationLogPath=' + NotificationLogPath());

  // Kill any running HebrewFixer processes before installation
  Exec('taskkill.exe', '/F /IM HebrewFixer1998.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  LogLine('InitializeSetup: taskkill result=' + IntToStr(ResultCode));
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
  ExecOk: Boolean;
  PSExe: String;
  PSScript: String;
  Args: String;
  Marker: Cardinal;
begin
  LogLine('CurUninstallStepChanged: step=' + IntToStr(Ord(CurUninstallStep)));
  if CurUninstallStep = usUninstall then
  begin
    // Initialize per-run RunId for the uninstaller too (InitializeSetup doesn't run here)
    if RunId = '' then
      RunId := IntToStr(GetCurrentProcessId());

    LogLine('UNINSTALL: entered');
    LogLine('UNINSTALL: RunId=' + RunId);
    LogLine('UNINSTALL: InstallPSLogPath=' + InstallPSLogPath());
    LogLine('UNINSTALL: NotificationLogPath=' + NotificationLogPath());

    // Ensure app is not running; otherwise uninstaller may fail to remove files/dirs.
    Exec('taskkill.exe', '/F /IM HebrewFixer1998.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    LogLine('UNINSTALL: taskkill HebrewFixer1998.exe result=' + IntToStr(ResultCode));

    // On uninstall, do REGISTRY-ONLY cleanup. Do NOT launch Settings UI automation.
    PSExe := ExpandConstant('{sys}\\WindowsPowerShell\\v1.0\\powershell.exe');
    PSScript := ExpandConstant('{app}\\InstallerTools\\CleanupNotifyIconSettings.ps1');
    Args :=
      '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + PSScript + '" ' +
      '-AppName "HebrewFixer1998.exe" ' +
      '-Mode Sanitize -DesiredPromoted 0 ' +
      '-LogPath "' + InstallPSLogPath() + '"';
    LogLine('UNINSTALL: running registry-only tray cleanup (sanitize)');
    LogLine('UNINSTALL: PSExe=' + PSExe);
    LogLine('UNINSTALL: Args=' + Args);
    ExecOk := Exec(PSExe, Args, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    LogLine('UNINSTALL: Exec ok=' + IntToStr(Ord(ExecOk)) + ' result=' + IntToStr(ResultCode));
    AppendPSLogToMain('UNINSTALL');

    // Best-effort reset marker (key itself is removed by uninsdeletekey).
    RegWriteDWordValue(HKEY_CURRENT_USER, 'Software\\HebrewFixer', 'TrayVisibleApplied', 0);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  ExecOk: Boolean;
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

    // Step 0: Registry-only cleanup BEFORE launching the app (reinstall hardening).
    // This prevents the tray icon from flashing during the brief registration launch.
    PSExe := ExpandConstant('{sys}\\WindowsPowerShell\\v1.0\\powershell.exe');
    PSScript := ExpandConstant('{app}\\InstallerTools\\CleanupNotifyIconSettings.ps1');
    Args :=
      '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + PSScript + '" ' +
      '-AppName "HebrewFixer1998.exe" ' +
      '-Mode Sanitize -DesiredPromoted 0 ' +
      '-FailIfCannotLog ' +
      '-RunId ' + RunId;
    LogLine('INSTALL: pre-cleanup (registry-only sanitize)');
    LogLine('INSTALL: PSExe=' + PSExe);
    LogLine('INSTALL: Args=' + Args);
    LogLine('INSTALL: CleanupBootstrapLogPath=' + CleanupBootstrapLogPath());

    // Run via cmd.exe with redirection so we ALWAYS capture errors, even if script logging fails.
    ExecOk := Exec(ExpandConstant('{sys}\\cmd.exe'), CmdWrapRedirect(PSExe, Args, CleanupBootstrapLogPath()), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    LogLine('INSTALL: pre-cleanup Exec ok=' + IntToStr(Ord(ExecOk)) + ' result=' + IntToStr(ResultCode));
    AppendPSLogToMain('INSTALL-PRECLEAN');

    // Step 1: Launch HebrewFixer hidden briefly to register the tray entry.
    LogLine('INSTALL: launching app hidden for tray registration');
    ExecOk := Exec(ExePath, '/NoTooltip', '', SW_HIDE, ewNoWait, ResultCode);
    LogLine('INSTALL: registration launch ok=' + IntToStr(Ord(ExecOk)) + ' result=' + IntToStr(ResultCode));
    Sleep(800);

    // IMPORTANT: Close the registration instance BEFORE any promotion-state changes.
    Exec('taskkill.exe', '/F /IM HebrewFixer1998.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    LogLine('INSTALL: taskkill HebrewFixer1998.exe (pre-UI) result=' + IntToStr(ResultCode));

    // Step 2: Run tray promotion script.
    // When HF_ENABLE_UI_AUTOMATION=0, we still run PromoteTrayIconInvisible.ps1 but with -SkipUIAutomation.
    if GetWindowRect(WizardForm.Handle, WinRect) then
    begin
      WinX := WinRect.Left;
      WinY := WinRect.Top;
      WinWidth := WinRect.Right - WinRect.Left;
      WinHeight := WinRect.Bottom - WinRect.Top;
    end
    else
    begin
      // Best-effort fallback (script needs these params even when SkipUIAutomation is set)
      WinX := 0;
      WinY := 0;
      WinWidth := 900;
      WinHeight := 600;
      LogLine('INSTALL: WARN - GetWindowRect failed, using fallback installer bounds');
    end;

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
      '-AppName "HebrewFixer1998.exe" -CleanupRegistry ' +
      '-LogPath "' + NotificationLogPath() + '"';

#if HF_ENABLE_UI_AUTOMATION
    LogLine('INSTALL: HF_ENABLE_UI_AUTOMATION=1 (full UI automation enabled)');
#else
    Args := Args + ' -SkipUIAutomation';
    LogLine('INSTALL: HF_ENABLE_UI_AUTOMATION=0 (SkipUIAutomation enabled)');
#endif

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

    ExecOk := Exec(PSExe, Args, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    LogLine('INSTALL: Exec ok=' + IntToStr(Ord(ExecOk)) + ' result=' + IntToStr(ResultCode));
    AppendPSLogToMain('INSTALL');

    // Step 3: Launch the app only if requested.
    if WizardIsTaskSelected('launchapp') then
    begin
      LogLine('INSTALL: User wants app visible - launching now');
      ExecOk := Exec(ExePath, '/NoTooltip', '', SW_SHOW, ewNoWait, ResultCode);
      LogLine('INSTALL: app launch ok=' + IntToStr(Ord(ExecOk)) + ' result=' + IntToStr(ResultCode));
    end
    else
    begin
      LogLine('INSTALL: User does NOT want app visible - not launching');
    end;
  end;
end;

