/// 文件日志（按天滚动目录内追加，自动轮转），供故障诊断使用。
library;

import 'dart:io';

import 'settings.dart';
import 'version.dart';

/// 单文件上限（超过则轮转）。
const int kMaxLogBytes = 512 * 1024;

/// 保留的日志文件数量（含当前文件）。
const int kMaxLogFiles = 3;

String _logsDirPath() => '${configDir().path}${Platform.pathSeparator}logs';

String _logPath() => '${_logsDirPath()}${Platform.pathSeparator}voicemouse.log';

/// 初始化：创建日志目录并写入启动头（版本 / OS / 架构）。
void logInit() {
  try {
    final dir = Directory(_logsDirPath());
    dir.createSync(recursive: true);
    final file = File(_logPath());
    if (!file.existsSync() || file.lengthSync() == 0) {
      _append('INFO', 'startup',
          'VoiceMouse v$kVersion | ${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion} | ${Platform.version}');
    }
  } catch (_) {}
}

/// 轮转：当前文件超限时把 voicemouse.log -> voicemouse.1.log -> ... 顺延。
void _rotateIfNeeded() {
  try {
    final f = File(_logPath());
    if (!f.existsSync() || f.lengthSync() < kMaxLogBytes) return;
    for (var i = kMaxLogFiles - 2; i >= 0; i--) {
      final src = i == 0
          ? _logPath()
          : '${_logsDirPath()}${Platform.pathSeparator}voicemouse.$i.log';
      final dst = '${_logsDirPath()}${Platform.pathSeparator}voicemouse.${i + 1}.log';
      if (File(src).existsSync()) File(src).renameSync(dst);
    }
  } catch (_) {}
}

void _append(String level, String tag, String message) {
  try {
    _rotateIfNeeded();
    final ts = DateTime.now().toIso8601String();
    final line = '$ts [$level] [$tag] $message\n';
    File(_logPath()).writeAsStringSync(line, mode: FileMode.append, flush: true);
  } catch (_) {}
}

void logInfo(String tag, String message) => _append('INFO', tag, message);

void logWarn(String tag, String message) => _append('WARN', tag, message);

void logError(String tag, String message) => _append('ERROR', tag, message);

void logFatal(String tag, String message) => _append('FATAL', tag, message);

/// 供"导出诊断包"使用。
List<File> logFiles() {
  final out = <File>[];
  try {
    final dir = Directory(_logsDirPath());
    if (!dir.existsSync()) return out;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    out.addAll(files);
  } catch (_) {}
  return out;
}