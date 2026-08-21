// ignore_for_file: non_constant_identifier_names, camel_case_types, library_private_types_in_public_api
import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:image/image.dart' as img;
import 'package:window_manager/window_manager.dart';

import 'app/app_controller.dart';
import 'core/log.dart';
import 'platform/macos_backend.dart';
import 'platform/platform_backend.dart';
import 'platform/win32_backend.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  logInit();
  runZonedGuarded(() {
    if (Platform.isWindows) {
      if (!ensureSingleInstance()) {
        // 不能只 return：ensureInitialized 已拉起引擎线程，进程不会退出
        exit(0);
      }
    } else if (Platform.isMacOS) {
      // macOS 单实例：文件锁（~/Library/Application Support/voicemouse.lock）
      if (!_macSingleInstance()) {
        exit(0);
      }
    }
    runApp(const VoiceMouseApp());
  }, (Object error, StackTrace stack) {
    // 未处理异常落盘，供"导出诊断包"排查
    logFatal('crash', '$error\n$stack');
  });
}

/// macOS 单实例：对 Application Support 目录下的锁文件加排他锁。
/// 第二实例抢锁失败即退出。
bool _macSingleInstance() {
  try {
    final home = Platform.environment['HOME'] ?? '';
    final dir = Directory('$home/Library/Application Support/voicemouse');
    dir.createSync(recursive: true);
    final lockFile = File('${dir.path}/single_instance.lock');
    final raf = lockFile.openSync(mode: FileMode.write);
    try {
      raf.lockSync(FileLock.exclusive);
    } on FileSystemException {
      raf.closeSync();
      return false;
    }
    // 持有锁直到进程退出（RandomAccessFile 由 GC 关闭会释放锁；显式持有引用）
    _macLock = raf;
    return true;
  } catch (_) {
    return true;
  }
}

// 防止 lock 文件句柄被 GC 提前回收（进程存活期间锁必须保持）
// ignore: unused_element
RandomAccessFile? _macLock;

/// 单实例：CreateMutexW + 激活已有窗口。
bool ensureSingleInstance() {
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final createMutex = kernel32
        .lookupFunction<IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
            int Function(Pointer<Void>, int, Pointer<Utf16>)>('CreateMutexW');
    final openMutex = kernel32.lookupFunction<IntPtr Function(Int32, Int32, Pointer<Utf16>),
        int Function(int, int, Pointer<Utf16>)>('OpenMutexW');
    final getLastError =
        kernel32.lookupFunction<Int32 Function(), int Function()>('GetLastError');
    final closeHandle = kernel32
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
    // 不用 Global\ 前缀：普通用户可能没有 SeCreateGlobalPrivilege，
    // 失败时 CreateMutexW 返回 0，导致单实例失效。默认会话命名空间即可。
    // 判断存在性用 OpenMutexW 返回值，不依赖 Dart FFI 下可能被 VM 干扰的
    // GetLastError（那会导致第二实例误判为第一实例）。
    final name = 'VoiceMouse_SingleInstance'.toNativeUtf16();
    try {
      const mutexAllAccess = 0x1F0001;
      final existing = openMutex(mutexAllAccess, 0, name);
      if (existing != 0) {
        closeHandle(existing);
        activateExistingWindow();
        return false;
      }
      final h = createMutex(nullptr, 0, name);
      if (h == 0) {
        // 无权限创建互斥：放弃单实例限制，但不阻止运行
        return true;
      }
      // 句柄不关闭：进程存活期间互斥保持存在，进程退出时系统自动释放
      // 竞态兜底：极端同时启动时，创建者之一会拿到 183
      if (getLastError() == 183) {
        activateExistingWindow();
        return false;
      }
      return true;
    } finally {
      malloc.free(name);
    }
  } catch (_) {
    return true;
  }
}

void activateExistingWindow() {
  try {
    _activateEnum(0);
  } catch (_) {}
}

typedef EnumWindowsProc = Int32 Function(IntPtr hwnd, IntPtr lParam);

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

final _EnumWindows = _user32.lookupFunction<
    Int32 Function(Pointer<NativeFunction<EnumWindowsProc>>, IntPtr),
    int Function(Pointer<NativeFunction<EnumWindowsProc>>, int)>('EnumWindows');
final _GetWindowTextLengthW = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('GetWindowTextLengthW');
final _GetWindowTextW = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>, Int32),
    int Function(int, Pointer<Utf16>, int)>('GetWindowTextW');
final _ShowWindow =
    _user32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
final _SetForegroundWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');

int _enumCallback(int hwnd, int lParam) {
  try {
    final len = _GetWindowTextLengthW(hwnd);
    if (len <= 0) return 1;
    final buf = calloc<Uint16>(len + 1);
    try {
      _GetWindowTextW(hwnd, buf.cast<Utf16>(), len + 1);
      final title = buf.cast<Utf16>().toDartString();
      if (title.toLowerCase().contains('voicemouse')) {
        _ShowWindow(hwnd, 9); // SW_RESTORE
        _SetForegroundWindow(hwnd);
        return 0;
      }
      return 1;
    } finally {
      calloc.free(buf);
    }
  } catch (_) {
    return 1;
  }
}

void _activateEnum(int unused) {
  final callback = Pointer.fromFunction<EnumWindowsProc>(_enumCallback, 1);
  _EnumWindows(callback, 0);
}

class VoiceMouseApp extends StatefulWidget {
  const VoiceMouseApp({super.key});

  @override
  State<VoiceMouseApp> createState() => _VoiceMouseAppState();
}

class _VoiceMouseAppState extends State<VoiceMouseApp>
    with TrayListener, WindowListener {
  late final PlatformBackend _backend;
  late final AppController _controller;
  AppLifecycleListener? _lifecycle;
  String? _trayIconPath;
  bool _trayHintShown = false;
  Timer? _trayHintRestoreTimer;

  @override
  void initState() {
    super.initState();
    _backend = Platform.isMacOS ? MacOSBackend() : Win32Backend();
    _controller = AppController(_backend);
    _controller.start();
    _initWindowAndTray();
    trayManager.addListener(this);
    windowManager.addListener(this);
    // 录制中切走窗口（失焦）自动退出录制，避免键盘被钩子长期吞掉
    _lifecycle = AppLifecycleListener(
      onInactive: _onWindowInactive,
    );
  }

  void _onWindowInactive() {
    if (_controller.recordingCombo != null) {
      _controller.recalCancel();
    }
  }

  Future<void> _initWindowAndTray() async {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
      // 等待窗口准备就绪后再初始化托盘，避免托盘图标绑定失败。
      // Windows 使用无边框 + 自定义顶栏；macOS 保留系统标题栏与交通灯按钮。
      await windowManager.waitUntilReadyToShow(
        WindowOptions(
          title: 'VoiceMouse',
          minimumSize: const Size(560, 800),
          size: const Size(794, 1123), // A4 竖版 @ 96 DPI
          center: true,
          backgroundColor: Colors.transparent,
          skipTaskbar: false,
          titleBarStyle:
              Platform.isWindows ? TitleBarStyle.hidden : TitleBarStyle.normal,
        ),
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      );
      await _extractTrayIcon();
      await _syncTrayMenu();
    } catch (e, stack) {
      logWarn('tray', '托盘/窗口管理初始化失败: $e\n$stack');
    }
  }

  /// 把 Flutter asset 中的 PNG 图标释放到临时目录，供 tray_manager 使用。
  /// tray_manager 需要本地文件路径，不能直接读 asset bundle。
  /// Windows 托盘原生对 ICO 兼容性最好，因此保留 PNG 源文件的同时，
  /// 在运行时把 PNG 转成多尺寸 ICO 给系统托盘显示，macOS 直接用彩色 PNG。
  Future<void> _extractTrayIcon() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final bytes = await rootBundle.load('assets/tray_icon.png');
      final pngBytes = bytes.buffer.asUint8List();
      final pngFile = File('${tempDir.path}/voicemouse_tray_icon.png');
      await pngFile.writeAsBytes(pngBytes);
      _trayIconPath = pngFile.path;

      if (Platform.isWindows) {
        // Windows 托盘需要 ICO 才能稳定显示彩色图标
        final icoFile = File('${tempDir.path}/voicemouse_tray_icon.ico');
        final icoBytes = await _pngToIco(pngBytes);
        await icoFile.writeAsBytes(icoBytes);
        _trayIconPath = icoFile.path;
      }

      await trayManager.setIcon(_trayIconPath!);
      await trayManager.setToolTip('VoiceMouse 语音鼠标');
    } catch (e, stack) {
      // 图标释放失败仍继续：保留默认图标或空托盘，不影响主体功能
      logWarn('tray', '托盘图标初始化失败: $e\n$stack');
    }
  }

  /// 将 PNG 字节转换为多尺寸 ICO 字节。
  /// 生成的 ICO 文件 Windows 托盘可正常显示彩色图标。
  Future<List<int>> _pngToIco(List<int> pngBytes) async {
    final source = img.decodePng(pngBytes);
    if (source == null) throw Exception('无法解码 tray_icon.png');

    final sizes = [16, 24, 32, 48, 64];
    final images = <img.Image>[];
    for (final size in sizes) {
      images.add(img.copyResize(source, width: size, height: size));
    }

    final ico = img.encodeIco(images);
    return ico;
  }

  Future<void> _syncTrayMenu() async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: '显示主界面'),
          MenuItem(
            key: 'toggle',
            label: _controller.running ? '暂停运行' : '继续运行',
          ),
          MenuItem(key: 'quit', label: '退出程序'),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() async {
    await _showFromTray();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showFromTray();
        break;
      case 'toggle':
        if (_controller.running) {
          _controller.pauseRunning();
        } else {
          _controller.startRunning();
        }
        _syncTrayMenu();
        break;
      case 'quit':
        _quit();
        break;
    }
  }

  @override
  void onWindowClose() async {
    // 关闭按钮不退出，而是收进托盘
    await _hideToTray();
  }

  @override
  void onWindowMinimize() async {
    // 最小化按钮直接收进托盘，不在任务栏占位
    await _hideToTray();
  }

  Future<void> _hideToTray() async {
    try {
      await windowManager.hide();
      _showTrayHintOnce();
    } catch (_) {}
  }

  Future<void> _showFromTray() async {
    try {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
    } catch (_) {}
  }

  /// 首次收到托盘提示时，把托盘 tooltip 临时改成提示文案，6 秒后恢复。
  void _showTrayHintOnce() {
    if (_trayHintShown) return;
    _trayHintShown = true;
    try {
      trayManager.setToolTip('VoiceMouse 已最小化到托盘，右键图标可退出');
      _trayHintRestoreTimer?.cancel();
      _trayHintRestoreTimer = Timer(const Duration(seconds: 6), () {
        trayManager.setToolTip('VoiceMouse 语音鼠标');
      });
    } catch (_) {}
  }

  void _quit() {
    _trayHintRestoreTimer?.cancel();
    _controller.shutdown();
    exit(0);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _trayHintRestoreTimer?.cancel();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _controller.shutdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final appearance = '${_controller.settings['appearance'] ?? 'system'}';
        final isDark = appearance == 'dark' ||
            (appearance == 'system' &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);
        final colors = isDark ? vmDark : vmLight;
        return MaterialApp(
          title: 'VoiceMouse',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(colors, isDark ? Brightness.dark : Brightness.light),
          home: AppShell(controller: _controller),
        );
      },
    );
  }
}


