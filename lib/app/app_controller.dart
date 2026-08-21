/// 应用主控制器：把平台后端、核心逻辑与 UI 粘合起来。
///
/// 设计（对应原 Python 版 webview_app.py 的父进程逻辑）：
/// - 单 isolate 单线程模型：安全轮询用 Timer 驱动，后端钩子回调在主线程消息泵中
///   同步触发（见 win32_backend 的消息泵），因此所有状态变更天然线程安全。
/// - 所有对外动作（改设置、录制、检测）直接修改状态后 notifyListeners()，
///   UI 通过 AnimatedBuilder/ListenableBuilder 重建。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/diagnostics.dart' as diagnostics_mod;
import '../core/log.dart' as log_mod;
import '../core/press_state.dart';
import '../core/router.dart';
import '../core/safety.dart';
import '../core/settings.dart' as settings_mod;
import '../core/settings.dart';
import '../core/shortcut.dart' as shortcut_mod;
import '../platform/platform_backend.dart';

const Map<String, String> buttonLabels = {
  'middle': '鼠标中键',
  'x1': '上侧键（侧键 1）',
  'x2': '下侧键（侧键 2）',
  'x3': '侧键 3',
  'x4': '侧键 4',
  'x5': '侧键 5',
};

const Map<String, String> buttonShort = {
  'middle': '中键',
  'x1': '上侧键',
  'x2': '下侧键',
  'x3': '侧键3',
  'x4': '侧键4',
  'x5': '侧键5',
};

const Map<String, String> srcLabels = {
  'system': 'Windows 系统语音',
  'macos': 'macOS 听写',
  // 内部 key 仍为 'ime'（兼容历史配置），UI 统一叫「自定义」：
  // 既支持第三方输入法的语音快捷键，也支持任意软件自带的语音热键或单键（如 F7）。
  'ime': '自定义快捷键录制',
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
    // 防御性：跨平台配置迁移纠错（Windows 不允许 shortcut_source == macos，反之亦然）
    if (backend.name == 'windows' && settings['shortcut_source'] == 'macos') {
      settings['shortcut_source'] = 'system';
      settings['shortcut'] = 'WIN+H';
    }
    // macOS 默认使用系统听写（连按两下 Fn），Windows 默认 WIN+H
    if (backend.name == 'macos' &&
        (settings['shortcut_source'] == 'system' || settings['shortcut'] == 'WIN+H')) {
      settings['shortcut_source'] = 'macos';
      settings['shortcut'] = 'FN';
    }
    // 防御性：button 键值强校验。
    // 历史配置或"自动识别"异常时可能写入非法值（null/其他字符串），
    // 会导致 Router 中 settings['button'] != button → 永远放行 → 单击永远是原功能。
    // 支持 middle / x1 / x2 / x3 / x4 / x5（鼠标侧键识别扩展到 5+ 键）。
    final buttonRaw = settings['button'];
    if (buttonRaw is! String ||
        !const {'middle', 'x1', 'x2', 'x3', 'x4', 'x5'}.contains(buttonRaw)) {
      settings['button'] = 'middle';
    }
    _settingsCache = Map<String, dynamic>.from(settings);
    _running = settings['enabled'] == true;

    press = PressStateMachine(_onPressAction);
    try {
      final rawDcw = backend.getDoubleClickTime();
      // 二次夹逼：无论后端返回什么，最终应用的双击窗口一定在 200~550ms 之间
      // （1.1 倍余量，完全贴合用户"平常双击打开软件"的真实节奏，不会再漏判双击）。
      final dcw = (rawDcw * 1.1).clamp(0.20, 0.55);
      press.configure(
        settings['mode'] ?? 'tap_double',
        doubleClickWindow: dcw,
      );
    } catch (_) {
      press.configure(settings['mode'] ?? 'tap_double', doubleClickWindow: 0.3);
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

  /// 外部只读：当前是否正在挂键盘钩子监听按键。
  bool get isRecordingListening => _recorder != null;
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
      log_mod.logInfo('hook', '鼠标监听已启动 (${backend.name})');
    } catch (e) {
      log_mod.logError('hook', '鼠标监听启动失败: $e');
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
    // 防键盘锁：如果录制会话未正常结束（窗口关闭/程序退出/弹窗被意外销毁），
    // 强制 cancel recorder → 触发 isDone=true → _keyboardHookProc 自动卸载钩子。
    _recorder?.cancel();
    _recorder = null;
    try {
      backend.stopShortcutRecording();
    } catch (_) {}
    try {
      backend.stopHook();
    } catch (_) {}
    try {
      backend.cleanup();
    } catch (_) {}
  }

  // ============================ 状态快照（供 UI 读取） ============================

  String get displayShortcut {
    // 🔴 2026-08-20 重大修复：只要 settings['shortcut'] 有有效值（非空字符串），
    //    优先显示用户实际保存的快捷键 —— 不再因 shortcut_source=='system' 就硬编码 WIN+H，
    //    也不再因旧逻辑强覆盖导致"显示 WIN+H 实际发的也是 WIN+H，白录了自定义快捷键"。
    // 只有当 shortcut 为空 / 非法时，才按 source 兜底显示出厂默认值。
    final s = settings['shortcut'];
    if (s is String && s.isNotEmpty) {
      if (s == 'FN') return 'FN 连按两下'; // macos 专用存储值→显示转译
      return s; // 自定义 WIN+H / CTRL+SHIFT+A / F7 等，一律原样显示
    }
    // 兜底：shortcut 完全没设置过 → 按系统出厂默认
    final src = settings['shortcut_source'] ?? 'system';
    if (src == 'macos') return 'FN 连按两下';
    return 'WIN+H'; // Windows 出厂兜底：系统语音输入
  }

  /// 当前 tap_double 模式下的双击判定窗口（毫秒，取整）。
  ///
  /// - replace 模式下此值无意义，UI 层会隐藏。
  /// - 无论系统或后端返回何值，最终夹逼到 250~350ms（=日常双击打开软件的节奏）。
  int get doubleClickWindowMs {
    final s = press.window;
    // 与最新策略保持一致：200~550ms + 1.1倍余量，覆盖绝大多数用户真实双击节奏。
    final ms = (s * 1000).round();
    if (ms < 200) return 200;
    if (ms > 550) return 550;
    return ms;
  }

  /// 根据当前鼠标实际按键数，动态生成"可选触发按键"列表。
  ///
  /// 返回值格式：(内部key, UI短名, UI长名, 提示hint) —— UI 三处会用到：
  ///   ① 设置页 VMSegmented 选项
  ///   ② 自动识别弹窗手动选择按钮
  ///   ③ 设备详情弹窗中展示系统识别到了哪些按键
  ///
  /// 规则：
  /// - 系统总按键数 ≥ 3 → 一定显示 middle（中键）
  /// - ≥ 4 → 追加 x1
  /// - ≥ 5 → 追加 x2 （5键鼠标：左+右+中+X1+X2 → 就会显示中键+侧键1+侧键2，共3个）
  /// - ≥ 6 → 追加 x3
  /// - ≥ 7 → 追加 x4
  /// - ≥ 8 → 追加 x5 （最多再显示3个额外侧键，即使Win32原生API只能处理到X2，UI也先展示供用户选择）
  List<(String key, String short, String label, String hint)> get availableButtonOptions {
    final total = (() {
      try {
        final n = backend.getMouseButtons();
        if (n >= 3) return n;
      } catch (_) {}
      return 3;
    })();
    final result = <(String, String, String, String)>[];
    // 0: middle  —— 只要≥3键就有中键
    if (total >= 3) {
      result.add(('middle', '中键', '鼠标中键', '滚轮往下按'));
    }
    // 1: x1      —— ≥4键（总按键数扣掉左+右+中 = 1个侧键）
    if (total >= 4) {
      result.add(('x1', '侧键1', '上侧键（侧键1）', 'XButton1'));
    }
    // 2: x2      —— ≥5键（总扣掉3主 = 2个侧键）
    if (total >= 5) {
      result.add(('x2', '侧键2', '下侧键（侧键2）', 'XButton2'));
    }
    // 3: x3      —— ≥6键
    if (total >= 6) {
      result.add(('x3', '侧键3', '侧键3', '厂商驱动映射键'));
    }
    // 4: x4      —— ≥7键
    if (total >= 7) {
      result.add(('x4', '侧键4', '侧键4', '厂商驱动映射键'));
    }
    // 5: x5      —— ≥8键
    if (total >= 8) {
      result.add(('x5', '侧键5', '侧键5', '厂商驱动映射键'));
    }
    // 兜底：至少要有一个中键选项（防止 total 异常返回 <3）
    if (result.isEmpty) {
      result.add(('middle', '中键', '鼠标中键', '滚轮往下按'));
    }
    return result;
  }

  /// 当前所选按键的"影响范围说明"，用于设置页/运行页告知用户。
  ///
  /// 核心设计思路（用户要求补充）：
  /// 1. 选中键 = middle（中键）→ 中键按压被接管，中键翻页（双击）仍可用，滚轮滚动完全不涉及。
  /// 2. 选中键 = x1 / x2 / x3+（侧键）→ 侧键按压被接管，中键/滚轮/其他键完全不受影响。
  /// 3. replace 模式时：所选按键的"单击原功能"被完全替换（也不再区分双击）。
  /// 4. tap_double 模式的【翻页闭环】（2026-08-20 补充告知用户）：双击开启自动翻页后，
  ///    3 秒内再单击一次触发键 = 安全结束翻页（补发一次原单击），不会误触语音。
  String get buttonImpactNote {
    final btn = settings['button'] ?? 'middle';
    final mode = settings['mode'] ?? 'tap_double';
    final ms = doubleClickWindowMs;
    if (btn == 'middle') {
      if (mode == 'replace') {
        return '仅替换中键按压 · 滚轮滚动与左右键完全不受影响';
      }
      return '单击触发语音，双击保留中键翻页（${ms}ms 判定）；双击后3秒内再单击可安全结束翻页，不误触语音 · 滚轮滚动不涉及';
    }
    // x1 / x2 / x3 / x4 / x5 （侧键，包含厂商映射的额外侧键）
    final idx = int.tryParse(btn.replaceFirst('x', '')) ?? 1;
    if (mode == 'replace') {
      return '仅接管侧键$idx · 中键按压、滚轮滚动、左右键 都不受影响';
    }
    return '单击侧键$idx触发语音，双击侧键$idx回放其原功能（${ms}ms 判定）；双击后3秒内再单击可安全结束，不误触语音 · 中键与滚轮 完全不涉及';
  }

  String get safetyLine {
    if (_safety.state.safe) return '✦ 当前为文本输入场景，可直接使用';
    return '◌ ${stateHint(_safety.state)}';
  }

  Map<String, dynamic> statsSnapshot() {
    final minutes = estimatedMinutesSaved();
    final triggers = triggerCount();
    final days = daysSinceFirstUse();
    // 每分钟平均口述速度：按每次触发估算字数反推
    // 估算每次语音输入约30字，每次节省15秒 → 每分钟4次 × 30字 = 120字/分基准
    // 这里直接用 triggers（总次数）× 30字 / minutes（总分钟），但minutes为0时兜底
    final estimatedWords = triggers * 30;
    final speed = minutes > 0 ? (estimatedWords / minutes).round() : 0;
    return {
      'minutes_saved': minutes,
      'trigger_count': triggers,
      'days': days,
      'speed_wpm': speed,
    };
  }

  // ============================ 设置动作 ============================

  void _saveFromUi() {
    try {
      final src = _settingsCache['shortcut_source'] ?? 'system';
      if (src == 'system') {
        // 🔴 2026-08-20 重大修复：只有当 shortcut 为空/非法时，才兜底填 WIN+H；
        //    如果用户已经手动/录制了自定义快捷键（哪怕 source==system 也允许自定义），绝对不能覆盖！
        final sc = _settingsCache['shortcut'];
        if (sc is! String || sc.isEmpty) {
          _settingsCache['shortcut'] = 'WIN+H';
        }
      } else if (src == 'macos') {
        // ⚠️ 存储值必须是纯 'FN'，后端 sendShortcut() 只认这个精确串。
        // 显示层 displayShortcut 会单独转译为 'FN 连按两下'，两者严格解耦。
        _settingsCache['shortcut'] = 'FN';
      } else if (src == 'ime') {
        final sel = _settingsCache['ime_selection'] ?? '';
        VoiceInputOption? opt;
        for (final o in imeOptions) {
          if (o.name == sel) opt = o;
        }
        // 🔴 2026-08-20 修复：shortcut_manual==true 表示用户"明确手动/录制过了"，
        //    就算选了输入法推荐项，也绝对不能用输入法默认快捷键覆盖用户的自定义值！
        if (opt != null && opt.shortcut != null && _settingsCache['shortcut_manual'] != true) {
          final sc = _settingsCache['shortcut'];
          if (sc is! String || sc.isEmpty) {
            _settingsCache['shortcut'] = opt.shortcut;
          }
        }
      }
      if (src != 'macos') {
        final sc = _settingsCache['shortcut'];
        if (sc is String && sc.isNotEmpty) {
          _settingsCache['shortcut'] = shortcut_mod.normalizeShortcut(sc);
        }
      }
      settings = Map<String, dynamic>.from(_settingsCache);
      // ⚠️ 必须显式保留当前的双击窗口（不要用configure默认0.5，会覆盖我们校准过的250~350ms）
      final keepWindow = press.window;
      press.configure(settings['mode'] ?? 'tap_double', doubleClickWindow: keepWindow);
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
    // 🔴 2026-08-20 P0级产品修复：切"快捷键来源"时必须同步对应预设值，
    //    不能让"来源标签=Windows系统语音，但实际快捷键还是用户录的CTRL+SHIFT+V"——
    //    这种自相矛盾的状态会让用户彻底困惑："我切到系统了，怎么还在发别的？"
    //
    // 同时严格区分"用户手动/录制过的自定义值（shortcut_manual=true）"与"来源出厂预设值（manual=false）"：
    //  - shortcut_manual=true：用户明确录过或手输过 → 只有当他**明确点「录制校准」/「手动应用」时才能改，其他情况一律保留不覆盖。
    //  - shortcut_manual=false：来源出厂预设值 → 切来源时直接切到对应来源的预设。
    final nowManual = settings['shortcut_manual'] == true;
    final normalized = (v == 'system' || v == 'ime' || v == 'macos') ? v : (backend.name == 'macos' ? 'macos' : 'system');
    String defaultShortcut;
    bool resetManualToFalse;
    switch (normalized) {
      case 'macos':
        defaultShortcut = 'FN';
        resetManualToFalse = true; // macos 听写固定是连按两下 Fn，不允许手改
        break;
      case 'system':
        defaultShortcut = 'WIN+H';
        // 如果当前就是 system 来源，且用户在 system 下有手动自定义（nowManual==true 且 shortcut_source=='system'），保留用户值；
        // 其他情况（从 ime/macos 切过来）→ 切到 system 出厂预设。
        resetManualToFalse = !nowManual || '${settings['shortcut_source'] ?? ''}' != 'system';
        break;
      case 'ime':
      default:
        // 自定义来源：保留当前 shortcut（用户录的/上一次的），如果空的话后续 detectIme 会填输入法推荐；
        // manual=false 表示还没录过，等用户自己录或选推荐项。
        defaultShortcut = (() {
          final sc = settings['shortcut'];
          if (sc is String && sc.isNotEmpty && sc != 'FN') return sc;
          // macos 切过来的 FN 不能留，清空让 detectIme 填推荐
          return '';
        })();
        // 如果 defaultShortcut 有有效值且原本就是 manual=true → 保留用户手动标记；
        // 否则 resetManualToFalse → 标记为出厂预设/待用户录
        resetManualToFalse = !nowManual || defaultShortcut.isEmpty;
        break;
    }
    // 实际写入：先写 _settingsCache 再写 settings，保证 _saveFromUi 不会覆盖。
    _settingsCache['shortcut_source'] = normalized;
    settings['shortcut_source'] = normalized;
    if (resetManualToFalse || !nowManual) {
      // 需要用预设值的情况（出厂来源切换，且用户没有在该来源下明确自定义）
      if (defaultShortcut.isNotEmpty) {
        _settingsCache['shortcut'] = defaultShortcut;
        settings['shortcut'] = defaultShortcut;
      }
      _settingsCache['shortcut_manual'] = false;
      settings['shortcut_manual'] = false;
    } else {
      // nowManual==true，且当前切到的就是用户原来自定义过的来源（system切system保留用户自定义）→ 不动shortcut和manual
      // 同步一次 _settingsCache，保持双缓存一致
      final scCur = settings['shortcut'];
      if (scCur is String && scCur.isNotEmpty) {
        _settingsCache['shortcut'] = scCur;
      }
      _settingsCache['shortcut_manual'] = true;
    }
    if (normalized == 'ime') detectIme();
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

  /// 重置设置与统计为出厂状态（不删除诊断日志）。
  void resetSettings() {
    if (!settings_mod.resetAllData()) {
      _toast('重置失败：文件被占用或权限不足');
      return;
    }
    settings = loadSettings();
    _settingsCache = Map<String, dynamic>.from(settings);
    _running = settings['enabled'] == true;
    try {
      final rawDcw = backend.getDoubleClickTime();
      final dcw = (rawDcw * 1.1).clamp(0.20, 0.55);
      press.configure(settings['mode'] ?? 'tap_double', doubleClickWindow: dcw);
    } catch (_) {
      press.configure(settings['mode'] ?? 'tap_double', doubleClickWindow: 0.3);
    }
    saveSettings(settings);
    _toast('已重置设置与统计');
    notifyListeners();
  }

  /// 导出诊断包到桌面（日志 + 系统信息 + 脱敏配置）。
  void exportDiagnostics() {
    final desktop = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Platform.environment['TEMP'] ??
        '.';
    final dir =
        '$desktop${Platform.pathSeparator}VoiceMouse诊断_${DateTime.now().millisecondsSinceEpoch}';
    final r = diagnostics_mod.exportDiagnostics(dir);
    _toast(r.message);
    if (!r.ok) _showAlert('导出诊断包失败', r.message);
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
    // 注意：recalConfirm 可以在两种情况下被调用：
    //  A) 用户正在监听（_recorder != null）→ finish 拿结果
    //  B) 用户已经点过「录制完成」（_recorder == null，但 recordingCombo 还暂存着上次结果）→ 直接拿 recordingCombo 保存
    final combo = (() {
      final rec = _recorder;
      if (rec != null) {
        final c = rec.finish();
        _recorder = null;
        if (c != null && c.isNotEmpty) return c;
        return null;
      }
      // 情况B：暂存的结果
      final cached = recordingCombo;
      if (cached != null && cached.isNotEmpty) return cached;
      return null;
    })();
    recordingCombo = null;
    if (combo != null && combo.isNotEmpty) {
      // 🔴 2026-08-20 致命修复：必须【先同步 _settingsCache】！
      //    顺序绝对不能错！因为 _saveFromUi 的最后一行是：
      //        settings = Map<String, dynamic>.from(_settingsCache);
      //    如果先改 settings 再 _saveFromUi，刚写入 settings 的 combo 会被旧 _settingsCache 覆盖，等于白存！
      //    也因为 _onPressAction 触发时读的是 _settingsCache['shortcut']，不同步就永远发 WIN+H。
      _settingsCache['shortcut'] = combo;
      _settingsCache['shortcut_source'] = 'ime';
      _settingsCache['shortcut_manual'] = true;
      // settings 同步更新，保证 UI displayShortcut 立刻看到新值
      settings['shortcut'] = combo;
      settings['shortcut_source'] = 'ime';
      settings['shortcut_manual'] = true;
      _saveFromUi();
      _toast('已校准快捷键：$combo');
      // P1-①：录制完成后自动发送一次做「验货」，让用户立刻知道录的键能否正常注入
      Timer.run(() {
        final r = backend.sendShortcut(combo);
        if (r.ok) {
          _toast('验货成功：已自动发送 $combo');
        } else {
          _toast('验货失败：${r.message}');
          log_mod.logWarn('recal', '录制后自动验货失败: $combo -> ${r.message}');
        }
      });
    } else {
      _toast('未录制到按键');
    }
    notifyListeners();
  }

  /// 只停止录制监听（卸下键盘钩子），但暂存 recordingCombo 结果，给用户看"已录到XX"再确认。
  void recalStopListening() {
    final rec = _recorder;
    if (rec == null) return;
    // ✅ 用 finish()：停止监听+卸键盘钩子，同时返回已录的 combo；
    //    不走 cancel() → 不会触发 onCancel 回调清空 recordingCombo，避免闪空。
    final combo = rec.finish();
    _recorder = null;
    // 暂存结果（有则显示，没有则显示空串"等待按键"的逻辑已由UI处理）
    recordingCombo = (combo == null || combo.isEmpty) ? '' : combo;
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
        // 🔴 2026-08-20 修复：测试时 normalize 后的值同步写回 _settingsCache+settings
        _settingsCache['shortcut'] = shortcut;
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
    // ⚠️ 2026-08-20 【单一变量异步化】仅在这里做 Timer.run：
    // - PressStateMachine 恢复同步 _fire，避免 Hook 内部其他未知副作用
    // - 只把真正耗时的 SendInput/replayMouseClick 投递到 Hook 返回后的主线程微任务
    // → 既保证 Hook 永不超时（左键/右键/滚轮永远流畅），又不改动状态机同步语义
    Timer.run(() {
      if (kind == triggerSendShortcut) {
        final shortcut = '${_settingsCache['shortcut'] ?? 'WIN+H'}';
        recordTrigger();
        final r = backend.sendShortcut(shortcut);
        if (!r.ok) {
          log_mod.logWarn('trigger', '发送快捷键失败: $shortcut -> ${r.message}');
          _toast(r.message);
        } else {
          log_mod.logInfo('trigger', '已触发 $shortcut');
        }
      } else if (kind == triggerReplayClick) {
        final button = '${_settingsCache['button'] ?? 'middle'}';
        final r = backend.replayMouseClick(button);
        if (!r.ok) _toast(r.message);
      }
    });
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
        // 根据设备报告的按键总数，列出实际可用的按键
        final btns = <String>[];
        btns.add('中键'); // 至少有滚轮=中键
        if (m.buttons >= 4) btns.add('上侧键'); // 4键以上一般含侧键
        if (m.buttons >= 5) btns.add('下侧键'); // 5键含双侧键
        // 兜底：buttons<3 时不误导，只写中键（buttons=0表示未知）
        final btnText = m.buttons == 0
            ? '按键数未知，至少支持中键'
            : '支持：${btns.join(' / ')}';
        names.add('鼠标 ${i + 1} · $btnText · 共 ${m.buttons} 键 · $short');
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

  /// 对外弹窗提示（供 UI 直接调用）。
  void showAlert(String title, String message) => _showAlert(title, message);

  // ============================ 手动输入快捷键（录制校准替代） ============================

  /// 手动输入快捷键并保存（来源切到输入法，标记为用户手动设置）。
  void applyManualShortcut(String text) {
    final combo = shortcut_mod.normalizeShortcut(text);
    // 🔴 2026-08-20 致命修复：先同步 _settingsCache，再同步 settings，顺序不能错！
    _settingsCache['shortcut'] = combo;
    _settingsCache['shortcut_source'] = 'ime';
    _settingsCache['shortcut_manual'] = true;
    settings['shortcut'] = combo;
    settings['shortcut_source'] = 'ime';
    settings['shortcut_manual'] = true;
    _saveFromUi();
    _toast('已设置快捷键：$combo');
    notifyListeners();
  }

  void clearAlert() {
    lastAlertTitle = null;
    lastAlertMessage = null;
    notifyListeners();
  }
}