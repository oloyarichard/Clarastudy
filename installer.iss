[Setup]
AppName=Clarastudy
AppVersion=1.0
DefaultDirName={autopf}\Clarastudy
DefaultGroupName=Clarastudy
OutputDir=Output
OutputBaseFilename=ClarastudyInstaller
Compression=lzma
SolidCompression=yes

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\Clarastudy"; Filename: "{app}\untitled.exe"
Name: "{autodesktop}\Clarastudy"; Filename: "{app}\untitled.exe"

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/quiet /norestart"; StatusMsg: "Installing dependencies..."; Flags: waituntilterminated
Filename: "{app}\untitled.exe"; Description: "Launch Clarastudy"; Flags: nowait postinstall skipifsilent
