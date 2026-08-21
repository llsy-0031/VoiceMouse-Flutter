/// Windows 后端：Win32 Hook / SendInput / Raw Input / SafetyGate。
///
/// 设计说明（与 Python 版行为一致）：
/// - WH_MOUSE_LL 低层鼠标钩子 + WH_KEYBOARD_LL 低层键盘钩子（录制用）
/// - 所有钩子回调都在主线程的消息泵（Timer 驱动 PeekMessage）中触发，
///   因此回调内可直接访问 Dart 状态（单线程模型，无需锁）。
/// - SendInput 注入快捷键与鼠标点击补发。
library;

// 结构与函数名刻意保留 Win32/C 风格（与文档一致）
// ignore_for_file: camel_case_types, non_constant_identifier_names, library_private_types_in_public_api

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../core/safety.dart';
import '../core/shortcut.dart';
import 'platform_backend.dart';

const int whMouseLl = 14;
const int whKeyboardLl = 13;
const int wmLButtonDown = 0x0201;
const int wmLButtonUp = 0x0202;
const int wmRButtonDown = 0x0204;
const int wmRButtonUp = 0x0205;
const int wmMouseWheel = 0x020A;
const int wmMButtonDown = 0x0207;
const int wmMButtonUp = 0x0208;
const int wmXButtonDown = 0x020B;
const int wmXButtonUp = 0x020C;
const int wmKeyDown = 0x0100;
const int wmSysKeyDown = 0x0104;
const int wmHotKey = 0x0312;
const int wmQuit = 0x0012;
const int xButton1 = 0x0001;
const int xButton2 = 0x0002;
const int llMhfInjected = 0x00000001;
const int hcAction = 0;

const int inputMouse = 0;
const int inputKeyboard = 1;
const int keyEventFKeyUp = 0x0002;
const int keyEventFUnicode = 0x0004;
const int mouseEventFMiddleDown = 0x0020;
const int mouseEventFMiddleUp = 0x0040;
const int mouseEventFXDown = 0x0080;
const int mouseEventFXUp = 0x0100;

const int rimTypeMouse = 0;
const int ridiDeviceName = 0x20000007;
const int ridiDeviceInfo = 0x2000000B;
const int spiGetDoubleClickTime = 0x0032;
const int smCMouseButtons = 43; // SM_CMOUSEBUTTONS = 0x2B

const int modAlt = 0x0001;
const int modControl = 0x0002;
const int hotkeyEmergencyId = 9001;
const int vkF12 = 0x7B;

/// 'VMOU'：标记本程序注入的事件（用于回环过滤）
const int magicExtraInfo = 0x564D4F55;

const int processQueryLimitedInformation = 0x1000;
const int tokenQuery = 0x0008;
const int tokenIntegrityLevel = 25;

const Set<String> _textControlClasses = {
  'EDIT', 'RICHEDIT', 'RICHEDIT20A', 'RICHEDIT20W', 'RICHEDIT50W',
  'ATL:EDIT', 'QWidget', 'CHROME_RENDERWIDGETHOSTHWND',
};

/// 完整性级别额外结构（win32 包未提供，手动定义）
final class SID_AND_ATTRIBUTES extends Struct {
  external Pointer<Void> Sid;
  @Uint32()
  external int Attributes;
}

final class TOKEN_MANDATORY_LABEL extends Struct {
  external SID_AND_ATTRIBUTES Label;
}

/// RID_DEVICE_INFO（win32 包未提供，手动定义，必须与 C 结构完全一致）
final class RID_DEVICE_INFO_MOUSE extends Struct {
  @Uint32()
  external int dwId;
  @Uint32()
  external int dwNumberOfButtons;
  @Uint32()
  external int dwSampleRate;
  @Uint32()
  external int hasHorizontalWheel;
}

final class RID_DEVICE_INFO_KEYBOARD extends Struct {
  @Uint32()
  external int dwType;
  @Uint32()
  external int dwSubType;
  @Uint32()
  external int dwKeyboardMode;
  @Uint32()
  external int dwNumberOfFunctionKeys;
  @Uint32()
  external int dwNumberOfIndicators;
  @Uint32()
  external int dwNumberOfKeysTotal;
}

final class RID_DEVICE_INFO_HID extends Struct {
  @Uint32()
  external int dwVendorId;
  @Uint32()
  external int dwProductId;
  @Uint32()
  external int dwVersionNumber;
  @Uint16()
  external int usUsagePage;
  @Uint16()
  external int usUsage;
}

sealed class _RID_DEVICE_INFO_Union extends Union {
  external RID_DEVICE_INFO_MOUSE mouse;
  external RID_DEVICE_INFO_KEYBOARD keyboard;
  external RID_DEVICE_INFO_HID hid;
}

final class RID_DEVICE_INFO extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int dwType;
  external _RID_DEVICE_INFO_Union Anonymous;
}

/// GetSidSubAuthority*（win32 包未提供，手动绑定 advapi32）
final _advapi32 = DynamicLibrary.open('advapi32.dll');

final int Function(Pointer<Void> pSid, Pointer<Uint8> pCount) GetSidSubAuthorityCount =
    _advapi32
        .lookupFunction<Int32 Function(Pointer<Void>, Pointer<Uint8>),
            int Function(Pointer<Void>, Pointer<Uint8>)>('GetSidSubAuthorityCount');

final Pointer<Uint32> Function(Pointer<Void> pSid, int nSubAuthority) GetSidSubAuthority =
    _advapi32
        .lookupFunction<Pointer<Uint32> Function(Pointer<Void>, Uint32),
            Pointer<Uint32> Function(Pointer<Void>, int)>('GetSidSubAuthority');

/// 全局钩子桥：Pointer.fromFunction 要求静态函数，通过全局单例转发到后端实例。
Win32Backend? gHookBridge;

int _mouseHookProc(int nCode, int wParam, int lParam) {
  final b = gHookBridge;
  if (b == null) return CallNextHookEx(0, nCode, wParam, lParam);
  return b._hookProc(nCode, wParam, lParam);
}

int _keyboardHookProc(int nCode, int wParam, int lParam) {
  final b = gHookBridge;
  if (b == null) return CallNextHookEx(0, nCode, wParam, lParam);
  return b._keyboardHookProc(nCode, wParam, lParam);
}

typedef _HookProcNative = IntPtr Function(Int32 nCode, IntPtr wParam, IntPtr lParam);

final Pointer<NativeFunction<_HookProcNative>> _mouseHookFnPtr =
    Pointer.fromFunction<_HookProcNative>(_mouseHookProc, 0);
final Pointer<NativeFunction<_HookProcNative>> _keyboardHookFnPtr =
    Pointer.fromFunction<_HookProcNative>(_keyboardHookProc, 0);

/// 快捷键录制器：WH_KEYBOARD_LL 低层钩子吞掉所有按键并累积。
class Win32ShortcutRecorder implements ShortcutRecorder {
  Win32ShortcutRecorder({this.mode = 'multi'});

  final String mode;
  final Set<int> _keys = <int>{};
  int? _main;
  bool _finished = false;
  bool _esc = false;
  Timer? _watchdog;
  void Function(String combo)? _onChange;
  void Function()? _onCancel;

  /// 录制会话是否已结束（确认/取消/超时/ESC 后为 true）。
  bool get isDone => _finished;

  /// 录制最长 30 秒后自动停止并释放钩子，防止误锁键盘
  static const double recordTimeoutS = 30.0;
  static const List<int> _toggleKeys = [0x14, 0x90, 0x91];

  List<String> _mods() {
    final mods = <String>[];
    if (_keys.any((v) => const [0x11, 0xA2, 0xA3].contains(v))) mods.add('CTRL');
    if (_keys.any((v) => const [0x10, 0xA0, 0xA1].contains(v))) mods.add('SHIFT');
    if (_keys.any((v) => const [0x12, 0xA4, 0xA5].contains(v))) mods.add('ALT');
    if (_keys.any((v) => const [0x5B, 0x5C].contains(v))) mods.add('WIN');
    return mods;
  }

  @override
  String get combo {
    if (mode == 'single') return _main == null ? '' : vkToName(_main!);
    final mods = _mods();
    if (_main == null) return mods.join('+');
    return [...mods, vkToName(_main!)].join('+');
  }

  void _notify() {
    try {
      _onChange?.call(combo);
    } catch (_) {}
  }

  bool _ctrlAltDown() {
    try {
      final ctrl = GetAsyncKeyState(0x11) & 0x8000;
      final alt = GetAsyncKeyState(0x12) & 0x8000;
      return ctrl != 0 && alt != 0;
    } catch (_) {
      return false;
    }
  }

  /// 返回 True 表示吞掉该键。
  bool handle(int vk) {
    if (_finished) return false;
    // 紧急组合键 Ctrl+Alt+F12：放行并强制退出录制
    if (vk == vkF12 && _ctrlAltDown()) {
      _finished = true;
      _finishWatchdog();
      try {
        _onCancel?.call();
      } catch (_) {}
      return false;
    }
    if (vk == 0x1B) {
      // ESC 取消
      _esc = true;
      _finished = true;
      _finishWatchdog();
      try {
        _onCancel?.call();
      } catch (_) {}
      return true;
    }
    if (_toggleKeys.contains(vk)) return true;
    if (mode == 'single') {
      if (!modifierVks.contains(vk)) _main = vk;
    } else {
      _keys.add(vk);
      if (!modifierVks.contains(vk)) _main = vk;
    }
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

class Win32Backend implements PlatformBackend {
  Win32Backend() {
    if (!Platform.isWindows) {
      throw UnsupportedError('Win32Backend 只能在 Windows 上使用');
    }
    gHookBridge = this;
  }

  @override
  String get name => 'windows';

  @override
  bool get supportsCapture => true;

  @override
  bool needsPermission() => false;

  @override
  void requestPermission() {}

  MouseEventCallback? _routerCb;
  int _mouseHook = 0;
  int _keyboardHook = 0;
  bool _emergencyDisabled = false;
  Timer? _pumpTimer;
  bool _pumping = false;
  Win32ShortcutRecorder? _activeRecorder;
  ({int x, int y})? _lastHwPt;

  @override
  void Function(bool emergency)? onEmergency;

  // ============================ 钩子 ============================

  @override
  void startHook(MouseEventCallback callback) {
    _routerCb = callback;
    if (_mouseHook != 0) return;
    final hook = SetWindowsHookEx(whMouseLl, _mouseHookFnPtr, NULL, 0);
    if (hook == 0) {
      throw Win32Exception('鼠标 Hook 安装失败', GetLastError());
    }
    _mouseHook = hook;
    // 紧急热键被占用不影响主体功能
    RegisterHotKey(NULL, hotkeyEmergencyId, modControl | modAlt, vkF12);
    _startPump();
  }

  void _startPump() {
    if (_pumpTimer != null) return;
    _pumpTimer = Timer.periodic(const Duration(milliseconds: 10), (_) => _pumpOnce());
  }

  void _stopPump() {
    _pumpTimer?.cancel();
    _pumpTimer = null;
  }

  void _pumpOnce() {
    if (_pumping) return;
    _pumping = true;
    try {
      final msg = calloc<MSG>();
      try {
        var guard = 0;
        while (PeekMessage(msg, NULL, 0, 0, PM_REMOVE) != 0) {
          guard++;
          if (guard > 200) break;
          if (msg.ref.message == wmQuit) break;
          if (msg.ref.message == wmHotKey && msg.ref.wParam == hotkeyEmergencyId) {
            _emergencyDisabled = true;
            _activeRecorder?.cancel();
            _activeRecorder = null;
            onEmergency?.call(true);
          }
          TranslateMessage(msg);
          DispatchMessage(msg);
        }
      } finally {
        calloc.free(msg);
      }
    } catch (_) {
    } finally {
      _pumping = false;
    }
  }

  @override
  void stopHook() {
    _stopPump();
    if (_keyboardHook != 0) {
      UnhookWindowsHookEx(_keyboardHook);
      _keyboardHook = 0;
    }
    if (_mouseHook != 0) {
      UnregisterHotKey(NULL, hotkeyEmergencyId);
      UnhookWindowsHookEx(_mouseHook);
      _mouseHook = 0;
    }
    _activeRecorder?.cancel();
    _activeRecorder = null;
  }

  int _hookProc(int nCode, int wParam, int lParam) {
    if (nCode < hcAction) return CallNextHookEx(0, nCode, wParam, lParam);

    // 🔴🔴🔴 2026-08-20 终极保险丝（第一性原理 · 永远不放行不基本操作）！
    // 任何情况下，左键/右键/滚轮 三个"人类最基本鼠标功能"直接短路放行——
    // 不走任何 Router 逻辑、不走任何 flag 判断、不走任何状态机，
    // 就算上层代码写了再大的 bug，这三个操作 100% 跟没装软件时一模一样，
    // 绝对不会再出现"鼠标废了，左键右键点不了"的惨剧。
    if (wParam == wmLButtonDown || wParam == wmLButtonUp ||
        wParam == wmRButtonDown || wParam == wmRButtonUp ||
        wParam == wmMouseWheel) {
      return CallNextHookEx(0, nCode, wParam, lParam);
    }

    final data = Pointer.fromAddress(lParam).cast<MSLLHOOKSTRUCT>();
    // 2026-08-20 紧急修正：暂时移除 dwExtraInfo 判定，避免 struct 64 位 IntPtr 类型与 magic 比较异常
    // （该比较理论正确，但实际运行导致左键右键被吞，先回滚保稳定，防回环继续靠 llMhfInjected flag）
    if (data.ref.flags & llMhfInjected != 0) {
      return CallNextHookEx(0, nCode, wParam, lParam);
    }
    final identified = _identifyButtonEvent(wParam, data);
    if (identified == null) {
      return CallNextHookEx(0, nCode, wParam, lParam);
    }
    final (button, down) = identified;
    if (down) {
      _lastHwPt = (x: data.ref.pt.x, y: data.ref.pt.y);
    }
    if (_emergencyDisabled) {
      return CallNextHookEx(0, nCode, wParam, lParam);
    }
    var swallow = false;
    try {
      swallow = _routerCb?.call(button, down) ?? false;
    } catch (_) {
      swallow = false;
    }
    if (swallow) return 1;
    return CallNextHookEx(0, nCode, wParam, lParam);
  }

  (String, bool)? _identifyButtonEvent(int wParam, Pointer<MSLLHOOKSTRUCT> data) {
    if (wParam == wmMButtonDown) return ('middle', true);
    if (wParam == wmMButtonUp) return ('middle', false);
    if (wParam == wmXButtonDown || wParam == wmXButtonUp) {
      final which = (data.ref.mouseData >> 16) & 0xFFFF;
      // Win32 标准 XBUTTON 定义：1=x1, 2=x2, 4=x3, 8=x4, 16=x5
      final button = which == xButton1
          ? 'x1'
          : which == xButton2
              ? 'x2'
              : which == 4
                  ? 'x3'
                  : which == 8
                      ? 'x4'
                      : which == 16
                          ? 'x5'
                          : null;
      if (button != null) {
        return (button, wParam == wmXButtonDown);
      }
    }
    return null;
  }

  int _keyboardHookProc(int nCode, int wParam, int lParam) {
    if (nCode < hcAction) return CallNextHookEx(0, nCode, wParam, lParam);
    final rec = _activeRecorder;
    if (rec == null) return CallNextHookEx(0, nCode, wParam, lParam);
    if (rec.isDone) {
      // 录制已结束：立即释放钩子与录制器，避免键盘被吞
      _activeRecorder = null;
      if (_keyboardHook != 0) {
        UnhookWindowsHookEx(_keyboardHook);
        _keyboardHook = 0;
      }
      return CallNextHookEx(0, nCode, wParam, lParam);
    }
    if (wParam != wmKeyDown && wParam != wmSysKeyDown) {
      return CallNextHookEx(0, nCode, wParam, lParam);
    }
    final data = Pointer.fromAddress(lParam).cast<KBDLLHOOKSTRUCT>();
    final swallow = rec.handle(data.ref.vkCode);
    return swallow ? 1 : CallNextHookEx(0, nCode, wParam, lParam);
  }

  // ============================ 输入注入 ============================

  /// 把一组 INPUT 依次发送。返回是否全部成功。
  bool _sendInputs(List<Pointer<INPUT>> inputs) {
    var ok = true;
    for (final ptr in inputs) {
      try {
        final n = SendInput(1, ptr, sizeOf<INPUT>());
        if (n != 1) ok = false;
      } finally {
        calloc.free(ptr);
      }
    }
    return ok;
  }

  Pointer<INPUT> _keyInput({int wVk = 0, int wScan = 0, int dwFlags = 0}) {
    final input = calloc<INPUT>();
    input.ref.type = inputKeyboard;
    input.ref.ki.wVk = wVk;
    input.ref.ki.wScan = wScan;
    input.ref.ki.dwFlags = dwFlags;
    input.ref.ki.time = 0;
    input.ref.ki.dwExtraInfo = magicExtraInfo;
    return input;
  }

  @override
  InjectResult sendShortcut(String shortcut) {
    final upper = shortcut.toUpperCase().replaceAll(' ', '');
    if (upper.contains('FN')) {
      return const InjectResult(
          false,
          '苹果系统听写快捷键（连按两下 Fn）仅适用于 macOS；在 Windows 上请选择「Windows 系统语音输入（WIN+H）」或「输入法语音输入」。');
    }
    try {
      final normalized = normalizeShortcut(shortcut);
      final parsed = parseShortcut(normalized);
      final inputs = <Pointer<INPUT>>[];
      for (final m in parsed.mods) {
        inputs.add(_keyInput(wVk: tokenToVk(m)));
      }
      // 单字符且无修饰键时用 UNICODE 注入：绕过中文输入法(IME)对字母键的拦截
      if (parsed.mods.isEmpty && parsed.main.length == 1 && _isAlnum(parsed.main)) {
        final char = parsed.main.codeUnitAt(0);
        inputs.add(_keyInput(wScan: char, dwFlags: keyEventFUnicode));
        inputs.add(_keyInput(wScan: char, dwFlags: keyEventFUnicode | keyEventFKeyUp));
      } else {
        final mainVk = tokenToVk(parsed.main);
        inputs.add(_keyInput(wVk: mainVk));
        inputs.add(_keyInput(wVk: mainVk, dwFlags: keyEventFKeyUp));
      }
      for (final m in parsed.mods.reversed) {
        inputs.add(_keyInput(wVk: tokenToVk(m), dwFlags: keyEventFKeyUp));
      }
      final ok = _sendInputs(inputs);
      return ok
          ? InjectResult(true, '已触发 $normalized')
          : InjectResult(false, '快捷键注入失败：SendInput 未全部生效');
    } catch (e) {
      return InjectResult(false, '快捷键错误：$e');
    }
  }

  bool _isAlnum(String s) {
    final c = s.codeUnitAt(0);
    return (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  }

  Pointer<INPUT> _mouseInput({required int dwFlags, int mouseData = 0}) {
    final input = calloc<INPUT>();
    input.ref.type = inputMouse;
    input.ref.mi.dwFlags = dwFlags;
    input.ref.mi.mouseData = mouseData;
    input.ref.mi.time = 0;
    input.ref.mi.dwExtraInfo = magicExtraInfo;
    return input;
  }

  @override
  InjectResult replayMouseClick(String button) => _injectClick(button, 1);

  InjectResult replayDoubleClick(String button) => _injectClick(button, 2);

  InjectResult _injectClick(String button, int count) {
    // Win32 XButton 定义：XBUTTON1=1, XBUTTON2=2, XBUTTON3=4, XBUTTON4=8, XBUTTON5=16
    // 都用 MOUSEEVENTF_XDOWN / XUP，仅 mouseData（高16位）不同。
    const int xButton3 = 4;
    const int xButton4 = 8;
    const int xButton5 = 16;
    final (downFlag, upFlag, data) = switch (button) {
      'middle' => (mouseEventFMiddleDown, mouseEventFMiddleUp, 0),
      'x1' => (mouseEventFXDown, mouseEventFXUp, xButton1 << 16),
      'x2' => (mouseEventFXDown, mouseEventFXUp, xButton2 << 16),
      'x3' => (mouseEventFXDown, mouseEventFXUp, xButton3 << 16),
      'x4' => (mouseEventFXDown, mouseEventFXUp, xButton4 << 16),
      'x5' => (mouseEventFXDown, mouseEventFXUp, xButton5 << 16),
      _ => (0, 0, 0),
    };
    if (downFlag == 0) return const InjectResult(false, '未知鼠标按键');
    // 对准原始按下位置补发（避免光标移动后补发到错误位置）
    final pos = _lastHwPt;
    if (pos != null) {
      try {
        SetCursorPos(pos.x, pos.y);
      } catch (_) {}
    }
    var ok = true;
    for (var i = 0; i < count; i++) {
      final inputs = [
        _mouseInput(dwFlags: downFlag, mouseData: data),
        _mouseInput(dwFlags: upFlag, mouseData: data),
      ];
      if (!_sendInputs(inputs)) ok = false;
      if (i < count - 1) {
        sleep(const Duration(milliseconds: 100));
      }
    }
    return ok
        ? const InjectResult(true, '已补发原鼠标点击')
        : const InjectResult(false, '补发原鼠标点击失败');
  }

  // ============================ 设备枚举 ============================

  @override
  List<DeviceInfo> enumerateMice() {
    final result = <DeviceInfo>[];
    try {
      final count = calloc<Uint32>();
      try {
        if (GetRawInputDeviceList(nullptr, count, sizeOf<RAWINPUTDEVICELIST>()) ==
            0xFFFFFFFF) {
          return result;
        }
        if (count.value == 0) return result;
        final list = calloc<RAWINPUTDEVICELIST>(count.value);
        try {
          final got = GetRawInputDeviceList(list, count, sizeOf<RAWINPUTDEVICELIST>());
          if (got == 0xFFFFFFFF) return result;
          for (var i = 0; i < got; i++) {
            if (list[i].dwType != rimTypeMouse) continue;
            // 设备名
            final size = calloc<Uint32>();
            try {
              if (GetRawInputDeviceInfo(list[i].hDevice, ridiDeviceName, nullptr, size) ==
                  0xFFFFFFFF) {
                result.add(DeviceInfo('未知鼠标设备', 0));
                continue;
              }
              var name = '未知鼠标设备';
              if (size.value > 0) {
                // size.value 是所需字节数（含 NUL）。部分驱动实现会写满
                // 传入的缓冲区并追加终止符，这里按 3 倍冗余分配。
                final bufBytes = size.value * 3 + 4;
                final buf = calloc<Uint8>(bufBytes);
                try {
                  size.value = bufBytes;
                  if (GetRawInputDeviceInfo(
                          list[i].hDevice, ridiDeviceName, buf, size) !=
                      0xFFFFFFFF) {
                    name = _utf16ToString(buf.cast<Uint16>(), size.value ~/ 2);
                  }
                } finally {
                  calloc.free(buf);
                }
              }
              // 设备信息
              final info = calloc<RID_DEVICE_INFO>();
              try {
                info.ref.cbSize = sizeOf<RID_DEVICE_INFO>();
                final infoSize = calloc<Uint32>();
                try {
                  infoSize.value = sizeOf<RID_DEVICE_INFO>();
                  var buttons = 0;
                  if (GetRawInputDeviceInfo(list[i].hDevice, ridiDeviceInfo,
                          info.cast<Void>(), infoSize) !=
                      0xFFFFFFFF) {
                    buttons = info.ref.Anonymous.mouse.dwNumberOfButtons;
                  }
                  result.add(DeviceInfo(name, buttons));
                } finally {
                  calloc.free(infoSize);
                }
              } finally {
                calloc.free(info);
              }
            } finally {
              calloc.free(size);
            }
          }
        } finally {
          calloc.free(list);
        }
      } finally {
        calloc.free(count);
      }
    } catch (_) {}
    return result;
  }

String _utf16ToString(Pointer<Uint16> buf, int maxLen) {
  final units = Uint16List(maxLen);
  for (var i = 0; i < maxLen; i++) {
    final u = buf[i];
    if (u == 0) break;
    units[i] = u;
  }
  return String.fromCharCodes(units);
}

  // ============================ SafetyGate ============================

  @override
  SafetyState checkSafety() {
    try {
      return _checkSafetyImpl();
    } catch (_) {
      return SafetyState.unsafeUnknown;
    }
  }

  SafetyState _checkSafetyImpl() {
    final fg = GetForegroundWindow();
    if (fg == 0) return SafetyState.unsafeUnknown;

    final pid = calloc<Uint32>();
    try {
      final tid = GetWindowThreadProcessId(fg, pid);
      if (tid == 0) return SafetyState.unsafeUnknown;

      if (_isLockedOrSecure()) return SafetyState.unsafeSecureDesktop;
      if (_isElevatedTarget(pid.value)) return SafetyState.unsafeElevatedTarget;

      final textEvidence = _hasTextTarget(tid, fg);
      if (_isFullscreen(fg) && !textEvidence) return SafetyState.unsafeFullscreen;
      if (!textEvidence) return SafetyState.unsafeNoTextTarget;
      return SafetyState.safeDesktopText;
    } finally {
      calloc.free(pid);
    }
  }

  bool _isLockedOrSecure() {
    try {
      final exe = _foregroundExeName();
      if (exe != null &&
          const ['lockapp.exe', 'logonui.exe', 'shellexperiencehost.exe']
              .contains(exe.toLowerCase())) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  String? _foregroundExeName() {
    final fg = GetForegroundWindow();
    if (fg == 0) return null;
    final pid = calloc<Uint32>();
    try {
      GetWindowThreadProcessId(fg, pid);
      final h = OpenProcess(processQueryLimitedInformation, 0, pid.value);
      if (h == 0) return null;
      try {
        final buf = calloc<Uint16>(1024);
        try {
          final size = calloc<Uint32>();
          try {
            size.value = 1024;
            if (QueryFullProcessImageName(h, 0, buf.cast<Utf16>(), size) == 0) return null;
            return _utf16ToString(buf, size.value).split(r'\').last;
          } finally {
            calloc.free(size);
          }
        } finally {
          calloc.free(buf);
        }
      } finally {
        CloseHandle(h);
      }
    } finally {
      calloc.free(pid);
    }
  }

  bool _isElevatedTarget(int pid) {
    try {
      final ourLevel = _processIntegrity(GetCurrentProcessId());
      final theirLevel = _processIntegrity(pid);
      if (ourLevel == null || theirLevel == null) return false;
      return theirLevel > ourLevel;
    } catch (_) {
      return false;
    }
  }

  /// 返回进程完整性级别（SID 子权威值）。8=System, 7=High, 5=Medium, 4=Low
  int? _processIntegrity(int pid) {
    final h = OpenProcess(processQueryLimitedInformation, 0, pid);
    if (h == 0) return null;
    try {
      final htoken = calloc<IntPtr>();
      try {
        if (OpenProcessToken(h, tokenQuery, htoken) == 0) return null;
        final label = calloc<TOKEN_MANDATORY_LABEL>();
        try {
          final size = calloc<Uint32>();
          try {
            final ok = GetTokenInformation(htoken.value, tokenIntegrityLevel,
                label.cast<Void>(), sizeOf<TOKEN_MANDATORY_LABEL>(), size);
            if (ok == 0) return null;
            final sid = label.ref.Label.Sid;
            if (sid == nullptr) return null;
            final count = calloc<Uint8>();
            try {
              GetSidSubAuthorityCount(sid, count);
              if (count.value == 0) return null;
              final sub = GetSidSubAuthority(sid, count.value - 1);
              return sub.value;
            } finally {
              calloc.free(count);
            }
          } finally {
            calloc.free(size);
          }
        } finally {
          calloc.free(label);
        }
      } finally {
        CloseHandle(htoken.value);
        calloc.free(htoken);
      }
    } finally {
      CloseHandle(h);
    }
  }

  bool _hasTextTarget(int tid, int fg) {
    final info = calloc<GUITHREADINFO>();
    try {
      info.ref.cbSize = sizeOf<GUITHREADINFO>();
      if (GetGUIThreadInfo(tid, info) != 0) {
        final caretArea = (info.ref.rcCaret.right - info.ref.rcCaret.left) *
            (info.ref.rcCaret.bottom - info.ref.rcCaret.top);
        if (info.ref.hwndCaret != 0 && caretArea >= 2) return true;
        final focusClass = _windowClass(info.ref.hwndFocus);
        if (focusClass != null && _textControlClasses.contains(focusClass)) return true;
        final caretClass = _windowClass(info.ref.hwndCaret);
        if (caretClass != null && _textControlClasses.contains(caretClass)) return true;
      }
      final fgClass = _windowClass(fg);
      if (fgClass != null && _textControlClasses.contains(fgClass)) return true;
      return false;
    } finally {
      calloc.free(info);
    }
  }

  String? _windowClass(int hwnd) {
    if (hwnd == 0) return null;
    final buf = calloc<Uint16>(256);
    try {
      final n = GetClassName(hwnd, buf.cast<Utf16>(), 255);
      return n == 0 ? null : _utf16ToString(buf, 255).toUpperCase();
    } finally {
      calloc.free(buf);
    }
  }

  bool _isFullscreen(int fg) {
    final rect = calloc<RECT>();
    try {
      if (GetWindowRect(fg, rect) == 0) return false;
      final monitor = MonitorFromWindow(fg, MONITOR_DEFAULTTONEAREST);
      final mi = calloc<MONITORINFO>();
      try {
        mi.ref.cbSize = sizeOf<MONITORINFO>();
        if (GetMonitorInfo(monitor, mi) == 0) return false;
        final winW = rect.ref.right - rect.ref.left;
        final winH = rect.ref.bottom - rect.ref.top;
        // 重要：分母必须用「物理屏幕总尺寸 rcMonitor」而非「工作区 rcWork」。
        // - rcWork 会扣除任务栏/停靠栏，导致普通最大化浏览器 = 1.0 → 误判为全屏。
        // - rcMonitor 是整个显示器的像素大小，只有"独占全屏"（游戏/VLC 全屏等）
        //   的窗口才会覆盖任务栏，尺寸接近 rcMonitor。
        final monW = mi.ref.rcMonitor.right - mi.ref.rcMonitor.left;
        final monH = mi.ref.rcMonitor.bottom - mi.ref.rcMonitor.top;
        if (monW <= 0 || monH <= 0) return false;
        // 面积占比 97% 以上才认为是"独占全屏"（普通最大化仅覆盖 rcWork≈90%）
        return (winW * winH) / (monW * monH) >= 0.97;
      } finally {
        calloc.free(mi);
      }
    } finally {
      calloc.free(rect);
    }
  }

  // ============================ 开机启动 ============================

  @override
  ({bool ok, String message}) applyAutostart(bool enabled) {
    try {
      const keyPath = r'Software\Microsoft\Windows\CurrentVersion\Run';
      final key = calloc<IntPtr>();
      try {
        final open = RegOpenKeyEx(
            HKEY_CURRENT_USER, keyPath.toNativeUtf16(), 0, KEY_SET_VALUE, key);
        if (open != ERROR_SUCCESS) {
          return (ok: false, message: '开机启动设置失败：无法打开注册表 Run 键');
        }
        try {
          if (enabled) {
            final exe = Platform.resolvedExecutable;
            final cmd = '"$exe"';
            final cmdPtr = cmd.toNativeUtf16();
            final namePtr = 'VoiceMouseMVP'.toNativeUtf16();
            try {
              final r = RegSetValueEx(key.value, namePtr, 0, REG_SZ,
                  cmdPtr.cast<Uint8>(), (cmd.length + 1) * 2);
              if (r != ERROR_SUCCESS) {
                return (ok: false, message: '开机启动设置失败：RegSetValueEx=$r');
              }
            } finally {
              malloc.free(cmdPtr);
              malloc.free(namePtr);
            }
          } else {
            final namePtr = 'VoiceMouseMVP'.toNativeUtf16();
            try {
              RegDeleteValue(key.value, namePtr);
            } finally {
              malloc.free(namePtr);
            }
          }
          return (ok: true, message: enabled ? '已设置开机启动' : '已取消开机启动');
        } finally {
          RegCloseKey(key.value);
        }
      } finally {
        calloc.free(key);
      }
    } catch (e) {
      return (ok: false, message: '开机启动设置失败：$e');
    }
  }

  // ============================ 快捷键录制 ============================

  @override
  Win32ShortcutRecorder startShortcutRecording({String mode = 'multi'}) {
    final rec = Win32ShortcutRecorder(mode: mode);
    _activeRecorder = rec;
    if (_keyboardHook == 0) {
      final hook = SetWindowsHookEx(whKeyboardLl, _keyboardHookFnPtr, NULL, 0);
      if (hook == 0) {
        _activeRecorder = null;
        throw Win32Exception('键盘 Hook 安装失败', GetLastError());
      }
      _keyboardHook = hook;
    }
    return rec;
  }

  @override
  void stopShortcutRecording() {
    // 幂等：随时调用都安全。强制卸载键盘钩子 + 清理录制器，防"键盘被锁"。
    try {
      _activeRecorder?.cancel();
    } catch (_) {}
    _activeRecorder = null;
    if (_keyboardHook != 0) {
      UnhookWindowsHookEx(_keyboardHook);
      _keyboardHook = 0;
    }
  }

  // ============================ 紧急停用 ============================

  @override
  void setEmergencyDisabled(bool disabled) {
    _emergencyDisabled = disabled;
    if (!disabled) _activeRecorder = null;
  }

  @override
  bool isEmergencyDisabled() => _emergencyDisabled;

  @override
  bool isForegroundSelf() {
    try {
      final fg = GetForegroundWindow();
      if (fg == 0) return false;
      final pid = calloc<Uint32>();
      try {
        GetWindowThreadProcessId(fg, pid);
        return pid.value == GetCurrentProcessId();
      } finally {
        calloc.free(pid);
      }
    } catch (_) {
      return false;
    }
  }

  // ============================ 输入法识别 ============================

  static const List<(List<String>, String?, String)> _imeVoiceHints = [
    (['sogou', '搜狗'], 'CTRL+SHIFT+0', '搜狗输入法「语音输入」快捷键（常见默认值，请以输入法设置为准）'),
    (['ifly', '讯飞', 'iflyime'], 'CTRL+SHIFT+0', '讯飞输入法「语音输入」快捷键（常见默认值，请以输入法设置为准）'),
    (['baidu', '百度'], 'CTRL+SHIFT+0', '百度输入法「语音输入」快捷键（常见默认值，请以输入法设置为准）'),
    (['qq', 'qq输入'], null, 'QQ 输入法暂无独立语音输入，可用系统 WIN+H 或自定义'),
    (['微软拼音', 'pinyin', 'mspy', 'chsime'], 'WIN+H', '微软拼音无独立语音输入，用系统语音输入 WIN+H'),
    (['wubi', '五笔'], null, '五笔输入法无语音输入，可用系统 WIN+H 或自定义'),
  ];

  @override
  List<VoiceInputOption> detectVoiceInputOptions() {
    final groups = <String, VoiceInputOption>{};
    for (final name in _enumerateImeNames()) {
      final lower = name.toLowerCase();
      for (final (keywords, shortcut, note) in _imeVoiceHints) {
        if (keywords.any((k) => lower.contains(k.toLowerCase()))) {
          final key = (keywords.map((k) => k.toLowerCase()).toList()..sort()).join(',');
          final cur = groups[key];
          if (cur == null || name.length > cur.name.length) {
            groups[key] = VoiceInputOption(name, shortcut, note);
          }
          break;
        }
      }
    }

    // 讯飞输入法：语音输入快捷键真实存于注册表
    final iflyKey =
        (const ['ifly', '讯飞', 'iflyime'].map((k) => k.toLowerCase()).toList()..sort())
            .join(',');
    final real = _readIflyVoiceHotkey();
    if (real != null) {
      groups[iflyKey] = VoiceInputOption(
          groups[iflyKey]?.name ?? '讯飞输入法',
          real,
          '讯飞输入法注册表记录的语音输入快捷键（默认多为 Ctrl+Shift+Alt+[；若你在输入法设置里改过而这里对不上，用「录制校准」对准）');
    }

    final out = <VoiceInputOption>[];
    for (final opt in groups.values) {
      var shortcut = opt.shortcut;
      if (shortcut != null) {
        try {
          shortcut = normalizeShortcut(shortcut);
        } catch (_) {
          shortcut = null;
        }
      }
      out.add(VoiceInputOption(opt.name, shortcut, opt.note));
    }
    return out;
  }

  String? _readIflyVoiceHotkey() {
    try {
      final key = calloc<IntPtr>();
      try {
        final open = RegOpenKeyEx(HKEY_CURRENT_USER,
            r'Software\iFly Info Tek\iFlyIME'.toNativeUtf16(), 0, KEY_READ, key);
        if (open != ERROR_SUCCESS) return null;
        try {
          return _regQueryString(key.value, 'iFlyImeVoiceShiftHotKey');
        } finally {
          RegCloseKey(key.value);
        }
      } finally {
        calloc.free(key);
      }
    } catch (_) {
      return null;
    }
  }

  List<String> _enumerateImeNames() {
    final names = <String>[];
    try {
      void walk(int key, int depth) {
        if (depth > 5) return;
        var i = 0;
        while (true) {
          final sub = calloc<Uint16>(512);
          final subSize = calloc<Uint32>()..value = 511;
          try {
            final r = RegEnumKeyEx(key, i, sub.cast<Utf16>(), subSize, nullptr, nullptr, nullptr, nullptr);
            if (r != ERROR_SUCCESS) break;
            i++;
            final subName = _utf16ToString(sub, subSize.value);
            final sk = calloc<IntPtr>();
            try {
              final open = RegOpenKeyEx(key, subName.toNativeUtf16(), 0, KEY_READ, sk);
              if (open == ERROR_SUCCESS) {
                for (final valueName in const ['ProfileDescription', 'DisplayName', 'Description']) {
                  final desc = _regQueryString(sk.value, valueName);
                  if (desc != null && desc.isNotEmpty) names.add(desc);
                }
                walk(sk.value, depth + 1);
                RegCloseKey(sk.value);
              }
            } finally {
              calloc.free(sk);
            }
          } finally {
            calloc.free(sub);
            calloc.free(subSize);
          }
        }
      }

      for (final (hive, path) in const [
        (HKEY_CURRENT_USER, r'Software\Microsoft\CTF\TIP'),
        (HKEY_LOCAL_MACHINE, r'SOFTWARE\Microsoft\CTF\TIP'),
        (HKEY_LOCAL_MACHINE, r'SOFTWARE\WOW6432Node\Microsoft\CTF\TIP'),
      ]) {
        try {
          final key = calloc<IntPtr>();
          try {
            final open = RegOpenKeyEx(hive, path.toNativeUtf16(), 0, KEY_READ, key);
            if (open == ERROR_SUCCESS) {
              walk(key.value, 0);
              RegCloseKey(key.value);
            }
          } finally {
            calloc.free(key);
          }
        } catch (_) {}
      }

      // Keyboard Layout\Preload -> 布局名称
      try {
        final preload = calloc<IntPtr>();
        try {
          final open = RegOpenKeyEx(
              HKEY_CURRENT_USER, r'Keyboard Layout\Preload'.toNativeUtf16(), 0, KEY_READ, preload);
          if (open == ERROR_SUCCESS) {
            var i = 0;
            while (true) {
              final vname = calloc<Uint16>(512);
              final vnameSize = calloc<Uint32>()..value = 511;
              final vdata = calloc<Uint8>(512);
              final vdataSize = calloc<Uint32>()..value = 511;
              try {
                final r = RegEnumValue(
                    preload.value, i, vname.cast<Utf16>(), vnameSize, nullptr, nullptr, vdata, vdataSize);
                if (r != ERROR_SUCCESS) break;
                i++;
                final layout = _utf16ToString(vdata.cast<Uint16>(), vdataSize.value ~/ 2);
                final kl = calloc<IntPtr>();
                try {
                  final open2 = RegOpenKeyEx(
                      HKEY_LOCAL_MACHINE,
                      (r'SYSTEM\CurrentControlSet\Control\Keyboard Layouts\' + layout)
                          .toNativeUtf16(),
                      0,
                      KEY_READ,
                      kl);
                  if (open2 == ERROR_SUCCESS) {
                    for (final valueName in const ['Layout Text', 'Layout File', 'IME File']) {
                      final txt = _regQueryString(kl.value, valueName);
                      if (txt != null && txt.isNotEmpty) names.add(txt);
                    }
                    RegCloseKey(kl.value);
                  }
                } finally {
                  calloc.free(kl);
                }
              } finally {
                calloc.free(vname);
                calloc.free(vnameSize);
                calloc.free(vdata);
                calloc.free(vdataSize);
              }
            }
            RegCloseKey(preload.value);
          }
        } finally {
          calloc.free(preload);
        }
      } catch (_) {}
    } catch (_) {}
    final out = <String>[];
    for (final n in names) {
      if (n.isNotEmpty && !out.contains(n)) out.add(n);
    }
    return out;
  }

  String? _regQueryString(int key, String valueName) {
    try {
      final vn = valueName.toNativeUtf16();
      try {
        final size = calloc<Uint32>();
        try {
          size.value = 0;
          final r = RegQueryValueEx(key, vn, nullptr, nullptr, nullptr, size);
          if (r != ERROR_SUCCESS || size.value == 0) return null;
          final buf = calloc<Uint8>(size.value);
          try {
            final r2 = RegQueryValueEx(key, vn, nullptr, nullptr, buf, size);
            if (r2 != ERROR_SUCCESS) return null;
            return String.fromCharCodes(
                buf.cast<Uint16>().asTypedList(size.value ~/ 2).where((c) => c != 0));
          } finally {
            calloc.free(buf);
          }
        } finally {
          calloc.free(size);
        }
      } finally {
        malloc.free(vn);
      }
    } catch (_) {
      return null;
    }
  }

  // ============================ 其他 ============================

  @override
  int getMouseButtons() {
    try {
      final n = GetSystemMetrics(smCMouseButtons);
      if (n >= 3) return n;
    } catch (_) {}
    // 兜底：遍历 Raw Input 枚举到的设备，取最大 buttons 值
    try {
      int m = 3;
      for (final d in enumerateMice()) {
        if (d.buttons > m) m = d.buttons;
      }
      return m;
    } catch (_) {
      return 3;
    }
  }

  @override
  double getDoubleClickTime() {
    try {
      final ms = calloc<Uint32>();
      try {
        if (SystemParametersInfo(spiGetDoubleClickTime, 0, ms, 0) != 0) {
          final raw = ms.value / 1000.0;
          // 2026-08-20 调整：贴合用户"系统实际设置的双击节奏"，不做之前的 250~350ms 强卡。
          // - 夹逼到 200ms ~ 550ms（覆盖用户系统常见设置 200~450ms）
          // - ×1.1 容忍余量：用户实际按键速度会略慢于系统边界值，加 10% 避免漏判
          // - 这样能 100% 匹配"平常双击打开任何软件"的真实手感
          return (raw * 1.1).clamp(0.20, 0.55);
        }
      } finally {
        calloc.free(ms);
      }
    } catch (_) {}
    return 0.3; // 兜底 300ms（最常用的双击节奏）
  }

  @override
  void prepare() {}

  @override
  void cleanup() {
    stopHook();
    gHookBridge = null;
  }
}

class Win32Exception implements Exception {
  const Win32Exception(this.message, this.code);
  final String message;
  final int code;
  @override
  String toString() => '$message（Win32=$code）';
}
