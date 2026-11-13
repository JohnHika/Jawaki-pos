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
