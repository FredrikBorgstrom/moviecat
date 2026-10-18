; Inno Setup script for the MovieCat Windows installer.
; Built in CI: iscc /DAppVersion=1.2.3 windows\installer\moviecat.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6E2B5C1A-3F47-4D8B-9A1E-7C0D4F2B8A61}
AppName=MovieCat
AppVersion={#AppVersion}
AppVerName=MovieCat {#AppVersion}
UninstallDisplayName=MovieCat
AppPublisher=AB Cx3
AppPublisherURL=https://moviecat.org
AppSupportURL=https://github.com/FredrikBorgstrom/moviecat/issues
AppUpdatesURL=https://moviecat.org
DefaultDirName={autopf}\MovieCat
DefaultGroupName=MovieCat
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\build\installer
OutputBaseFilename=MovieCat-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\moviecat.exe
LicenseFile=..\..\LICENSE
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\MovieCat"; Filename: "{app}\moviecat.exe"
Name: "{autodesktop}\MovieCat"; Filename: "{app}\moviecat.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\moviecat.exe"; Description: "{cm:LaunchProgram,MovieCat}"; Flags: nowait postinstall skipifsilent
