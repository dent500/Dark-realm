[Setup]
AppId={{C6E2A341-DA1A-4C5A-9473-4CBA599542FB}}
AppName=Dark Realm
AppVersion=1.0.0
AppPublisher=Antigravity
DefaultDirName={autopf}\Dark Realm
DefaultGroupName=Dark Realm
AllowNoIcons=yes
OutputDir=.
OutputBaseFilename=Dark_Realm_Setup
SetupIconFile=..\assets\branding\icon.ico
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\Dark Realm.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\Dark Realm.pck"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\libgodotsteam.windows.template_release.x86_64.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\steam_api64.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\steam_appid.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\ui\game_logo.jpg"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\branding\icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Dark Realm"; Filename: "{app}\Dark Realm.exe"; IconFilename: "{app}\icon.ico"
Name: "{userdesktop}\Dark Realm"; Filename: "{app}\Dark Realm.exe"; IconFilename: "{app}\icon.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\Dark Realm.exe"; Description: "{cm:LaunchProgram,Dark Realm}"; Flags: nowait postinstall skipifsilent
