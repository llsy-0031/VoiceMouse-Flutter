# SECURITY — 安全说明

## 权限请求（最小权限）

| 平台 | 请求权限 | 用途 |
|---|---|---|
| Windows | 辅助功能（模拟输入） | WH_MOUSE_LL / WH_KEYBOARD_LL 钩子与快捷键注入 |
| macOS | 辅助功能（Accessibility） | CGEventTap 捕获与事件注入 |

首次启动会引导授权；权限被撤销时 UI 提示且不崩溃，不静默降级。

## 数据处理

- 纯本地：无网络通信、无遥测、无账户体系、无云同步。
- 数据目录：Windows `%APPDATA%\VoiceMouseMVP\`；macOS `~/Library/Application Support/VoiceMouseMVP/`。
- 存储内容：设置（快捷键、触发模式、外观）、使用统计。不含用户输入文本。
- 日志：仅记录事件与错误（含快捷键 keycode），不含输入内容。
- 导出诊断包：日志 + 系统信息 + 脱敏配置（快捷键值脱敏），由用户主动触发。

## 密钥与凭据

- 仓库不含任何 Secret（无 API Key / Token / 私钥 / 证书）。
- CI 不访问任何 GitHub Secret / Environments。

## 供应链

- 依赖：Flutter SDK + path_provider、tray_manager、win32、ffi（均 MIT/BSD 系），
  无原生二进制依赖；Flutter 版本锁定 3.47.0。
- 变更监控：见 .github/dependabot.yml。

## 漏洞报告

- 通过 GitHub Issue 提交（含复现步骤与影响说明），或直接 PR 修复。
- 修复流程：开 fix 分支 → 修复 + 测试 → PR → CI 通过 → 合入 main → 随下一个 Patch Release 发布。