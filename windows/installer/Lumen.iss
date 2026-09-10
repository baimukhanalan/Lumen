; Inno Setup script for Lumen (Windows).
; Compiled in CI with:
;   ISCC.exe /DPublishDir=<publish output> /DMyAppVersion=<version> Lumen.iss
; Falls back to sensible defaults when the /D values are not passed.

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef PublishDir
  #define PublishDir "..\..\dist\windows"
#endif

#define MyAppName "Lumen"
#define MyAppPublisher "Alan Baimukhan"
#define MyAppExeName "Lumen.exe"
#define MyAppURL "https://github.com/baimukhanalan/Lumen"

[Setup]
AppId={{B7E2B4E0-3F1A-4C2E-9E6D-4A0F1E2C7A10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\Lumen
DefaultGroupName=Lumen
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=Lumen-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "startupicon"; Description: "Start Lumen automatically at login"; GroupDescription: "Startup:"

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\Lumen"; Filename: "{app}\{#MyAppExeName}"
Name: "{userstartup}\Lumen"; Filename: "{app}\{#MyAppExeName}"; Tasks: startupicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Lumen"; Flags: nowait postinstall skipifsilent
