; Counterbase for Windows: the phone app built for Windows (mobile/).
; Build: flutter build windows --release, copy the Visual C++ runtime DLLs
; (msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll) into
; build\windows\x64\runner\Release, then run ISCC with APP_VERSION set.
; AppId matches the old desktop/ installer so this replaces it in place.

#define MyAppName "Counterbase"
#define MyAppPublisher "Arche Axon"
#define MyAppExeName "Counterbase.exe"

[Setup]
AppId={{0914856D-7D26-4BA9-8AF9-0BFE84C2AD21}
AppName={#MyAppName}
AppVersion={#GetEnv('APP_VERSION')}
AppVerName={#MyAppName} {#GetEnv('APP_VERSION')}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Counterbase
UsePreviousAppDir=yes
DefaultGroupName={#MyAppName}
UsePreviousGroup=no
DisableProgramGroupPage=yes
; Installs for the signed-in Windows user, so shop staff need no admin password.
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\build\windows\installer
OutputBaseFilename=Counterbase-Setup
SetupIconFile=runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
; The in-app updater reopens Counterbase itself (see [Run] and RELAUNCH).
RestartApplications=no
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "*.lib,*.exp,*.pdb"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: files; Name: "{autoprograms}\Axon POS.lnk"
Type: files; Name: "{autodesktop}\Axon POS.lnk"

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Open {#MyAppName}"; Flags: nowait postinstall skipifsilent
; The in-app updater runs this setup with /SILENT /RELAUNCH=1: open Counterbase again
; as soon as the new files are in, so the shop never has to find the icon.
Filename: "{app}\{#MyAppExeName}"; Flags: nowait; Check: ReopenAfterUpdate

[Code]
function ReopenAfterUpdate: Boolean;
begin
  Result := ExpandConstant('{param:RELAUNCH|0}') = '1';
end;

const
  SYNCHRONIZE = $00100000;
  WAIT_TIMEOUT = $00000102;

function OpenProcess(dwDesiredAccess: Cardinal; bInheritHandle: Integer;
  dwProcessId: Cardinal): Cardinal;
  external 'OpenProcess@kernel32.dll stdcall';
function WaitForSingleObject(hHandle: Cardinal; dwMilliseconds: Cardinal): Cardinal;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function CloseHandle(hObject: Cardinal): Integer;
  external 'CloseHandle@kernel32.dll stdcall';
function FindWindowW(lpClassName: String; lpWindowName: String): Cardinal;
  external 'FindWindowW@user32.dll stdcall';

{ The in-app updater starts this setup and then closes Counterbase. Wait for
  that copy to be completely gone before touching its files, so the swap never
  races the app closing (which is what made a silent update fail at "closing
  the application"). Older copies pass no /WAITPID: for those, wait until no
  Counterbase window is left, up to 20 seconds. }
procedure WaitForRunningApp;
var
  PidText: String;
  Pid: Integer;
  H: Cardinal;
  Tries: Integer;
begin
  PidText := ExpandConstant('{param:WAITPID|0}');
  Pid := StrToIntDef(PidText, 0);
  if Pid > 0 then
  begin
    H := OpenProcess(SYNCHRONIZE, 0, Pid);
    if H <> 0 then
    begin
      WaitForSingleObject(H, 30000);
      CloseHandle(H);
    end;
    Exit;
  end;
  Tries := 0;
  while (Tries < 40) and (FindWindowW('FLUTTER_RUNNER_WIN32_WINDOW', 'Counterbase') <> 0) do
  begin
    Sleep(500);
    Tries := Tries + 1;
  end;
end;

function InitializeSetup: Boolean;
begin
  if WizardSilent or (ExpandConstant('{param:WAITPID|0}') <> '0') then
    WaitForRunningApp;
  Result := True;
end;
