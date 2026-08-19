# VoiceMouse 语音鼠标（Flutter 版）

把鼠标按键（中键 / 侧键）变成"语音输入"触发键的 Windows / macOS 桌面效率工具。单击指定鼠标键 → 触发系统语音输入（Windows 听写 / macOS 听写）。

- 一句话定位：把鼠标按键变成语音输入快捷键。
- 目标用户：中文办公用户，在浏览器 / 微信 / Word 等场景快速语音输入。
- 本地 / 联网：纯本地，无网络通信，不采集数据；免费开源（MIT）。
- 首版不做：自动更新、Windows ARM64 / macOS Intel、签名公证、移动端。

> 原版（Python）仓库：https://github.com/llsy-0031/VoiceMouse
> 本仓库为 Flutter 重写版。

## 功能

- 鼠标键触发语音输入（中键 / 侧键 x1 / x2）：单击触发 · 双击保留原功能 · 长按兜底
- 组合快捷键注入（CTRL / SHIFT / ALT / WIN），FN 特例支持 macOS 听写（连按两下 Fn）
- 快捷键录制校准（multi / single 模式，ESC 取消）
- 紧急停用热键 Ctrl+Alt+F12（双平台）
- 开机自启、系统托盘、深浅色主题、使用统计
- 设置页：导出诊断包（日志 + 系统信息 + 脱敏配置）、重置设置

## 平台

| 平台 | 后端 | 构建 |
|------|------|------|
| Windows x64 | `lib/platform/win32_backend.dart`（WH_MOUSE_LL 钩子 + SendInput） | 本地 / CI |
| macOS arm64（Apple Silicon） | `lib/platform/macos_backend.dart`（CGEventTap） | GitHub Actions（ad-hoc 签名） |

> 版本决策：不发布 Windows ARM64 / macOS Intel；不做签名公证（详见 [docs/PLATFORM_SUPPORT.md](docs/PLATFORM_SUPPORT.md)）。

macOS 注意：首次使用需在「系统设置 → 隐私与安全性 → 辅助功能」勾选本应用；ad-hoc 签名包首次打开需右键 → 打开。

## 快速开始

```bash
flutter pub get
flutter analyze
flutter test
flutter build windows --release    # Windows
flutter build macos --release      # macOS（需 Mac；或走 GitHub Actions）
```

macOS 云构建：推 tag `v*` 或手动触发 Actions 工作流 `.github/workflows/release-macos.yml`，自动产出双平台 zip + SHA256SUMS.txt 并发布 Release。

## 下载

最新版在 [GitHub Releases](https://github.com/llsy-0031/VoiceMouse-Flutter/releases)（含 SHA256SUMS.txt）。

## 文档

| 文档 | 内容 |
|------|------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 架构、关键设计、禁止破坏的约束 |
| [docs/PLATFORM_SUPPORT.md](docs/PLATFORM_SUPPORT.md) | 支持矩阵、依赖平台能力、版本决策 |
| [docs/TEST_PLAN.md](docs/TEST_PLAN.md) | 测试计划与用例 |
| [docs/RELEASE.md](docs/RELEASE.md) | 发布流程、产物清单、发布前检查 |
| [docs/SECURITY.md](docs/SECURITY.md) | 权限、数据处理、漏洞报告 |
| [docs/HANDOFF.md](docs/HANDOFF.md) | 项目交接（版本/依赖/CI 状态/下一步） |
| [CHANGELOG.md](CHANGELOG.md) | 版本变更与 Known Issues（面向用户） |

## 目录结构

```
lib/
  app/app_controller.dart    # 设置/路由/状态机编排
  core/                      # 平台无关：press_state、shortcut、settings、router、safety、log、diagnostics、version
  platform/                  # win32_backend / macos_backend / PlatformBackend 接口
  ui/                        # run_page、settings_page、app_shell、theme、widgets
test/                        # 单元测试（15 用例）
.github/workflows/           # CI：双平台构建 + Release
docs/                        # 开发者文档
windows/ macos/              # 平台壳工程（Flutter 生成 + 少量定制）
```

## 技术要点

- 架构：`PlatformBackend` 接口抽象平台差异，UI / 路由 / 设置完全共享
- macOS 事件模型：后台 isolate + CFRunLoopRun 承载 CGEventTap，"吞掉 + 补发"与 Windows 钩子语义一致
- 单实例：Windows 命名互斥（OpenMutexW 探测）；macOS 文件锁（FileLock.exclusive）
- 数据目录：Windows `%APPDATA%\VoiceMouseMVP\`；macOS `~/Library/Application Support/VoiceMouseMVP/`（设置 / 统计 / 日志）

## 许可证

[MIT](LICENSE)