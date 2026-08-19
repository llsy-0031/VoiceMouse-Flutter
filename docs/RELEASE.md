# RELEASE — 发布产物、签名与分发说明

## 发布产物（Required Targets）

| 产物 | 构建方式 | 签名 | 公证 |
|---|---|---|---|
| `VoiceMouse-<ver>-windows-x64.zip` | GitHub Actions windows-latest（或本地） | ❌ 无（SmartScreen 可能提示） | 不适用 |
| `VoiceMouse-<ver>-macos-arm64.zip` | GitHub Actions macos-latest | ✅ ad-hoc 签名（Gatekeeper 拦截） | ❌ 未公证 |
| `SHA256SUMS.txt` | CI release job 自动生成 | - | - |

## 决策（2026-08-20 记录）

- ❌ 不做 Developer ID 签名 / Notarization（需付费开发者账号）。
- ❌ 不做 Windows 代码签名证书（需付费）。
- ❌ 不发布 Windows ARM64 / macOS Intel。
- ❌ 不做应用内自动更新（离线工具，用户从 GitHub Release 手动下载）。

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