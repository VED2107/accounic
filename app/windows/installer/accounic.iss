; Accounic — Windows installer (context.md §33)
;
; Built with Inno Setup. It packages the whole of
; build\windows\x64\runner\Release, which is the .exe plus the Flutter engine
; DLL, the plugin DLLs and the data\ directory (ICU data, assets and the AOT
; snapshot). Shipping the .exe alone produces a binary that will not start —
; every file in that folder is required.
;
; Build it with:
;   iscc app\windows\installer\accounic.iss /DAppVersion=1.0.0
;
; It installs per-user, into Local AppData, and therefore needs no
; administrator rights: Accounic is a single-user application that writes only
; its own session data, so asking for elevation would buy nothing and cost the
; user a UAC prompt.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName        "Accounic"
#define AppPublisher   "Accounic"
#define AppExeName     "accounic.exe"
#define AppId          "{{8B0E4C2A-9F51-4E63-8B4E-4C7A6D1E9F20}"
#define SourceDir      "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/VED2107/accounic
AppSupportURL=https://github.com/VED2107/accounic/issues
AppUpdatesURL=https://github.com/VED2107/accounic/releases
VersionInfoVersion={#AppVersion}

; Per-user install: no elevation, no UAC prompt, no shared state.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#AppName}
DisableDirPage=yes
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}

OutputDir=..\..\build\installer
OutputBaseFilename=Accounic-Setup-{#AppVersion}-x64
SetupIconFile=..\runner\resources\app_icon.ico

; LZMA2/max keeps the 20MB Flutter engine down to something worth downloading.
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; Accounic ships x64 only, matching the Flutter Windows build.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Release directory, recursively. `recursesubdirs` is what carries
; data\flutter_assets and data\icudtl.dat, without which the app shows a blank
; window and exits.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Flutter writes its window-geometry and shared-preferences state beside the
; binary; leaving it behind would make a reinstall inherit the old window size.
Type: filesandordirs; Name: "{app}\data"
