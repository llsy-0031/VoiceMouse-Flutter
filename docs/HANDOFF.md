# HANDOFF — 项目交接

> 给下一位 AI/开发者的状态说明。每次大版本/阶段结束更新。
> 面向用户的版本记录与已知限制见 [CHANGELOG.md](../CHANGELOG.md)，本文不重复。

## 当前版本
- pubspec `1.0.1+2`；界面 kVersion `v1.0.1`（`lib/core/version.dart`，与 pubspec 手动同步）。

## 当前可运行平台
- Windows x64（本地构建验证）；macOS arm64（GitHub Actions CI 构建）。

## 已完成
- 双平台后端：win32_backend / macos_backend（FFI + isolate + 共享内存事件管线）。
- 触发状态机（tap_double / replace）、安全路由、紧急热键（Ctrl+Alt+F12 双平台）。
- macOS 全面审计修复：FN 存储串、suppress 放行、录制修饰键过滤、紧急热键、竖屏窗口。
- 工程规范：双平台 CI + 标准产物名 + SHA256、日志系统、设置原子写 + schema_version、
  诊断导出、重置设置。

## 当前架构
```
UI (run_page/settings_page/app_shell)
  → AppController（设置/路由/状态机编排）
  → PlatformBackend 接口
      ├─ win32_backend（低层钩子+注入，前台窗口检测，RegisterHotKey）
      └─ macos_backend（CGEventTap 后台 isolate + 共享内存轮询）
  → core/（press_state 状态机、shortcut 解析、settings 存储、router、log、diagnostics）
```

## 关键依赖
- Flutter 3.47.0（Stable，锁定）；dart 3.13。path_provider、tray_manager、win32、ffi。
  全部 MIT/BSD 系，无原生二进制依赖。

## Native 能力（FFI，无插件）
- Windows：WH_MOUSE_LL / WH_KEYBOARD_LL 钩子、SendInput/注入、RegisterHotKey、前台窗口枚举。
- macOS：CGEventTap、CGEvent 注入、CFRunLoop 后台 isolate、LaunchAgents。

## CI 状态
- Workflow：`.github/workflows/release-macos.yml`（Build & Release (macOS + Windows)），
  4 job：determine-version → build-macos / build-windows → release（SHA256 + Release 发布）。
- 流程与检查清单见 `docs/RELEASE.md`。
- 注意：YAML 多行 run 块必须整体缩进；PowerShell Set-Content 会写 BOM 破坏 YAML。

## 签名/公证状态
- macOS ad-hoc（Gatekeeper 拦截，需右键打开）；Windows 未签名（SmartScreen 提示）。决策：不付费签名。

## 数据 schema
- settings.json / stats.json（JSON，`schema_version: 1`，原子写 + .bak 备份）。
- 目录：Windows %APPDATA%/VoiceMouseMVP；macOS ~/Library/Application Support/VoiceMouseMVP。
- 迁移入口：`lib/core/settings.dart` 的 `migrateSettings`（幂等）。

## 下一步
- 用户实机验收 v1.0.1（重点：触发链路、双击保留、紧急热键、竖屏窗口、诊断导出）。
- 视反馈修复；长期可做：macOS 全屏检测、设备枚举。

## 禁止破坏的约束
- `_poll`/tap 的共享内存槽位布局（_sSeq.._sEmerg）改动须同步 isolate 与主线程两侧。
- macOS suppress 放行必须按"每次真实 post 前置 1"的语义，不要在键盘注入路径设置。
- 默认快捷键 macOS 存 `'FN'`（显示层单独转 'FN 连按两下'），不可混存。
- Flutter 版本锁 3.47.0，升级需单独任务并验证插件兼容。