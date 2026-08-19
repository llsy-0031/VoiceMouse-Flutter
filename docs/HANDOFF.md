# HANDOFF — 项目交接

> 给下一位 AI/开发者的状态说明。每次大版本/阶段结束更新。

## 当前版本
- pubspec `1.0.1+2`；界面 kVersion `v1.0.1`（app_controller.dart:21）。

## 当前可运行平台
- Windows x64（本地构建验证）；macOS arm64（GitHub Actions CI 构建）。

## 当前发布产物
- GitHub Release v1.0.0 / v1.0.1：`VoiceMouse-*-windows-x64.zip`、`VoiceMouse-*-macos-arm64.zip`、`SHA256SUMS.txt`。

## 已完成
- 双平台后端：win32_backend / macos_backend（FFI + isolate + 共享内存事件管线）。
- 触发状态机（tap_double / replace）、安全路由、紧急热键（Ctrl+Alt+F12 双平台）。
- macOS 全面审计修复：FN 存储串、suppress 放行、录制修饰键过滤、紧急热键、竖屏窗口。
- CI：macOS + Windows 双 job 构建 → 合并 release job（SHA256 + Release 自动发布）。
- 日志系统、设置原子写 + schema_version、诊断导出、重置设置。

## 未完成 / 已知 Bug
- macOS checkSafety 恒安全（无全屏/游戏窗口检测）——P2 已知限制。
- macOS enumerateMice 返回空——P2 已知限制。
- 录制快捷键期间"测试快捷键"注入被拦截——P2 已知限制。
- 补发原点击时若光标已移动会被拉回——P2 已知限制。

## 当前架构
```
UI (run_page/settings_page/app_shell)
  → AppController（设置/路由/状态机编排）
  → PlatformBackend 接口
      ├─ win32_backend（低层钩子+注入，前台窗口检测，RegisterHotKey）
      └─ macos_backend（CGEventTap 后台 isolate + 共享内存轮询）
  → core/（press_state 状态机、shortcut 解析、settings 存储、router、log）
```

## 关键依赖
- Flutter 3.47.0（Stable，锁定）；dart 3.13。
- path_provider、tray_manager（Windows 托盘）、win32、ffi。全部 MIT/BSD 系，无原生二进制依赖。

## Native 能力（FFI，无插件）
- Windows：WH_MOUSE_LL / WH_KEYBOARD_LL 钩子、SendInput/注入、RegisterHotKey、前台窗口枚举。
- macOS：CGEventTap、CGEvent 注入、CFRunLoop 后台 isolate、LaunchAgents。

## 构建方式
- 本地 Windows：`flutter.bat build windows --release`（analyze 用 dart.exe 直跑，flutter analyze 中文路径会崩）。
- macOS：推送代码后 CI 自动构建（workflow_dispatch 输入版本号或打 v* tag）。

## CI 状态
- Workflow：`.github/workflows/release-macos.yml`（Build & Release (macOS + Windows)），4 个 job：determine-version → build-macos / build-windows → release。
- 注意：YAML 多行 run 块必须整体缩进；PowerShell Set-Content 会写 BOM 破坏 YAML。

## 签名/公证状态
- macOS ad-hoc（Gatekeeper 拦截，需右键打开）；Windows 未签名（SmartScreen 提示）。决策：不付费签名。

## 数据 schema
- settings.json / stats.json（JSON，无 schema 版本历史；`schema_version: 1` 已加入，原子写）。
- 目录：Windows %APPDATA%/VoiceMouseMVP；macOS ~/Library/Application Support/VoiceMouseMVP。

## 下一步
- 用户实机验收 v1.0.1（重点：触发链路、双击保留、紧急热键、竖屏窗口）。
- 视反馈修复；长期可做：macOS 全屏检测、设备枚举。

## 禁止破坏的约束
- `_poll`/tap 的共享内存槽位布局（_sSeq.._sEmerg）改动须同步 isolate 与主线程两侧。
- macOS suppress 放行必须按"每次真实 post 前置 1"的语义，不要在键盘注入路径设置。
- 默认快捷键 macOS 存 `'FN'`（显示层单独转 'FN 连按两下'），不可混存。
- Flutter 版本锁 3.47.0，升级需单独任务并验证插件兼容。