#define MyAppName "Counterbase"
#define MyAppPublisher "Arche Axon Intelligence"
#define MyAppExeName "Counterbase.exe"

[Setup]
AppId={{0914856D-7D26-4BA9-8AF9-0BFE84C2AD21}
AppName={#MyAppName}
AppVersion={#GetEnv('APP_VERSION')}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Counterbase
UsePreviousAppDir=yes
DefaultGroupName={#MyAppName}
UsePreviousGroup=no
DisableProgramGroupPage=yes
OutputDir=..\build\windows\installer
OutputBaseFilename=CounterbaseDesktopSetup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: files; Name: "{autoprograms}\Axon POS.lnk"
Type: files; Name: "{autodesktop}\Axon POS.lnk"

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
