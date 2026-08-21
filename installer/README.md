# VoiceMouse 安装器封装说明

本目录包含 Windows 与 macOS 双平台安装器封装脚本，替代原有的 `.zip` 压缩包发布方式。

## 目录结构

```
02_发布包/
├─ VoiceMouse/                          ← Windows 可执行文件目录（构建安装器的来源）
├─ installer/
│   ├─ app_icon.ico                     ← 安装程序图标
│   ├─ VoiceMouse_Installer_Windows.iss ← Windows Inno Setup 脚本
│   ├─ build-windows-installer.bat      ← Windows 一键构建批处理
│   ├─ build-macos-installer.sh         ← macOS DMG/pkg 构建脚本
│   └─ README.md                        ← 本文件
└─ VoiceMouse-1.0.3-windows-x64-setup.exe  ← 构建产物示例
```

## Windows 安装器

### 前置条件

- 安装 [Inno Setup 6](https://jrsoftware.org/isinfo.php)
- 确保 `iscc.exe` 在系统 PATH 中

### 构建步骤

```powershell
# 方式一：双击运行
build-windows-installer.bat

# 方式二：命令行
cd "02_发布包\installer"
iscc "VoiceMouse_Installer_Windows.iss"
```

产物位于 `02_发布包/VoiceMouse-1.0.3-windows-x64-setup.exe`。

### 安装器行为

- 默认安装到 `%ProgramFiles%\VoiceMouse`
- 创建开始菜单快捷方式
- 可选创建桌面快捷方式
- 安装完成可选立即运行
- 注册到系统「应用」列表，支持卸载

## macOS 安装器

### 前置条件

- macOS 系统
- 已安装 Xcode Command Line Tools
- 已安装 Flutter SDK
- 可选：`create-dmg`（`brew install create-dmg`）

### 构建步骤

```bash
cd "02_发布包/installer"
bash build-macos-installer.sh
```

产物位于 `build/VoiceMouse-1.0.3-macos-arm64.dmg`（如果安装了 create-dmg）或 `build/VoiceMouse-1.0.3-macos-arm64.pkg`。

### 安装说明

1. 打开 DMG，将 `VoiceMouse.app` 拖入「应用程序」
2. 首次运行：右键 → 打开（ad-hoc 签名，Gatekeeper 拦截属正常）
3. 系统设置 → 隐私与安全性 → 辅助功能 → 勾选 VoiceMouse

## 与 GitHub Release 的对应关系

| 平台 | 旧发布物 | 新发布物 |
|---|---|---|
| Windows | `VoiceMouse-<ver>-windows-x64.zip` | `VoiceMouse-<ver>-windows-x64-setup.exe` |
| macOS | `VoiceMouse-<ver>-macos-arm64.zip` | `VoiceMouse-<ver>-macos-arm64.dmg` 或 `.pkg` |

## 界面升级计划

当前使用 Inno Setup 默认向导界面。后续可将 `VoiceMouseInstaller_Design/` 中的 Flutter Material 3 风格 HTML 页面集成到安装器 UI 中（例如通过 HTML 自定义页面插件或重写为 Flutter 桌面安装器）。
