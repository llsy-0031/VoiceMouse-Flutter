; VoiceMouse 语音鼠标 安装脚本（Inno Setup 6）
; 产物：VoiceMouse-<ver>-windows-x64-setup.exe
; 特性：
;   . 用户级安装（无需管理员，可选为所有用户安装）
;   . 创建开始菜单/桌面快捷方式
;   . 注册到系统「应用」列表，支持卸载
;   . 安装完成可选立即运行
;   . 安装界面后续可替换为 VoiceMouseInstaller_Design 中的 Flutter 风格 HTML 向导

#define MyAppName "VoiceMouse 语音鼠标"
#define MyAppVersion "1.0.3"
#define MyAppPublisher "VoiceMouse"
#define MyAppExeName "voicemouse.exe"
#define MyAppSourceDir "..\VoiceMouse"
#define MyAppOutputName "VoiceMouse-" + MyAppVersion + "-windows-x64-setup"

[Setup]
; 卸载识别码（固定，勿改）
AppId={{7F3B9C2E-4A81-4D9F-B5C6-8E2A1D0F3B44}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppVerName={#MyAppName} {#MyAppVersion}
DefaultDirName={autopf}\VoiceMouse
DefaultGroupName=VoiceMouse
DisableProgramGroupPage=yes
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\\build\\windows\\x64\\runner
OutputBaseFilename={#MyAppOutputName}
SetupIconFile=app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoProductName={#MyAppName}

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: checkedonce
Name: "launchafterinstall"; Description: "安装完成后立即运行 VoiceMouse"; GroupDescription: "附加任务："; Flags: checkedonce

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\VoiceMouse"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 VoiceMouse"; Filename: "{uninstallexe}"
Name: "{autodesktop}\VoiceMouse"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "立即运行 VoiceMouse"; Flags: nowait postinstall skipifsilent; Tasks: launchafterinstall

[Messages]
SetupWindowTitle=安装 - %1
WelcomeLabel1=欢迎使用 [name] 安装向导
WelcomeLabel2=本向导将把 [name/ver] 安装到您的电脑上。%n%n建议在安装前关闭其他应用程序，以免需要重启。

