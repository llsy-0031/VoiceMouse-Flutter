/// 诊断包导出：日志 + 系统信息 + 脱敏配置，复制到用户指定目录。
library;

import 'dart:convert';
import 'dart:io';

import 'log.dart';
import 'settings.dart';
import 'version.dart';

/// 导出诊断包到 [destDir]（目录将被创建）。
/// 返回 (是否成功, 提示文本)。
({bool ok, String message}) exportDiagnostics(String destDir) {
  try {
    final dir = Directory(destDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    // 系统与版本信息
    final appInfo = {
      'app': 'VoiceMouse',
      'version': kVersion,
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'dart_version': Platform.version,
      'config_dir': configDir().path,
    };
    File('${dir.path}${Platform.pathSeparator}app_info.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(appInfo));

    // 脱敏配置（当前配置无密钥类字段；若未来新增 Token 需在此排除）
    final sanitized = Map<String, dynamic>.from(defaultSettings)
      ..addAll(loadSettings());
    File('${dir.path}${Platform.pathSeparator}config_sanitized.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(sanitized));

    // 日志
    final logs = Directory('${dir.path}${Platform.pathSeparator}logs');
    if (!logs.existsSync()) logs.createSync(recursive: true);
    var logCount = 0;
    for (final f in logFiles()) {
      f.copySync('${logs.path}${Platform.pathSeparator}${f.uri.pathSegments.last}');
      logCount++;
    }

    return (ok: true, message: '诊断包已导出到：$destDir（日志 $logCount 个）');
  } catch (e) {
    return (ok: false, message: '导出诊断包失败：$e');
  }
}