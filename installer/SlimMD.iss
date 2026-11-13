; ---------------------------------------------------------------------------
; SlimMD - Inno Setup installer script
; Per-user install, no admin rights required.
; Build:  ISCC.exe installer\SlimMD.iss   (or run build.ps1)
; ---------------------------------------------------------------------------

#define MyAppName "SlimMD"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "SlimMD Project"
#define MyAppExeName "SlimMD.exe"
#define MyProgId "SlimMD.md"
#define MyWebviewGuid "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"

[Setup]
AppId={{F6C24649-D899-4BFB-8239-178ED1B8CCFF}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=SlimMD-{#MyAppVersion}-Setup
SetupIconFile=..\src\SlimMD\SlimMD.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
VersionInfoVersion={#MyAppVersion}
VersionInfoProductTextVersion={#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
ChangesAssociations=yes
LZMANumBlockThreads=2

[Languages]
Name: "english";    MessagesFile: "compiler:Default.isl"
Name: "chinesetrad"; MessagesFile: "Languages\ChineseTrad.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:tasks_desktopicon}"; GroupDescription: "{cm:tasks_additional}"; Flags: unchecked
Name: "associate";   Description: "{cm:tasks_associate}";   GroupDescription: "{cm:tasks_additional}"; Flags: unchecked

[Files]
Source: "..\publish\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion createallsubdirs; Excludes: "*.pdb"

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}";   Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; .md file association (per-user; does not override an explicit user choice)
Root: HKCU; Subkey: "Software\Classes\{#MyProgId}";                    ValueType: string; ValueData: "Markdown Document"; Flags: uninsdeletekey; Tasks: associate
Root: HKCU; Subkey: "Software\Classes\{#MyProgId}\DefaultIcon";        ValueType: string; ValueData: "{app}\{#MyAppExeName},0"; Tasks: associate
Root: HKCU; Subkey: "Software\Classes\{#MyProgId}\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: associate
Root: HKCU; Subkey: "Software\Classes\.md";                            ValueType: string; ValueData: "{#MyProgId}"; Flags: uninsdeletevalue; Tasks: associate

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:run_launch}"; Flags: nowait postinstall skipifsilent

[CustomMessages]
english.tasks_additional=Additional tasks:
chinesetrad.tasks_additional=其他工作:
english.tasks_desktopicon=Create a &desktop shortcut
chinesetrad.tasks_desktopicon=建立桌面(&D)捷徑
english.tasks_associate=&Associate .md files with {#MyAppName}
chinesetrad.tasks_associate=將 .md 檔案與 {#MyAppName} 關聯(&A)
english.run_launch=Launch {#MyAppName}
chinesetrad.run_launch=啟動 {#MyAppName}
english.webview2_missing=Microsoft Edge WebView2 Runtime was not detected on this computer. {#MyAppName} requires it to render Markdown.%n%nOpen the WebView2 download page now? (You can still install without it, but {#MyAppName} will not run until the Runtime is installed.)
chinesetrad.webview2_missing=未偵測到此電腦已安裝 Microsoft Edge WebView2 Runtime。{#MyAppName} 需要它才能顯示 Markdown。%n%n要現在開啟 WebView2 下載頁面嗎？（您仍可繼續安裝，但安裝完成前請先安裝 Runtime，否則 {#MyAppName} 無法執行。）

[Code]
// The WebView2 Evergreen Runtime can be installed per-machine (HKLM) or
// per-user (HKCU); check all three registry views plus the install folder.
function WebView2Installed: Boolean;
var
  Pv: String;
  Dir: String;
begin
  Result := False;

  if RegQueryStringValue(HKLM32, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\' + '{#MyWebviewGuid}', 'pv', Pv)
     and (Pv <> '') and (Pv <> '0.0.0.0') then
    Result := True
  else if RegQueryStringValue(HKLM64, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\' + '{#MyWebviewGuid}', 'pv', Pv)
     and (Pv <> '') and (Pv <> '0.0.0.0') then
    Result := True
  else if RegQueryStringValue(HKCU, 'Software\Microsoft\EdgeUpdate\Clients\' + '{#MyWebviewGuid}', 'pv', Pv)
     and (Pv <> '') and (Pv <> '0.0.0.0') then
    Result := True
  else
  begin
    Dir := ExpandConstant('{pf32}\Microsoft\EdgeWebView\Application');
    Result := DirExists(Dir);
  end;
end;

function InitializeSetup: Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  if not WebView2Installed then
  begin
    if MsgBox(ExpandConstant('{cm:webview2_missing}'), mbConfirmation, MB_YESNO) = IDYES then
      ShellExec('open', 'https://go.microsoft.com/fwlink/p/?LinkId=2124703', '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
  end;
end;
