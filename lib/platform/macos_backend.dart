// ignore_for_file: non_constant_identifier_names, camel_case_types, library_private_types_in_public_api
/// macOS 平台后端（第一版）。
///
/// 架构（与 win32_backend 对齐的"吞掉 + 补发"模型）：
/// - 后台 isolate 线程创建 CGEventTap（鼠标）并进入 CFRunLoopRun()，
///   tap 回调运行在该 isolate 自己的 Dart 线程上，因此可以安全执行
///   Pointer.fromFunction 回调（关键设计点）。
/// - tap 回调把事件写入共享内存（主 isolate calloc 的 Pointer，地址可跨
///   isolate 传递），默认返回 NULL 吞掉该事件。
/// - 主 isolate 用 Timer(10ms) 轮询共享内存，把事件交给 routerCb；
///   若 router 决定"保留原功能"，则调用 CGEventPost 补发合成事件
///   （补发前写 suppress 槽位，回调看到后放行一次，防止自投递被再捕获）。
/// - 键盘录制走独立的后台 isolate（录制时临时启动，吞掉键盘事件）。
/// - 权限：监听全局鼠标需要"辅助功能"权限（AXIsProcessTrusted）。
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../core/safety.dart';
import '../core/shortcut.dart' as shortcut_mod;
import 'platform_backend.dart';

// ============================ 常量 ============================

// CGEventType
const int kCGEventNull = 0;
const int kCGEventLeftMouseDown = 1;
const int kCGEventLeftMouseUp = 2;
const int kCGEventRightMouseDown = 3;
const int kCGEventRightMouseUp = 4;
const int kCGEventKeyDown = 10;
const int kCGEventKeyUp = 11;
const int kCGEventFlagsChanged = 12;
const int kCGEventOtherMouseDown = 25;
const int kCGEventOtherMouseUp = 26;

// CGEventTapLocation / Placement / Options
const int kCGHIDEventTap = 0;
const int kCGHeadInsertEventTap = 0;
const int kCGEventTapOptionDefault = 0;
const int kCGEventTapOptionListenOnly = 1;

// CGEventField
const int kCGMouseEventButtonNumber = 12;
const int kCGKeyboardEventKeycode = 9;
const int kCGKeyboardEventEventFlags = 13;

// CGMouseButton
const int kCGMouseButtonLeft = 0;
const int kCGMouseButtonRight = 1;
const int kCGMouseButtonCenter = 2;

// CGEventFlags
const int kCGEventFlagMaskShift = 1 << 17;
const int kCGEventFlagMaskControl = 1 << 18;
const int kCGEventFlagMaskAlternate = 1 << 19;
const int kCGEventFlagMaskCommand = 1 << 20;

// CFStringEncoding
const int kCFStringEncodingUTF8 = 0x08000100;

// 鼠标共享内存槽位偏移（Int64 数组下标）
const int _sSeq = 0;
const int _sButton = 1;
const int _sDown = 2;
const int _sX = 3;
const int _sY = 4;
const int _sSuppress = 5;
const int _sEmerg = 6;

// 键盘共享内存槽位偏移
const int _kSeq = 0;
const int _kKeycode = 1;
const int _kMods = 2;
const int _kDown = 3;

// 按钮编码
const int _btnMiddle = 0;
const int _btnX1 = 1;
const int _btnX2 = 2;

// 平台库路径
const String _cfPath =
    '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation';
const String _cgPath =
    '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics';
const String _asPath =
    '/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices';

// ============================ FFI 类型与签名 ============================

/// CGPoint（C 结构体，FFI 按值传递）。
final class _CGPoint extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;
}

typedef _CGEventTapCallBack = Pointer<Void> Function(
    Pointer<Void> proxy, Uint32 type, Pointer<Void> event, Pointer<Void> userInfo);

typedef _CGEventTapCreateFn = Pointer<Void> Function(Uint32 tap, Uint32 place,
    Uint32 options, Uint64 mask, Pointer<NativeFunction<_CGEventTapCallBack>> cb,
    Pointer<Void> user);
typedef _CGEventTapCreateNative = Pointer<Void> Function(int tap, int place,
    int options, int mask, Pointer<NativeFunction<_CGEventTapCallBack>> cb,
    Pointer<Void> user);

typedef _CGEventTapEnableFn = Void Function(Pointer<Void> port, Int32 enable);
typedef _CGEventTapEnableNative = void Function(Pointer<Void> port, int enable);

typedef _CGEventGetIntegerValueFieldFn = Int64 Function(
    Pointer<Void> event, Int32 field);
typedef _CGEventGetIntegerValueFieldNative = int Function(
    Pointer<Void> event, int field);

typedef _CGEventGetLocationFn = _CGPoint Function(Pointer<Void> event);
typedef _CGEventGetLocationNative = _CGPoint Function(Pointer<Void> event);

typedef _CGEventCreateMouseEventFn = Pointer<Void> Function(Pointer<Void> source,
    Uint32 type, _CGPoint pt, Uint32 button);
typedef _CGEventCreateMouseEventNative = Pointer<Void> Function(
    Pointer<Void> source, int type, _CGPoint pt, int button);

typedef _CGEventSetIntegerValueFieldFn = Void Function(
    Pointer<Void> event, Int32 field, Int64 value);
typedef _CGEventSetIntegerValueFieldNative = void Function(
    Pointer<Void> event, int field, int value);

typedef _CGEventPostFn = Void Function(Uint32 tap, Pointer<Void> event);
typedef _CGEventPostNative = void Function(int tap, Pointer<Void> event);

typedef _CGEventCreateKeyboardEventFn = Pointer<Void> Function(
    Pointer<Void> source, Uint16 keycode, Int32 keyDown);
typedef _CGEventCreateKeyboardEventNative = Pointer<Void> Function(
    Pointer<Void> source, int keycode, int keyDown);

typedef _CGEventSetFlagsFn = Void Function(Pointer<Void> event, Uint64 flags);
typedef _CGEventSetFlagsNative = void Function(Pointer<Void> event, int flags);

typedef _CGEventSourceCreateFn = Pointer<Void> Function(Uint32 state);
typedef _CGEventSourceCreateNative = Pointer<Void> Function(int state);

typedef _CFRunLoopGetCurrentFn = Pointer<Void> Function();
typedef _CFRunLoopGetCurrentNative = Pointer<Void> Function();

typedef _CFRunLoopAddSourceFn =
    Void Function(Pointer<Void> rl, Pointer<Void> source, Pointer<Void> mode);
typedef _CFRunLoopAddSourceNative = void Function(
    Pointer<Void> rl, Pointer<Void> source, Pointer<Void> mode);

typedef _CFRunLoopRunFn = Void Function();
typedef _CFRunLoopRunNative = void Function();

typedef _CFMachPortCreateRunLoopSourceFn =
    Pointer<Void> Function(Pointer<Void> alloc, Pointer<Void> port, Int64 order);
typedef _CFMachPortCreateRunLoopSourceNative = Pointer<Void> Function(
    Pointer<Void> alloc, Pointer<Void> port, int order);

typedef _CFReleaseFn = Void Function(Pointer<Void> cf);
typedef _CFReleaseNative = void Function(Pointer<Void> cf);

typedef _CFStringCreateWithCStringFn = Pointer<Void> Function(
    Pointer<Void> alloc, Pointer<Uint8> str, Int32 encoding);
typedef _CFStringCreateWithCStringNative = Pointer<Void> Function(
    Pointer<Void> alloc, Pointer<Uint8> str, int encoding);

typedef _AXIsProcessTrustedFn = Uint8 Function();
typedef _AXIsProcessTrustedNative = int Function();

// ============================ 全局 FFI 函数（惰性加载） ============================

late _CGEventTapCreateNative _gTapCreate;
late _CGEventTapEnableNative _gTapEnable;
late _CGEventGetIntegerValueFieldNative _gGetIntegerValueField;
late _CGEventGetLocationNative _gGetLocation;
late _CGEventCreateMouseEventNative _gCreateMouseEvent;
late _CGEventSetIntegerValueFieldNative _gSetIntegerValueField;
late _CGEventPostNative _gPost;
late _CGEventCreateKeyboardEventNative _gCreateKeyboardEvent;
late _CGEventSetFlagsNative _gSetFlags;
late _CGEventSourceCreateNative _gEventSourceCreate;
late _CFRunLoopGetCurrentNative _gRunLoopGetCurrent;
late _CFRunLoopAddSourceNative _gRunLoopAddSource;
late _CFRunLoopRunNative _gRunLoopRun;
late _CFMachPortCreateRunLoopSourceNative _gMachPortSource;
late _CFReleaseNative _gCFRelease;
late _CFStringCreateWithCStringNative _gCFStringCreate;
late _AXIsProcessTrustedNative _gAXIsProcessTrusted;

bool _ffiLoaded = false;

void _loadPlatformFunctions() {
  if (_ffiLoaded) return;
  _ffiLoaded = true;
  final cf = DynamicLibrary.open(_cfPath);
  final cg = DynamicLibrary.open(_cgPath);
  final as = DynamicLibrary.open(_asPath);
  _gTapCreate = cg.lookupFunction<_CGEventTapCreateFn, _CGEventTapCreateNative>(
      'CGEventTapCreate');
  _gTapEnable =
      cg.lookupFunction<_CGEventTapEnableFn, _CGEventTapEnableNative>('CGEventTapEnable');
  _gGetIntegerValueField = cg
      .lookupFunction<_CGEventGetIntegerValueFieldFn,
          _CGEventGetIntegerValueFieldNative>('CGEventGetIntegerValueField');
  _gGetLocation = cg.lookupFunction<_CGEventGetLocationFn, _CGEventGetLocationNative>(
      'CGEventGetLocation');
  _gCreateMouseEvent = cg
      .lookupFunction<_CGEventCreateMouseEventFn, _CGEventCreateMouseEventNative>(
          'CGEventCreateMouseEvent');
  _gSetIntegerValueField = cg
      .lookupFunction<_CGEventSetIntegerValueFieldFn,
          _CGEventSetIntegerValueFieldNative>('CGEventSetIntegerValueField');
  _gPost = cg.lookupFunction<_CGEventPostFn, _CGEventPostNative>('CGEventPost');
  _gCreateKeyboardEvent = cg
      .lookupFunction<_CGEventCreateKeyboardEventFn,
          _CGEventCreateKeyboardEventNative>('CGEventCreateKeyboardEvent');
  _gSetFlags =
      cg.lookupFunction<_CGEventSetFlagsFn, _CGEventSetFlagsNative>('CGEventSetFlags');
  _gEventSourceCreate = cg
      .lookupFunction<_CGEventSourceCreateFn, _CGEventSourceCreateNative>(
          'CGEventSourceCreate');
  _gRunLoopGetCurrent = cf
      .lookupFunction<_CFRunLoopGetCurrentFn, _CFRunLoopGetCurrentNative>(
          'CFRunLoopGetCurrent');
  _gRunLoopAddSource = cf.lookupFunction<_CFRunLoopAddSourceFn, _CFRunLoopAddSourceNative>(
      'CFRunLoopAddSource');
  _gRunLoopRun =
      cf.lookupFunction<_CFRunLoopRunFn, _CFRunLoopRunNative>('CFRunLoopRun');
  _gMachPortSource = cf
      .lookupFunction<_CFMachPortCreateRunLoopSourceFn,
          _CFMachPortCreateRunLoopSourceNative>('CFMachPortCreateRunLoopSource');
  _gCFRelease = cf.lookupFunction<_CFReleaseFn, _CFReleaseNative>('CFRelease');
  _gCFStringCreate = cf
      .lookupFunction<_CFStringCreateWithCStringFn,
          _CFStringCreateWithCStringNative>('CFStringCreateWithCString');
  _gAXIsProcessTrusted = as
      .lookupFunction<_AXIsProcessTrustedFn, _AXIsProcessTrustedNative>(
          'AXIsProcessTrusted');
}

// ============================ 事件回调（后台 isolate 内执行） ============================

Pointer<Int64>? _gMouseShared;
Pointer<Int64>? _gKeyShared;
Pointer<Void>? _gCommonModes;

/// 识别鼠标事件 → (按钮编码, 是否按下)。非目标按钮返回 null。
(int, bool)? _identifyEvent(int type, Pointer<Void> event) {
  if (type == kCGEventOtherMouseDown || type == kCGEventOtherMouseUp) {
    final down = type == kCGEventOtherMouseDown;
    final btn = _gGetIntegerValueField(event, kCGMouseEventButtonNumber);
    if (btn == kCGMouseButtonCenter) return (_btnMiddle, down);
    if (btn == 3) return (_btnX1, down);
    if (btn == 4) return (_btnX2, down);
    return null;
  }
  return null;
}

/// 鼠标 tap 回调：写共享内存并吞掉事件（suppress 槽位时放行一次）。
Pointer<Void> _mouseTapCallback(
    Pointer<Void> proxy, int type, Pointer<Void> event, Pointer<Void> userInfo) {
  final sh = _gMouseShared;
  if (sh == null) return event;
  if (sh[_sSuppress] != 0) {
    sh[_sSuppress] = 0;
    return event;
  }
  final identified = _identifyEvent(type, event);
  if (identified == null) return event;
  final (button, down) = identified;
  sh[_sSeq] = sh[_sSeq] + 1;
  sh[_sButton] = button;
  sh[_sDown] = down ? 1 : 0;
  if (down) {
    final pt = _gGetLocation(event);
    sh[_sX] = (pt.x * 1000).round();
    sh[_sY] = (pt.y * 1000).round();
  }
  return nullptr;
}

/// 键盘 tap 回调（录制用）：写共享内存并吞掉。
Pointer<Void> _keyTapCallback(
    Pointer<Void> proxy, int type, Pointer<Void> event, Pointer<Void> userInfo) {
  final sh = _gKeyShared;
  if (sh == null) return event;
  if (type != kCGEventKeyDown && type != kCGEventKeyUp) return event;
  final keycode = _gGetIntegerValueField(event, kCGKeyboardEventKeycode);
  final flags = _gGetIntegerValueField(event, kCGKeyboardEventEventFlags);
  sh[_kSeq] = sh[_kSeq] + 1;
  sh[_kKeycode] = keycode;
  sh[_kMods] = flags;
  sh[_kDown] = type == kCGEventKeyDown ? 1 : 0;
  return nullptr;
}

/// 获取 kCFRunLoopCommonModes 字符串（全局缓存）。
Pointer<Void> _commonModes() {
  final cached = _gCommonModes;
  if (cached != null && cached != nullptr) return cached;
  final bytes = Uint8List.fromList('kCFRunLoopCommonModes'.codeUnits);
  final ptr = calloc<Uint8>(bytes.length + 1);
  ptr.asTypedList(bytes.length).setAll(0, bytes);
  try {
    _gCommonModes = _gCFStringCreate(nullptr, ptr, kCFStringEncodingUTF8);
    return _gCommonModes!;
  } finally {
    calloc.free(ptr);
  }
}

/// 紧急热键 tap 回调（listenOnly，不吞事件）：Ctrl+Alt+F12 → 写共享内存触发紧急停用。
Pointer<Void> _emergencyTapCallback(
    Pointer<Void> proxy, int type, Pointer<Void> event, Pointer<Void> userInfo) {
  final sh = _gMouseShared;
  if (sh == null) return event;
  if (type == kCGEventKeyDown) {
    final keycode = _gGetIntegerValueField(event, kCGKeyboardEventKeycode);
    if (keycode == 0x6F) {
      // F12
      final flags = _gGetIntegerValueField(event, kCGKeyboardEventEventFlags);
      if (flags & kCGEventFlagMaskControl != 0 &&
          flags & kCGEventFlagMaskAlternate != 0) {
        sh[_sEmerg] = 1;
      }
    }
  }
  return event;
}

/// 后台 isolate 入口：创建鼠标 tap 并进入 runloop。
void _macEventLoopMain(List<Object?> args) {
  try {
    _loadPlatformFunctions();
    _gMouseShared = Pointer<Int64>.fromAddress(args[0] as int);
    final sendPort = args[1] as SendPort;
    final mouseMask = (1 << kCGEventOtherMouseDown) | (1 << kCGEventOtherMouseUp);
    final cb = Pointer.fromFunction<_CGEventTapCallBack>(_mouseTapCallback);
    final tap = _gTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap,
        kCGEventTapOptionDefault, mouseMask, cb, nullptr);
    if (tap == nullptr) {
      sendPort.send(('error', 'CGEventTapCreate 失败：可能没有辅助功能权限'));
      return;
    }
    final source = _gMachPortSource(nullptr, tap, 0);
    final rl = _gRunLoopGetCurrent();
    // 紧急热键（Ctrl+Alt+F12）：listenOnly 键盘 tap，不吞事件
    final emergMask = (1 << kCGEventKeyDown) | (1 << kCGEventFlagsChanged);
    final emergCb =
        Pointer.fromFunction<_CGEventTapCallBack>(_emergencyTapCallback);
    final emergTap = _gTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap,
        kCGEventTapOptionListenOnly, emergMask, emergCb, nullptr);
    if (emergTap != nullptr) {
      final emergSource = _gMachPortSource(nullptr, emergTap, 0);
      _gRunLoopAddSource(rl, emergSource, _commonModes());
      _gTapEnable(emergTap, 1);
    }
    _gRunLoopAddSource(rl, source, _commonModes());
    _gTapEnable(tap, 1);
    sendPort.send(('ready', tap));
    _gRunLoopRun();
  } catch (e) {
    if (args.length >= 2) {
      (args[1] as SendPort).send(('error', '事件循环异常：$e'));
    }
  }
}

/// 键盘录制 isolate 入口。
void _macKeyLoopMain(List<Object?> args) {
  try {
    _loadPlatformFunctions();
    _gKeyShared = Pointer<Int64>.fromAddress(args[0] as int);
    final sendPort = args[1] as SendPort;
    final keyMask = (1 << kCGEventKeyDown) | (1 << kCGEventKeyUp);
    final cb = Pointer.fromFunction<_CGEventTapCallBack>(_keyTapCallback);
    final tap = _gTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap,
        kCGEventTapOptionDefault, keyMask, cb, nullptr);
    if (tap == nullptr) {
      sendPort.send(('key_error', '键盘 Tap 创建失败'));
      return;
    }
    final source = _gMachPortSource(nullptr, tap, 0);
    final rl = _gRunLoopGetCurrent();
    _gRunLoopAddSource(rl, source, _commonModes());
    _gTapEnable(tap, 1);
    sendPort.send(('key_ready', tap));
    _gRunLoopRun();
  } catch (e) {
    if (args.length >= 2) {
      (args[1] as SendPort).send(('key_error', '键盘录制异常：$e'));
    }
  }
}

// ============================ 快捷键录制器 ============================

class MacShortcutRecorder implements ShortcutRecorder {
  MacShortcutRecorder({this.mode = 'multi'});

  final String mode;
  bool _finished = false;
  bool _esc = false;
  int? _main;
  int _lastFlags = 0;
  void Function(String combo)? _onChange;
  void Function()? _onCancel;
  Timer? _watchdog;

  static const double recordTimeoutS = 30.0;

  // macOS 修饰键 keycode（左右 Shift/Ctrl/Option/Cmd + Fn），不作为主键录入
  static const Set<int> modifierKeycodes = {
    0x38, 0x3C, // Shift
    0x3B, 0x3E, // Control
    0x3A, 0x3D, // Option
    0x37, 0x36, // Command
    0x3F, // Fn
  };

  List<String> _mods(int flags) {
    final mods = <String>[];
    if (flags & kCGEventFlagMaskControl != 0) mods.add('CTRL');
    if (flags & kCGEventFlagMaskShift != 0) mods.add('SHIFT');
    if (flags & kCGEventFlagMaskAlternate != 0) mods.add('ALT');
    if (flags & kCGEventFlagMaskCommand != 0) mods.add('WIN');
    return mods;
  }

  @override
  String get combo {
    final mods = _mods(_lastFlags);
    if (_main == null) return mods.join('+');
    return [...mods, shortcut_mod.macKeycodeToName(_main!)].join('+');
  }

  void _notify() {
    try {
      _onChange?.call(combo);
    } catch (_) {}
  }

  bool handle(int keycode, int flags) {
    _lastFlags = flags;
    if (_finished) return true;
    if (keycode == 0x35) {
      // ESC 取消
      _esc = true;
      _finished = true;
      _finishWatchdog();
      try {
        _onCancel?.call();
      } catch (_) {}
      return true;
    }
    if (!modifierKeycodes.contains(keycode)) _main = keycode;
    _notify();
    return true;
  }

  @override
  void start({void Function(String combo)? onChange, void Function()? onCancel}) {
    _onChange = onChange;
    _onCancel = onCancel;
    _watchdog = Timer(Duration(milliseconds: (recordTimeoutS * 1000).round()), () {
      if (_finished) return;
      try {
        _onCancel?.call();
      } catch (_) {}
      cancel();
    });
  }

  void _finishWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  @override
  String? finish() {
    _finishWatchdog();
    _finished = true;
    if (_esc) return null;
    return combo.isEmpty ? null : combo;
  }

  @override
  void cancel() {
    _finishWatchdog();
    _finished = true;
  }
}

// ============================ 后端主类 ============================

class MacOSBackend implements PlatformBackend {
  MacOSBackend() {
    if (!Platform.isMacOS) {
      throw UnsupportedError('MacOSBackend 只能在 macOS 上使用');
    }
  }

  @override
  String get name => 'macos';

  @override
  bool get supportsCapture => true;

  MouseEventCallback? _routerCb;
  Pointer<Int64>? _mouseShared;
  Pointer<Int64>? _keyShared;
  ReceivePort? _receivePort;
  Future<Isolate>? _eventIsolate;
  Future<Isolate>? _keyIsolate;
  Timer? _pollTimer;
  bool _emergencyDisabled = false;
  int _lastSeq = 0;
  int _lastKeySeq = 0;
  bool _tapReady = false;
  MacShortcutRecorder? _activeRecorder;
  ({int x, int y})? _lastPt;

  @override
  void Function(bool emergency)? onEmergency;

  @override
  bool needsPermission() {
    try {
      _loadPlatformFunctions();
      return _gAXIsProcessTrusted() == 0;
    } catch (_) {
      return true;
    }
  }

  @override
  void requestPermission() {
    Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
    ]);
  }

  @override
  void startHook(MouseEventCallback callback) {
    _routerCb = callback;
    if (_eventIsolate != null) return;
    _loadPlatformFunctions();
    _mouseShared = calloc<Int64>(8);
    _lastSeq = 0;
    _receivePort = ReceivePort();
    _receivePort!.listen(_onIsolateMessage);
    _eventIsolate = Isolate.spawn(
      _macEventLoopMain,
      [_mouseShared!.address, _receivePort!.sendPort],
      debugName: 'mac-event-loop',
    );
    _pollTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      _poll();
      _pollKeys();
    });
  }

  void _onIsolateMessage(dynamic msg) {
    if (msg is List && msg.length == 2) {
      if (msg[0] == 'ready') {
        _tapReady = true;
      } else if (msg[0] == 'error' || msg[0] == 'key_error') {
        _tapReady = false;
      }
    }
  }

  void _poll() {
    final sh = _mouseShared;
    if (sh == null) return;
    if (sh[_sEmerg] != 0) {
      sh[_sEmerg] = 0;
      if (!_emergencyDisabled) {
        _emergencyDisabled = true;
        try {
          onEmergency?.call(true);
        } catch (_) {}
      }
    }
    final seq = sh[_sSeq];
    if (seq == _lastSeq) return;
    _lastSeq = seq;
    final button = switch (sh[_sButton]) {
      _btnMiddle => 'middle',
      _btnX1 => 'x1',
      _btnX2 => 'x2',
      _ => 'middle',
    };
    final down = sh[_sDown] == 1;
    final x = sh[_sX] ~/ 1000;
    final y = sh[_sY] ~/ 1000;
    if (down) _lastPt = (x: x, y: y);
    if (_emergencyDisabled) return;
    var swallow = false;
    try {
      swallow = _routerCb?.call(button, down) ?? false;
    } catch (_) {
      swallow = false;
    }
    if (!swallow) {
      // router 决定保留原功能：补发合成点击（_postMouseEvent 内部自动设置放行标记）
      _postMouseEvent(button, down);
    }
  }

  void _pollKeys() {
    final sh = _keyShared;
    final rec = _activeRecorder;
    if (sh == null || rec == null) {
      // 无录制会话时自动清理键盘 isolate
      if (_keyIsolate != null) _stopKeyIsolate();
      return;
    }
    final seq = sh[_kSeq];
    if (seq == _lastKeySeq) return;
    _lastKeySeq = seq;
    if (sh[_kDown] != 1) return;
    rec.handle(sh[_kKeycode], sh[_kMods]);
  }

  @override
  void stopHook() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _killIsolate(_eventIsolate);
    _eventIsolate = null;
    _stopKeyIsolate();
    _receivePort?.close();
    _receivePort = null;
    final mouseShared = _mouseShared;
    if (mouseShared != null) {
      calloc.free(mouseShared);
      _mouseShared = null;
    }
    _tapReady = false;
    _activeRecorder?.cancel();
    _activeRecorder = null;
  }

  void _killIsolate(Future<Isolate>? isolate) {
    isolate?.then((i) {
      try {
        i.kill(priority: Isolate.immediate);
      } catch (_) {}
    });
  }

  void _stopKeyIsolate() {
    _killIsolate(_keyIsolate);
    _keyIsolate = null;
    final keyShared = _keyShared;
    if (keyShared != null) {
      calloc.free(keyShared);
      _keyShared = null;
    }
    _lastKeySeq = 0;
  }

  // ============================ 注入 ============================

  void _postMouseEvent(String button, bool down) {
    try {
      final (type, cgButton) = switch (button) {
        'middle' => (down ? kCGEventOtherMouseDown : kCGEventOtherMouseUp,
            kCGMouseButtonCenter),
        'x1' => (down ? kCGEventOtherMouseDown : kCGEventOtherMouseUp, 3),
        'x2' => (down ? kCGEventOtherMouseDown : kCGEventOtherMouseUp, 4),
        _ => (kCGEventNull, kCGMouseButtonLeft),
      };
      if (type == kCGEventNull) return;
      final pt = calloc<_CGPoint>();
      try {
        final last = _lastPt;
        pt.ref.x = (last?.x ?? 0).toDouble();
        pt.ref.y = (last?.y ?? 0).toDouble();
        final ev = _gCreateMouseEvent(nullptr, type, pt.ref, cgButton);
        if (ev == nullptr) return;
        _gSetIntegerValueField(ev, kCGMouseEventButtonNumber, cgButton);
        // 放行标记：tap 回调消费一次，确保本事件（及随后的 up）不再被吞
        _mouseShared![_sSuppress] = 1;
        _gPost(kCGHIDEventTap, ev);
        _gCFRelease(ev);
      } finally {
        calloc.free(pt);
      }
    } catch (_) {}
  }

  @override
  InjectResult sendShortcut(String shortcut) {
    final upper = shortcut.toUpperCase().replaceAll(' ', '');
    if (upper == 'FN') {
      return _sendFnDoubleTap();
    }
    try {
      final normalized = shortcut_mod.normalizeShortcut(shortcut);
      final parsed = shortcut_mod.parseShortcut(normalized);
      var flags = 0;
      for (final m in parsed.mods) {
        flags |= switch (m) {
          'CTRL' => kCGEventFlagMaskControl,
          'SHIFT' => kCGEventFlagMaskShift,
          'ALT' => kCGEventFlagMaskAlternate,
          'WIN' => kCGEventFlagMaskCommand,
          _ => 0,
        };
      }
      final keycode = shortcut_mod.tokenToMacKeycode(parsed.main);
      final source = _gEventSourceCreate(0);
      try {
        final down = _gCreateKeyboardEvent(source, keycode, 1);
        _gSetFlags(down, flags);
        _gPost(kCGHIDEventTap, down);
        _gCFRelease(down);
        final up = _gCreateKeyboardEvent(source, keycode, 0);
        _gSetFlags(up, flags);
        _gPost(kCGHIDEventTap, up);
        _gCFRelease(up);
      } finally {
        _gCFRelease(source);
      }
      return InjectResult(true, '已触发 $normalized');
    } catch (e) {
      return InjectResult(false, '快捷键错误：$e');
    }
  }

  InjectResult _sendFnDoubleTap() {
    final source = _gEventSourceCreate(0);
    try {
      for (var i = 0; i < 2; i++) {
        final down = _gCreateKeyboardEvent(source, 0x3F, 1);
        _gPost(kCGHIDEventTap, down);
        _gCFRelease(down);
        final up = _gCreateKeyboardEvent(source, 0x3F, 0);
        _gPost(kCGHIDEventTap, up);
        _gCFRelease(up);
        if (i == 0) {
          sleep(const Duration(milliseconds: 120));
        }
      }
    } finally {
      _gCFRelease(source);
    }
    return const InjectResult(true, '已触发 macOS 听写（连按两下 Fn）');
  }

  @override
  InjectResult replayMouseClick(String button) {
    _postMouseEvent(button, true);
    _postMouseEvent(button, false);
    return const InjectResult(true, '已补发原鼠标点击');
  }

  // ============================ 其他接口 ============================

  @override
  List<DeviceInfo> enumerateMice() => const [];

  @override
  SafetyState checkSafety() {
    if (needsPermission()) return SafetyState.unsafePermissionDenied;
    // 第一版：无法可靠判断前台窗口是否全屏/高权限，统一按安全处理
    return SafetyState.safeDesktopText;
  }

  @override
  bool isForegroundSelf() => false;

  @override
  List<VoiceInputOption> detectVoiceInputOptions() => [
        const VoiceInputOption('macOS 听写（连按两下 Fn）', 'FN', '系统自带，需在系统设置中开启听写'),
        const VoiceInputOption('输入法语音输入（需先安装输入法）', null, '安装后重新检测'),
      ];

  @override
  ({bool ok, String message}) applyAutostart(bool enabled) {
    try {
      final home = Platform.environment['HOME'] ?? '';
      final dir = Directory('$home/Library/LaunchAgents');
      dir.createSync(recursive: true);
      final plistPath = '$dir/com.voicemouse.voicemouse.plist';
      final exe = Platform.resolvedExecutable;
      if (enabled) {
        File(plistPath).writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.voicemouse.voicemouse</string>
  <key>ProgramArguments</key>
  <array><string>$exe</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
''');
        Process.run('launchctl', ['load', plistPath]);
        return (ok: true, message: '已设置开机启动');
      } else {
        if (File(plistPath).existsSync()) {
          Process.run('launchctl', ['unload', plistPath]);
          File(plistPath).deleteSync();
        }
        return (ok: true, message: '已取消开机启动');
      }
    } catch (e) {
      return (ok: false, message: '设置开机启动失败：$e');
    }
  }

  @override
  ShortcutRecorder startShortcutRecording({String mode = 'multi'}) {
    if (!_tapReady) {
      throw StateError('鼠标监听未就绪，无法录制');
    }
    _stopKeyIsolate();
    _keyShared = calloc<Int64>(8);
    _lastKeySeq = 0;
    final sendPort = _receivePort!.sendPort;
    _keyIsolate = Isolate.spawn(
      _macKeyLoopMain,
      [_keyShared!.address, sendPort],
      debugName: 'mac-key-loop',
    );
    _activeRecorder = MacShortcutRecorder(mode: mode);
    return _activeRecorder!;
  }

  @override
  void setEmergencyDisabled(bool disabled) {
    _emergencyDisabled = disabled;
  }

  @override
  bool isEmergencyDisabled() => _emergencyDisabled;

  @override
  double getDoubleClickTime() => 0.5;

  @override
  void prepare() {}

  @override
  void cleanup() {
    stopHook();
  }
}