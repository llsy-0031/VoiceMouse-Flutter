# RELEASE — 发布产物、签名与分发说明

## 发布产物（Required Targets）

| 平台 | 产物 | 构建方式 | 签名 | 公证 |
|---|---|---|---|---|
| Windows x64 | `VoiceMouse-<ver>-windows-x64-setup.exe` | GitHub Actions windows-latest + Inno Setup | ❌ 无（SmartScreen 可能提示） | 不适用 |
| macOS arm64 | `VoiceMouse-<ver>-macos-arm64.dmg` 或 `.pkg` | GitHub Actions macos-latest + create-dmg/pkgbuild | ✅ ad-hoc 签名（Gatekeeper 拦截） | ❌ 未公证 |
| 校验文件 | `SHA256SUMS.txt` | CI release job 自动生成 | - | - |

旧版 `.zip` 压缩包发布方式已停用，统一使用安装器分发。

## 决策

- 不发布 Windows ARM64 / macOS Intel。
- 不做签名公证；不做自动更新。
- Windows 使用 Inno Setup 生成安装程序（`02_发布包/installer/VoiceMouse_Installer_Windows.iss`）。
- macOS 优先生成 `.dmg`（需要 `create-dmg`），回退为 `.pkg`。
（完整记录见 [docs/PLATFORM_SUPPORT.md](PLATFORM_SUPPORT.md)。）
（完整记录见 [docs/PLATFORM_SUPPORT.md](PLATFORM_SUPPORT.md)。）

## Release 流程（CI 自动）

1. `workflow_dispatch` 输入版本号（如 v1.0.1）或推送 `v*` tag。
2. build-macos（arm64）+ build-windows（x64）并行构建。
3. release job 汇总产物 → 生成 SHA256SUMS.txt → 创建/更新 GitHub Release。

## 发布前检查清单

- [ ] CHANGELOG.md 已更新
- [ ] pubspec version / kVersion 已对齐
- [ ] 关键 P0/P1 bug 已修复并测试
- [ ] flutter analyze / flutter test 通过
- [ ] Windows Release 构建成功（本机或 CI）
- [ ] macOS 构建成功（CI）
- [ ] PLATFORM_SUPPORT.md 与实际一致
- [ ] 无 Secret 泄漏（git log 复查）

## 更新与回滚

- 旧版本 Release 保留，用户可回退下载。
- 无自动更新，不存在更新推送中断问题。
