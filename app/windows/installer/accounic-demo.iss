; Accounic Demo — Windows installer (docs/demo.md)
;
; The same packaging as accounic.iss, for the DEMO build. It exists so a demo
; can be installed the way the product is installed, rather than unzipped into
; a folder the visitor has to keep track of.
;
; Build it with:
;   flutter build windows --release --dart-define=DEMO_MODE=on ...
;   iscc app\windows\installer\accounic-demo.iss /DAppVersion=1.0.0
;
; -----------------------------------------------------------------------------
; EVERY IDENTIFIER HERE DIFFERS FROM accounic.iss, AND THAT IS THE POINT.
;
; A demo and a real Accounic are two applications that happen to share a
; codebase, and somebody evaluating the product may reasonably want both on one
; machine. If they shared an AppId, installing either would silently upgrade or
; uninstall the other; if they shared a directory, the second install would
; overwrite the first's binaries; if they shared a Start Menu name, the user
; could not tell which one they were opening.
;
; So: its own AppId, its own folder, its own name, its own uninstall entry.
;
; The SESSION is kept apart in the application itself rather than here, because
; an installer cannot do it. Windows derives the app-data directory from the
; executable's CompanyName and ProductName, which are "Accounic" in both builds,
; so both write to the same SharedPreferences file whatever folder they were
; installed into. `main.dart` gives the demo its own storage key instead — see
; the comment there.
; -----------------------------------------------------------------------------

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName        "Accounic Demo"
#define AppPublisher   "Accounic"
#define AppExeName     "accounic.exe"
; A different GUID from accounic.iss. Inno Setup treats AppId as the identity of
; the installed product: reuse it and the demo becomes an "upgrade" that removes
; the real application.
#define AppId          "{{3F7C1D9E-2A48-4B77-9C15-6E2B8A4D3C71}"
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

; Per-user install: no elevation, no UAC prompt, no shared state — the same
; reasoning as the production installer.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Accounic Demo
DisableDirPage=yes
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}

OutputDir=..\..\build\installer
OutputBaseFilename=Accounic-Demo-Setup-{#AppVersion}-x64
SetupIconFile=..\runner\resources\app_icon.ico

Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Release directory, recursively — the exe alone will not start
; without the engine DLL, the plugin DLLs and data\.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\data"
