# VoiceMouse 语音鼠标（Flutter 版）

把鼠标按键（如中键 / 侧键）变成"语音输入"触发快捷键的 Windows / macOS 双平台工具。按配置的鼠标键时，向当前光标位置注入快捷键组合，完成中文输入法的语音输入调用。

> 原版（Python）仓库：https://github.com/llsy-0031/VoiceMouse
> 本仓库为 Flutter 重写版：Windows（Win32 钩子）+ macOS（CGEventTap，GitHub Actions 云构建）

## 功能

- 鼠标键触发语音输入（支持中键 / 侧键 x1 / x2，可双击）
- 双击判定、组合快捷键注入（CTRL / SHIFT / ALT / WIN，FN 特例支持 macOS 听写）
- 快捷键录制（multi / single 模式，ESC 取消）
- 安全门：高权限场景自动提示
- 开机自启、系统托盘、紧急暂停热键（Ctrl+Alt+F12）
- 设置持久化（`settings.json` / `stats.json`）

## 平台

| 平台 | 后端 | 说明 |
|------|------|------|
| Windows x64 | `lib/platform/win32_backend.dart`（WH_MOUSE_LL 钩子 + SendInput） | 本地构建 / CI 构建 |
| macOS arm64（Apple Silicon） | `lib/platform/macos_backend.dart`（CGEventTap） | GitHub Actions 构建（ad-hoc 签名） |

> 版本决策：不发布 Windows ARM64 / macOS Intel；不做签名公证（详见 `docs/PLATFORM_SUPPORT.md`）。

macOS 注意：
- 首次使用需在「系统设置 → 隐私与安全性 → 辅助功能」勾选本应用
- ad-hoc 签名包首次打开需右键 → 打开（或 `xattr -cr` 去除隔离属性）
- 全屏/游戏场景请用 Ctrl+Alt+F12 紧急停用（macOS 无自动全屏识别）

## 文档

- `docs/PROJECT_BRIEF.md` 项目定位 · `docs/PLATFORM_SUPPORT.md` 支持矩阵 · `docs/TEST_PLAN.md` 测试计划 · `docs/RELEASE.md` 发布流程 · `docs/HANDOFF.md` 项目交接
- `CHANGELOG.md` 版本变更与已知限制

## 构建

```bash
flutter pub get
flutter analyze
flutter test
flutter build windows --release    # Windows
flutter build macos --release      # macOS（需 Mac；或走 GitHub Actions）
```

macOS 云构建：推 tag `v*` 或手动触发 Actions 工作流 `.github/workflows/release-macos.yml`，产物为 ad-hoc 签名 zip。

## 技术要点

- 架构：`PlatformBackend` 接口抽象平台差异，UI / 路由 / 设置完全共享
- macOS 事件模型：后台 isolate + CFRunLoopRun 承载 CGEventTap，"吞掉 + 补发"与 Windows 钩子语义一致
- 单实例：Windows 命名互斥（OpenMutexW 探测）；macOS 文件锁（FileLock.exclusive）

## 数据位置

- Windows：`%APPDATA%\VoiceMouseMVP\`（设置 / 统计 / 日志）
- macOS：`~/Library/Application Support/VoiceMouseMVP/`（设置 / 统计 / 日志）

设置页可「导出诊断包」（日志 + 系统信息 + 脱敏配置）到桌面。