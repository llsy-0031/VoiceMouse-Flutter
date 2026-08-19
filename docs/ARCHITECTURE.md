# ARCHITECTURE — 架构说明

> 面向开发者/维护者。快速理解：分三层，UI 与平台完全解耦。

## 分层

```
UI（run_page / settings_page / app_shell / theme / widgets）
  │  通知：AppController extends ChangeNotifier
  ▼
AppController（设置读写、路由、状态机编排、重置/诊断导出）
  │
  ▼
PlatformBackend（抽象接口）
  ├─ win32_backend：WH_MOUSE_LL 钩子 + SendInput 注入（FFI）
  └─ macos_backend：CGEventTap 后台 isolate + 共享内存轮询（FFI）
  │
  ▼
core/（平台无关逻辑）
  press_state 触发状态机 · shortcut 解析/录制 · settings 存储（原子写）
  router 安全路由 · safety 权限检测 · log 文件日志 · diagnostics 诊断导出 · version
```

## 关键设计

- **触发状态机**（`core/press_state.dart`）：单击触发 / 双击保留原功能 / 长按兜底，
  超时用后台计时器，注入走后端回调。
- **macOS 事件模型**：后台 isolate + CFRunLoopRun 承载 CGEventTap；
  "吞掉 + 补发"与 Windows 钩子语义一致；主线程通过共享内存轮询读取事件。
- **安全路由**（`core/router.dart`）：根据前台窗口判定目标按钮与安全场景，
  不安全时不触发并提示；macOS 恒安全（无窗口识别）。
- **设置存储**（`core/settings.dart`）：JSON，`schema_version: 1`，原子写（tmp + rename + .bak），
  损坏自动回退默认；`migrateSettings` 为幂等迁移入口。
- **单实例**：Windows 命名互斥（OpenMutexW）；macOS FileLock.exclusive。

## 关键数据流

```
鼠标按键
  → 后端钩子/Tap 捕获（吞掉）
  → 后台 isolate → 共享内存写入
  → 主线程 _poll 轮询
  → AppController 触发事件
  → 后端注入快捷键（SendInput / CGEvent）→ 系统听写
```

## 禁止破坏的约束

- 共享内存槽位布局（_sSeq.._sEmerg）改动须同步 isolate 与主线程两侧。
- macOS suppress 放行必须按"每次真实 post 前置 1"的语义，不要在键盘注入路径设置。
- 默认快捷键 macOS 存 `'FN'`（显示层单独转 'FN 连按两下'），不可混存。
- Flutter 锁 3.47.0，升级需单独任务并验证插件兼容。

## 与文档的关系

- 平台支持矩阵与决策：PLATFORM_SUPPORT.md
- 交接状态（当前版本/已完成/下一步）：HANDOFF.md