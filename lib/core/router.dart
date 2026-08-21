/// 鼠标事件路由：把平台原始鼠标事件翻译成映射决策（平台无关，可单测）。
///
/// 决策规则（对应 Game-Isolated 原则）：
/// 1. 未启用 -> 放行
/// 2. 安全状态不是 SAFE 或已过期 -> 放行
/// 3. 按键不是所选键 -> 放行
/// 4. 自动识别按键（capture）模式 -> 吞掉第一个匹配按键
/// 5. 交给 PressStateMachine 处理
library;

import 'safety.dart';
import 'press_state.dart' show monotonicSeconds;

typedef SettingsGetter = Map<String, dynamic> Function();
typedef SafetyGetter = ({SafetyState state, double ts}) Function();
typedef RouterAction = void Function(String button, bool down);
typedef CaptureEvent = void Function(String button);

/// Safety 判定的保鲜窗口：从 safety 检查到 hook 回调之间允许的最大间隔。
///
/// 原 350ms 过短，在 CPU 偶尔抖动或高 DPI 桌面稍慢时容易误过期放行。
/// 1.0s 既能保证安全数据不会过于陈旧，又能避免绝大多数误判放行（"单击变翻页"）。
const double safetyTtlSeconds = 1.0;

class MouseEventRouter {
  MouseEventRouter({
    required SettingsGetter settingsGetter,
    required SafetyGetter safetyGetter,
    required RouterAction onAction,
    CaptureEvent? onCaptureEvent,
  })  : _settings = settingsGetter,
        _safety = safetyGetter,
        _onAction = onAction, // ignore: prefer_initializing_formals
        _onCapture = onCaptureEvent;

  final SettingsGetter _settings;
  final SafetyGetter _safety;
  // ignore: prefer_initializing_formals
  final RouterAction _onAction;
  final CaptureEvent? _onCapture;
  bool _capture = false;
  String? _captureButton;

  void beginCapture() {
    _capture = true;
    _captureButton = null;
  }

  void cancelCapture() {
    _capture = false;
    _captureButton = null;
  }

  /// 返回 True = 吞掉该事件（不传递给系统），False = 放行。
  bool handle(String button, bool down) {
    if (button != 'middle' &&
        button != 'x1' &&
        button != 'x2' &&
        button != 'x3' &&
        button != 'x4' &&
        button != 'x5') {
      return false;
    }

    if (_capture) {
      if (down) {
        _capture = false;
        _captureButton = button;
        _onCapture?.call(button);
        return true;
      }
      return false;
    }

    if (_captureButton != null) {
      if (!down && _captureButton == button) {
        _captureButton = null;
        return true;
      }
      return false;
    }

    final settings = _settings();
    if (settings['enabled'] != true) return false;

    if (!_isFreshSafe()) return false;

    if (settings['button'] != button) return false;

    _onAction(button, down);
    return true;
  }

  bool _isFreshSafe() {
    try {
      final s = _safety();
      if (!s.state.safe) return false;
      return (monotonicSeconds() - s.ts) <= safetyTtlSeconds;
    } catch (_) {
      return false;
    }
  }
}