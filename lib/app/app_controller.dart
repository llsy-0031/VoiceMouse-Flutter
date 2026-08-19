/// 应用主控制器：把平台后端、核心逻辑与 UI 粘合起来。
///
/// 设计（对应原 Python 版 webview_app.py 的父进程逻辑）：
/// - 单 isolate 单线程模型：安全轮询用 Timer 驱动，后端钩子回调在主线程消息泵中
///   同步触发（见 win32_backend 的消息泵），因此所有状态变更天然线程安全。
/// - 所有对外动作（改设置、录制、检测）直接修改状态后 notifyListeners()，
///   UI 通过 AnimatedBuilder/ListenableBuilder 重建。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/press_state.dart';
import '../core/router.dart';
import '../core/safety.dart';
import '../core/settings.dart';
import '../core/shortcut.dart' as shortcut_mod;
import '../platform/platform_backend.dart';

const String kVersion = 'v0.3';

const Map<String, String> buttonLabels = {
  'middle': '鼠标中键',
  'x1': '上侧键（侧键 1）',
  'x2': '下侧键（侧键 2）',
};

const Map<String, String> buttonShort = {
  'middle': '中键',
  'x1': '上侧键',
  'x2': '下侧键',
};

const Map<String, String> srcLabels = {
  'system': 'Windows 系统语音',
  'macos': 'macOS 听写',
  'ime': '输入法语音输入',
};

const Map<String, String> modeHints = {
  'tap_double': '快速双击仍保留原功能',
  'replace': '按下即触发语音，原功能不再生效',
};

/// 钩子回调把动作转成 (kind, button) 元组发给控制器。
typedef PressEvent = ({String kind, String button});

class AppController extends ChangeNotifier {
  AppController(this.backend) {
    settings = loadSettings();
    if (settings['shortcut_source'] == 'custom') {
      settings['shortcut_source'] = 'system';
      settings['shortcut'] = 'WIN+H';
    }
    // macOS 默认使用系统听写（连按两下 Fn），Windows 默认 WIN+H
    if (backend.name == 'macos' &&
        settings['shortcut_source'] == 'system' &&
        settings['shortcut'] == 'WIN+H') {
      settings['shortcut_source'] = 'macos';
      settings['shortcut'] = 'FN';
    }
    _settingsCache = Map<String, dynamic>.from(settings);
    _running = settings['enabled'] == true;

    press = PressStateMachine(_onPressAction);
    try {
      final dcw = backend.getDoubleClickTime();
      press.configure(
        settings['mode'] ?? 'tap_double',
        doubleClickWindow: dcw,
      );
    } catch (_) {
      press.configure(settings['mode'] ?? 'tap_double');
    }

    router = MouseEventRouter(
      settingsGetter: () => Map<String, dynamic>.from(_settingsCache),
      safetyGetter: () => _safety,
      onAction: _onMouseAction,
      onCaptureEvent: _onCaptureEvent,
    );

    backend.onEmergency = _onEmergency;
  }

  final PlatformBackend backend;

  late Map<String, dynamic> settings;
  late Map<String, dynamic> _settingsCache;

  late PressStateMachine press;
  late MouseEventRouter router;

  bool _running = true;
  bool get running => _running;

  ({SafetyState state, double ts}) _safety = (state: SafetyState.unsafeUnknown, ts: 0);
  ({SafetyState state, double ts}) get safety => _safety;
  bool get safetyFresh {
    if (!_safety.state.safe) return false;
    return (monotonicSeconds() - _safety.ts) <= safetyTtlSeconds;
  }

  List<String> deviceNames = const [];
  List<VoiceInputOption> imeOptions = const [];

  String? toastText;
  int toastSeq = 0;

  bool detectActive = false;
  String? recordingCombo;
  String? lastAlertTitle;
  String? lastAlertMessage;

  ShortcutRecorder? _recorder;
  Timer? _detectTimer;
  Timer? _safetyTimer;
  bool _disposed = false;

  /// 前台是否是本程序自身（测试快捷键场景）。
  bool get foregroundSelf => backend.isForegroundSelf();

  // ============================ 生命周期 ============================

  void start() {
    refreshDevices();
    try {
      backend.startHook(router.handle);
    } catch (e) {
      _toast('鼠标监听启动失败：$e');
    }
    _startSafetyPoller();
    if (settings['autostart'] == true && _running) {
      _running = true;
    }
  }

  void shutdown() {
    _disposed = true;
    _safetyTimer?.cancel();
    _detectTimer?.cancel();
    press.cancel();
    _recorder?.cancel();
    _recorder = null;
    try {
      backend.stopHook();
    } catch (_) {}
    try {
      backend.cleanup();
    } catch (_) {}
  }

  // ============================ 状态快照（供 UI 读取） ============================

  String get displayShortcut {
    final src = settings['shortcut_source'] ?? 'system';
    if (src == 'system') return 'WIN+H';
    if (src == 'macos') return 'FN 连按两下';
    final s = settings['shortcut'];
    if (s is String && s.isNotEmpty) return s;
    return 'WIN+H';
  }

  String get safetyLine {
    if (_safety.state.safe) return '✦ 当前为文本输入场景，可直接使用';
    return '◌ ${stateHint(_safety.state)}';
  }

  Map<String, dynamic> statsSnapshot() {
    final minutes = estimatedMinutesSaved();
    final triggers = triggerCount();
    final words = triggers * 30;
    final days = daysSinceFirstUse();
    final speed = minutes > 0 ? (words / minutes).round() : 0;
    return {
      'minutes_saved': minutes,
      'trigger_count': triggers,
      'words_est': words,
      'days': days,
      'speed_wpm': speed,
    };
  }

  // ============================ 设置动作 ============================

  void _saveFromUi() {
    try {
      final src = _settingsCache['shortcut_source'] ?? 'system';
      if (src == 'system') {
        _settingsCache['shortcut'] = 'WIN+H';
      } else if (src == 'macos') {
        _settingsCache['shortcut'] = 'FN';
      } else if (src == 'ime') {
        final sel = _settingsCache['ime_selection'] ?? '';
        VoiceInputOption? opt;
        for (final o in imeOptions) {
          if (o.name == sel) opt = o;
        }
        if (opt != null && opt.shortcut != null && _settingsCache['shortcut_manual'] != true) {
          _settingsCache['shortcut'] = opt.shortcut;
        }
      }
      if (src != 'macos') {
        final sc = _settingsCache['shortcut'];
        if (sc is String && sc.isNotEmpty) {
          _settingsCache['shortcut'] = shortcut_mod.normalizeShortcut(sc);
        }
      }
      settings = Map<String, dynamic>.from(_settingsCache);
      press.configure(settings['mode'] ?? 'tap_double');
      saveSettings(settings);
    } catch (_) {}
  }

  void setButton(String v) {
    if (!buttonLabels.containsKey(v)) return;
    settings['button'] = v;
    _settingsCache['button'] = v;
    _saveFromUi();
    notifyListeners();
  }

  void setMode(String v) {
    if (!modeHints.containsKey(v)) return;
    settings['mode'] = v;
    _settingsCache['mode'] = v;
    _saveFromUi();
    notifyListeners();
  }

  void setSource(String v) {
    settings['shortcut_source'] = v;
    _settingsCache['shortcut_source'] = v;
    if (v == 'ime') detectIme();
    _saveFromUi();
    notifyListeners();
  }

  void setAppearance(String v) {
    settings['appearance'] = v;
    saveSettings(settings);
    _toast('外观已更新');
    notifyListeners();
  }

  void setAutostart(bool on) {
    settings['autostart'] = on;
    _settingsCache['autostart'] = on;
    final result = backend.applyAutostart(on);
    if (!result.ok) {
      _showAlert('开机启动设置失败', result.message);
    } else {
      _toast(result.message);
    }
    _saveFromUi();
    notifyListeners();
  }

  void setEnabled(bool on) {
    settings['enabled'] = on;
    _settingsCache['enabled'] = on;
    _running = on;
    _saveFromUi();
    _toast(on ? '语音鼠标已开启' : '已暂停，鼠标恢复原功能');
    notifyListeners();
  }

  void startRunning() {
    setEnabled(true);
    _toast('已开始运行，按一下触发键即可语音输入');
  }

  void pauseRunning() => setEnabled(false);

  // ============================ 输入法识别 ============================

  void detectIme() {
    try {
      imeOptions = backend.detectVoiceInputOptions();
    } catch (_) {
      imeOptions = const [];
    }
    _applySavedImeSelection();
    notifyListeners();
  }

  void _applySavedImeSelection() {
    if (imeOptions.isEmpty) return;
    final names = imeOptions.map((o) => o.name).toList();
    final saved = '${settings['ime_selection'] ?? ''}';
    if (names.contains(saved)) {
      _applyImeOption(imeOptions.firstWhere((o) => o.name == saved));
    } else {
      settings['ime_selection'] = names.first;
      _applyImeOption(imeOptions.first);
    }
  }

  void selectIme(String name) {
    VoiceInputOption? opt;
    for (final o in imeOptions) {
      if (o.name == name) opt = o;
    }
    if (opt == null) return;
    settings['shortcut_manual'] = false;
    settings['ime_selection'] = opt.name;
    _applyImeOption(opt);
    _saveFromUi();
    notifyListeners();
  }

  void _applyImeOption(VoiceInputOption opt) {
    settings['ime_selection'] = opt.name;
    if (settings['shortcut_manual'] == true) return;
    if (opt.shortcut != null && opt.shortcut!.isNotEmpty) {
      settings['shortcut'] = opt.shortcut;
    }
  }

  // ============================ 自动识别按键 ============================

  void openDetect() {
    router.beginCapture();
    detectActive = true;
    _detectTimer?.cancel();
    _detectTimer = Timer(const Duration(seconds: 20), () {
      if (detectActive) {
        cancelDetect();
        _toast('自动识别超时，已取消');
      }
    });
    notifyListeners();
  }

  void cancelDetect() {
    router.cancelCapture();
    detectActive = false;
    _detectTimer?.cancel();
    _detectTimer = null;
    notifyListeners();
  }

  void setButtonManual(String v) {
    cancelDetect();
    setButton(v);
    _toast('已识别并选上：${buttonLabels[v] ?? v}');
    notifyListeners();
  }

  // ============================ 录制校准 ============================

  void recalStart(String mode) {
    if (_recorder != null) return;
    try {
      _recorder = backend.startShortcutRecording(
        mode: mode,
      );
      _recorder!.start(
        onChange: (combo) {
          recordingCombo = combo;
          notifyListeners();
        },
        onCancel: () {
          _recorder = null;
          recordingCombo = null;
          notifyListeners();
        },
      );
      recordingCombo = '';
      notifyListeners();
    } catch (e) {
      _recorder = null;
      _toast('录制启动失败：$e');
    }
  }

  void recalConfirm() {
    final rec = _recorder;
    if (rec == null) {
      _toast('请先点「开始录制」');
      return;
    }
    final combo = rec.finish();
    _recorder = null;
    recordingCombo = null;
    if (combo != null && combo.isNotEmpty) {
      settings['shortcut'] = combo;
      settings['shortcut_source'] = 'ime';
      settings['shortcut_manual'] = true;
      _saveFromUi();
      _toast('已校准快捷键：$combo');
    } else {
      _toast('未录制到按键');
    }
    notifyListeners();
  }

  void recalCancel() {
    _recorder?.cancel();
    _recorder = null;
    recordingCombo = null;
    notifyListeners();
  }

  // ============================ 测试快捷键 ============================

  void testShortcut() {
    String shortcut;
    try {
      if ((settings['shortcut_source'] ?? 'system') == 'macos') {
        shortcut = 'FN';
      } else {
        shortcut = shortcut_mod.normalizeShortcut('${settings['shortcut'] ?? 'WIN+H'}');
        settings['shortcut'] = shortcut;
      }
      _saveFromUi();
    } catch (e) {
      _showAlert('快捷键无效', '$e');
      return;
    }
    _toast('正在测试……结果会显示在输入框里');
    Timer(const Duration(milliseconds: 400), () {
      if (!(safetyFresh || backend.isForegroundSelf())) {
        _toast('测试输入框没有获得焦点，请先点击测试输入框，再点「测试」。');
        return;
      }
      final r = backend.sendShortcut(shortcut);
      _toast(r.message);
      if (!r.ok) _showAlert('测试失败', r.message);
    });
  }

  // ============================ 紧急停用 / 权限 ============================

  void clearEmergency() {
    backend.setEmergencyDisabled(false);
    _toast('已重新打开语音鼠标，恢复正常工作');
    notifyListeners();
  }

  void openPermission() {
    try {
      backend.requestPermission();
      _toast('请在弹出的系统设置中授予「辅助功能」权限，然后返回');
    } catch (_) {}
  }

  void _onEmergency(bool emergency) {
    _toast(emergency ? '检测到紧急热键 Ctrl+Alt+F12：已紧急停用语音鼠标' : '已恢复正常');
    notifyListeners();
  }

  // ============================ 鼠标事件（钩子回调，主线程） ============================

  void _onMouseAction(String button, bool down) {
    if (down) {
      press.handleDown();
    } else {
      press.handleUp();
    }
  }

  void _onCaptureEvent(String button) {
    setButton(button);
    cancelDetect();
    _toast('已识别并选上：${buttonLabels[button] ?? button}');
  }

  void _onPressAction(String kind) {
    if (!safetyFresh) return;
    if (kind == triggerSendShortcut) {
      final shortcut = '${_settingsCache['shortcut'] ?? 'WIN+H'}';
      recordTrigger();
      final r = backend.sendShortcut(shortcut);
      if (!r.ok) _toast(r.message);
    } else if (kind == triggerReplayClick) {
      final button = '${_settingsCache['button'] ?? 'middle'}';
      final r = backend.replayMouseClick(button);
      if (!r.ok) _toast(r.message);
    }
  }

  // ============================ 设备枚举 ============================

  void refreshDevices() {
    try {
      final mice = backend.enumerateMice();
      if (mice.isEmpty) {
        deviceNames = const ['未从系统输入设备列表中发现鼠标（远程桌面环境属正常限制）'];
        return;
      }
      final names = <String>[];
      for (var i = 0; i < mice.length; i++) {
        final m = mice[i];
        var short = m.name;
        final vid = RegExp(r'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})').firstMatch(m.name);
        if (vid != null) {
          short = 'HID 鼠标（VID_${vid.group(1)!.toUpperCase()} / PID_${vid.group(2)!.toUpperCase()}）';
        }
        if (short.length > 70) short = '…${short.substring(short.length - 69)}';
        names.add('鼠标 ${i + 1} · 中键 / 上侧键 / 下侧键 · $short');
      }
      deviceNames = names;
    } catch (_) {
      deviceNames = const ['无法枚举鼠标设备'];
    }
    notifyListeners();
  }

  // ============================ 后台轮询 ============================

  void _startSafetyPoller() {
    _safetyTimer?.cancel();
    _safetyTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (_disposed) return;
      SafetyState state;
      try {
        state = backend.checkSafety();
      } catch (_) {
        state = SafetyState.unsafeUnknown;
      }
      _safety = (state: state, ts: monotonicSeconds());
      notifyListeners();
    });
  }

  // ============================ 通知辅助 ============================

  void _toast(String text) {
    toastText = text;
    toastSeq++;
    notifyListeners();
  }

  void _showAlert(String title, String message) {
    lastAlertTitle = title;
    lastAlertMessage = message;
    notifyListeners();
  }

  void clearAlert() {
    lastAlertTitle = null;
    lastAlertMessage = null;
    notifyListeners();
  }
}