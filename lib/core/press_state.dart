/// 鼠标触发状态机（平台无关，可单测）。
///
/// 触发方式：
/// - tap_double（默认）：单击触发语音、双击保留原功能。
///   双击窗口出厂统一为 500ms（与 Windows / macOS 系统默认双击节奏一致）。
///   - down1 -> up1（窗口内无第二次按下）-> 单击，触发语音
///   - down1 -> up1 -> down2（窗口内的第二次按下）-> up2 -> 双击，补发一次原单击
///   - down1 按住超过窗口 -> 长按兜底，直接触发语音
/// - replace：按下立即吞掉并执行一次快捷键（完全替换原功能）。
library;

import 'dart:async';

const String triggerSendShortcut = 'send_shortcut';
const String triggerReplayClick = 'replay_click';

/// 双击判定窗口出厂值（秒）。
///
/// 说明：
/// - 此常量仅作为状态机兜底默认值（当平台后端拿不到系统双击速度时使用）。
/// - 实际运行时：Windows 读取「系统→鼠标→双击速度」并夹逼到 250~350ms，
///   macOS 固定为 300ms。这个节奏和"日常双击打开任何软件"的频率完全一致。
/// - 旧版 500ms 太慢 → 单击后等待 500ms 才触发语音，用户会觉得"按了没反应/延迟大"。
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

  // ========================= 翻页闭环辅助状态（2026-08-20 新增） =========================
  // 背景：用户双击触发浏览器自动滚动（翻页工具）后，习惯"再单击一下"来结束
  // 自动滚动。如果按旧逻辑，这一次"关闭滚动的单击"会被当成普通单击，又触发
  // 语音快捷键——这就是"未形成闭环 + 误触语音"。
  //
  // 方案：当状态机判为双击、并准备补发 replayClick（开启滚动）之后，设置
  // _rollingClosePending=true 并启动 3 秒过期 timer。在该状态下的下一次单击，
  // 会被拦截为"补发另一次 replayClick（等于关闭滚动）"，不触发语音快捷键。
  // 消费完毕或 3 秒超时后自动置 false，后续单击照常走"开语音"路径。
  bool _rollingClosePending = false;
  Timer? _rollingTimer;

  void _setRollingClosePending() {
    _rollingClosePending = true;
    _rollingTimer?.cancel();
    _rollingTimer = Timer(const Duration(milliseconds: 3000), () {
      _rollingClosePending = false;
      _rollingTimer = null;
    });
  }

  void _consumeRollingClosePending() {
    _rollingClosePending = false;
    _rollingTimer?.cancel();
    _rollingTimer = null;
  }

  void configure(String mode, {double doubleClickWindow = 0.5}) {
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
        // 开翻页工具 → 进入"待关闭"状态：3 秒内下一次单击 = 关闭翻页，不触发语音
        _setRollingClosePending();
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
    _consumeRollingClosePending();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _onTimerFire() {
    _timer = null;
    if (_mode == 'tap_double') {
      if (_state == 'down1') {
        // 按住超过窗口 -> 长按兜底，触发语音（如果正好是待关闭滚动 → 改关闭翻页）
        _state = 'idle';
        if (_rollingClosePending) {
          _consumeRollingClosePending();
          _fire(triggerReplayClick);
          return;
        }
        _fire(triggerSendShortcut);
        return;
      } else if (_state == 'up1') {
        // 双击窗口内没有第二次按下 -> 确认单击
        _state = 'idle';
        if (_rollingClosePending) {
          // 关键点：这次单击不是语音，而是一次"关闭自动滚动的原单击"
          _consumeRollingClosePending();
          _fire(triggerReplayClick);
          return;
        }
        _fire(triggerSendShortcut);
        return;
      } else if (_state == 'down2') {
        // 第二击也按住超过窗口 -> 兜底触发语音
        _state = 'idle';
        // 注意：既然已经判双击了，就同时维持"待关闭滚动"语义（不再重复置位，避免重置timer）
        _fire(triggerSendShortcut);
        return;
      }
    }
    // replace 路径不会走到这里（没有 timer），加空语句防静态分析告警。
    if (_mode == 'replace') return;
  }

  void _fire(String kind) {
    // ⚠️ 2026-08-20 紧急修正：先恢复同步触发，避免Hook异步化引入未知问题；
    //    为避免 Hook 栈内同步 SendInput 超时卸载钩子，由上层 AppController._onPressAction
    //    单独把 sendShortcut/replayMouseClick 用 Timer.run 异步化（单一变量可控）。
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
