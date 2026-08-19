/// 鼠标触发状态机（平台无关，可单测）。
///
/// 触发方式：
/// - tap_double（默认）：单击触发语音、双击保留原功能。
///   双击窗口与系统双击速度一致（默认约 300ms）。
///   - down1 -> up1（窗口内无第二次按下）-> 单击，触发语音
///   - down1 -> up1 -> down2（窗口内的第二次按下）-> up2 -> 双击，补发一次原单击
///   - down1 按住超过窗口 -> 长按兜底，直接触发语音
/// - replace：按下立即吞掉并执行一次快捷键（完全替换原功能）。
library;

import 'dart:async';

const String triggerSendShortcut = 'send_shortcut';
const String triggerReplayClick = 'replay_click';

const double doubleClickWindowS = 0.3;

typedef PressAction = void Function(String kind);

class PressStateMachine {
  PressStateMachine(this._onAction);

  final PressAction _onAction;
  String _state = 'idle';
  String _mode = 'tap_double';
  double _window = doubleClickWindowS;
  bool _pressed = false;
  bool _longTriggered = false;
  Timer? _timer;

  void configure(String mode, {double doubleClickWindow = 0.3}) {
    _mode = (mode == 'tap_double' || mode == 'replace') ? mode : 'tap_double';
    if (doubleClickWindow > 0) _window = doubleClickWindow;
  }

  double get window => _window;

  /// 按下事件。返回 True 表示已拦截（应吞掉），False 表示放行。
  bool handleDown() {
    var fire = false;
    if (_mode == 'replace') {
      _pressed = true;
      _longTriggered = false;
      fire = true;
    } else {
      // tap_double
      if (_state == 'down2') {
        // 三连及更多：按双击处理后的剩余点击直接忽略
        return true;
      }
      if (_state == 'up1') {
        // 第二次按下 -> 双击判定
        _cancelTimer();
        _state = 'down2';
        _timer = Timer(Duration(milliseconds: (_window * 1000).round()), _onTimerFire);
        return true;
      }
      // 第一次按下
      _state = 'down1';
      _timer = Timer(Duration(milliseconds: (_window * 1000).round()), _onTimerFire);
    }
    if (fire) _fire(triggerSendShortcut);
    return true;
  }

  /// 松开事件。返回 True 表示已拦截，False 表示放行（不应发生）。
  bool handleUp() {
    var replay = false;
    if (_mode == 'tap_double') {
      if (_state == 'down1') {
        _cancelTimer();
        _state = 'up1';
        // 等一个双击窗口：没有再按下 -> 单击，触发语音
        _timer = Timer(Duration(milliseconds: (_window * 1000).round()), _onTimerFire);
        return true;
      }
      if (_state == 'down2') {
        _cancelTimer();
        _state = 'idle';
        // 双击 = 触发原来「单击」的功能（如网页中键单击自动滚动翻页）
        replay = true;
      }
    } else {
      // replace
      if (!_pressed) return false;
      _pressed = false;
      return true;
    }
    if (replay) _fire(triggerReplayClick);
    return true;
  }

  void cancel() {
    _cancelTimer();
    _pressed = false;
    _longTriggered = false;
    _state = 'idle';
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _onTimerFire() {
    var fire = false;
    _timer = null;
    if (_mode == 'tap_double') {
      if (_state == 'down1') {
        // 按住超过窗口 -> 长按兜底，直接触发语音
        _state = 'idle';
        fire = true;
      } else if (_state == 'up1') {
        // 双击窗口内没有第二次按下 -> 确认单击
        _state = 'idle';
        fire = true;
      } else if (_state == 'down2') {
        // 第二击也按住超过窗口 -> 触发语音
        _state = 'idle';
        fire = true;
      }
    }
    if (fire) _fire(triggerSendShortcut);
  }

  void _fire(String kind) {
    try {
      _onAction(kind);
    } catch (_) {
      // 触发回调异常不影响状态机
    }
  }

  bool get pressed => _pressed || _state == 'down1' || _state == 'down2';

  bool get longTriggered => _longTriggered;
}

/// 单调时钟（毫秒），用于保鲜判断。
final Stopwatch _monotonic = Stopwatch()..start();

/// 返回单调时钟秒数。
double monotonicSeconds() => _monotonic.elapsedMicroseconds / 1e6;

/// 简单的单调时钟保鲜包装，供 hook 侧二次校验使用。
class DebounceSafety {
  DebounceSafety(this._getter, {this.ttl = 0.35});

  final ({bool safe, double ts}) Function() _getter;
  final double ttl;

  bool isSafe() {
    try {
      final s = _getter();
      if (!s.safe) return false;
      return (monotonicSeconds() - s.ts) <= ttl;
    } catch (_) {
      return false;
    }
  }
}
