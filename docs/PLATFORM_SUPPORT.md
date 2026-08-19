# PLATFORM_SUPPORT — 支持矩阵与版本决策

> 决策记录（2026-08-20）：不发布 Windows ARM64 与 macOS Intel（x64）版本；
> 不做签名/公证（涉及付费证书与多系统安装流程）；不做自动更新（离线工具，GitHub Release 手动下载）。

## Required Targets

| Target | OS 版本 | CPU | Required | 构建环境 | 真机验收 |
|---|---|---|---|---|---|
| Windows | Win10/11 | x64 | ✅ Required | GitHub Actions windows-latest + 本地 | 本地已验 |
| macOS | macOS 12+ | arm64 (Apple Silicon) | ✅ Required | GitHub Actions macos-latest | 用户实机验收 |
| Windows | - | ARM64 | ❌ 不发布 | - | - |
| macOS | - | x64 (Intel) | ❌ 不发布 | - | - |

## 依赖平台能力

| 能力 | Windows 实现 | macOS 实现 |
|---|---|---|
| 全局鼠标监听 | WH_MOUSE_LL 钩子 | CGEventTap（辅助功能权限） |
| 触发系统听写 | WIN+H 或自定义快捷键 | Fn 连按两下 或自定义快捷键 |
| 紧急停用热键 | RegisterHotKey Ctrl+Alt+F12 | listenOnly 键盘 Tap Ctrl+Alt+F12 |
| 权限需求 | 辅助功能（UIAccess 模拟输入） | 辅助功能（Accessibility） |
| 开机自启 | 启动项注册表/目录 | LaunchAgents plist |

## 已知限制（详见 CHANGELOG Known Issues）

- macOS 无全屏/游戏窗口自动识别（checkSafety 恒安全），全屏请用 Ctrl+Alt+F12。
- macOS 设备列表为空（无设备枚举）。
- 录制快捷键期间"测试快捷键"会被拦截。
- 补发原点击时若光标已移动会被拉回。

## 动态规则核对（每次 Release 前检查）

- Flutter Stable 对 Windows/macOS 的官方支持范围（当前锁定 3.47.0）。
- GitHub Actions runner 架构（macos-latest 目前为 arm64）。
- macOS 最低系统版本与 Apple 分发规则变化。