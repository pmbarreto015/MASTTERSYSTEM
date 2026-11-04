[Setup]
AppName=MastterSystem ERP
AppVersion=2.0.0
AppPublisher=FpqSystem
AppPublisherURL=https://www.masttersystem.com.br
DefaultDirName={pf}\MastterSystem
DefaultGroupName=MastterSystem
UninstallDisplayIcon={app}\masttersystem.exe
Compression=lzma2
SolidCompression=yes
OutputDir=installer_output
OutputBaseFilename=MastterSystem_Setup_v2.0.0
PrivilegesRequired=admin

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MastterSystem"; Filename: "{app}\masttersystem.exe"
Name: "{group}\Desinstalar"; Filename: "{uninstallexe}"
Name: "{commondesktop}\MastterSystem"; Filename: "{app}\masttersystem.exe"

[Run]
Filename: "{app}\masttersystem.exe"; Description: "Iniciar MastterSystem"; Flags: postinstall nowait skipifsilent