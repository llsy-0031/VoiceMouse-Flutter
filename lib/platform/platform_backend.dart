/// 平台后端抽象接口。
///
/// 每个平台（Windows / macOS）实现本接口：
/// - 鼠标 Hook / Event Tap（监听并决定是否吞掉事件）
/// - 键盘快捷键注入
/// - 鼠标点击补发
/// - Raw Input 鼠标设备枚举（诊断用）
/// - SafetyGate 场景判断
/// - 开机启动
/// - 快捷键录制
library;

import '../core/safety.dart';

/// 鼠标事件回调：返回 True 表示事件应被吞掉。
typedef MouseEventCallback = bool Function(String button, bool down);

class InjectResult {
  const InjectResult(this.ok, this.message);
  final bool ok;
  final String message;
}

class DeviceInfo {
  const DeviceInfo(this.name, this.buttons);
  final String name;
  final int buttons;
}

class VoiceInputOption {
  const VoiceInputOption(this.name, this.shortcut, this.note);
  final String name;
  final String? shortcut;
  final String note;
}

/// 快捷键录制器接口。
abstract class ShortcutRecorder {
  /// 当前组合键字符串。
  String get combo;

  /// 开始监听按键变化（onChange 每次按键变化时触发，onCancel 表示中途放弃）。
  void start({void Function(String combo)? onChange, void Function()? onCancel});

  /// 结束录制，返回组合键（取消/无键返回 null）。
  String? finish();

  /// 取消录制。
  void cancel();
}

abstract class PlatformBackend {
  String get name;

  bool get supportsCapture => true;

  /// 启动鼠标监听。callback 返回 True 表示事件应被吞掉。
  void startHook(MouseEventCallback callback);

  /// 停止鼠标监听并取消所有挂起状态。必须幂等。
  void stopHook();

  /// 注入一次完整快捷键（按下+抬起）。只允许在 SAFE 状态调用。
  InjectResult sendShortcut(String shortcut);

  /// 补发一次原鼠标点击（短按保留原功能）。只允许在 SAFE 状态调用。
  InjectResult replayMouseClick(String button);

  /// 枚举鼠标设备（诊断用）。
  List<DeviceInfo> enumerateMice();

  /// 返回当前场景安全状态。调用方负责频率控制。
  SafetyState checkSafety();

  /// 是否缺少系统辅助功能/无障碍权限。
  bool needsPermission() => false;

  /// 前台窗口是否属于本程序自身（用于「测试快捷键」的场景）。
  bool isForegroundSelf() => false;

  /// 识别本机输入法的语音输入快捷键。
  List<VoiceInputOption> detectVoiceInputOptions() => [];

  /// 引导用户打开系统设置授予权限（macOS）。Windows 为空操作。
  void requestPermission() {}

  /// 设置开机启动。返回 (是否成功, 提示文本)。
  ({bool ok, String message}) applyAutostart(bool enabled);

  /// 启动快捷键录制（拦截模式）。
  ShortcutRecorder startShortcutRecording({String mode = 'multi'});

  /// 紧急停用（Windows Ctrl+Alt+F12）。跨平台可选实现。
  void setEmergencyDisabled(bool disabled);

  /// 紧急停用状态变化回调（后端触发，如按了紧急热键）。
  void Function(bool emergency)? onEmergency;

  bool isEmergencyDisabled() => false;

  /// 系统双击速度（秒），用于双击判定窗口。
  double getDoubleClickTime() => 0.5;

  /// 进入 GUI 主循环前的准备工作（后台线程等）。
  void prepare();

  /// 程序退出清理。
  void cleanup();
}