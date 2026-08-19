/// 设置与统计读写（JSON 文件，路径按平台区分，与 Python 版保持兼容）。
library;

import 'dart:convert';
import 'dart:io';

const String appDirName = 'VoiceMouseMVP';

const Map<String, dynamic> defaultSettings = {
  'button': 'middle',
  'mode': 'tap_double',
  'shortcut': 'WIN+H',
  'shortcut_source': 'system',
  'shortcut_manual': false,
  'ime_selection': '',
  'autostart': false,
  'enabled': true,
  'appearance': 'system',
};

Directory configDir() {
  String base;
  if (Platform.isMacOS) {
    base = '${Platform.environment['HOME'] ?? '.'}/Library/Application Support';
  } else {
    base = Platform.environment['APPDATA'] ??
        '${Platform.environment['HOME'] ?? '.'}/.config';
  }
  return Directory('$base${Platform.pathSeparator}$appDirName');
}

File configPath() => File('${configDir().path}${Platform.pathSeparator}settings.json');
File statsPath() => File('${configDir().path}${Platform.pathSeparator}stats.json');

Map<String, dynamic> loadSettings() {
  try {
    final raw = configPath().readAsStringSync();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final merged = Map<String, dynamic>.from(defaultSettings)..addAll(data);
    return merged;
  } catch (_) {
    return Map<String, dynamic>.from(defaultSettings);
  }
}

void saveSettings(Map<String, dynamic> settings) {
  try {
    configDir().createSync(recursive: true);
    configPath().writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(settings),
      flush: true,
    );
  } catch (_) {
    // 写失败不阻断主流程
  }
}

// ============================ 统计 ============================

Map<String, dynamic> loadStats() {
  Map<String, dynamic> data;
  try {
    data = jsonDecode(statsPath().readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    data = <String, dynamic>{};
  }
  var changed = false;
  if (data['first_use'] == null) {
    data['first_use'] = DateTime.now().millisecondsSinceEpoch / 1000.0;
    changed = true;
  }
  data['trigger_count'] ??= 0;
  if (changed) saveStats(data);
  return data;
}

void saveStats(Map<String, dynamic> stats) {
  try {
    configDir().createSync(recursive: true);
    statsPath().writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(stats),
      flush: true,
    );
  } catch (_) {}
}

/// 每次真正触发一次语音输入时调用。
void recordTrigger() {
  try {
    final s = loadStats();
    s['trigger_count'] = (s['trigger_count'] as num? ?? 0) + 1;
    saveStats(s);
  } catch (_) {}
}

int daysSinceFirstUse() {
  try {
    final first = (loadStats()['first_use'] as num).toDouble();
    return ((DateTime.now().millisecondsSinceEpoch / 1000.0) - first) ~/ 86400;
  } catch (_) {
    return 0;
  }
}

int triggerCount() {
  try {
    return (loadStats()['trigger_count'] as num? ?? 0).toInt();
  } catch (_) {
    return 0;
  }
}

/// 按每次语音输入平均约 15 秒估算节省的打字时间。
int estimatedMinutesSaved({double secondsPerTrigger = 15.0}) =>
    (triggerCount() * secondsPerTrigger / 60).floor();