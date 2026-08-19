/// 设置与统计读写（JSON 文件，路径按平台区分，与 Python 版保持兼容）。
library;

import 'dart:convert';
import 'dart:io';

const String appDirName = 'VoiceMouseMVP';

/// 当前数据 schema 版本。升级结构时递增并提供迁移逻辑（见 [migrateSettings]）。
const int kSchemaVersion = 1;

const Map<String, dynamic> defaultSettings = {
  'schema_version': kSchemaVersion,
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

/// 读取并迁移设置：旧版本缺字段补默认值；schema 升级走 [migrateSettings]。
Map<String, dynamic> loadSettings() {
  try {
    final raw = configPath().readAsStringSync();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    migrateSettings(data);
    final merged = Map<String, dynamic>.from(defaultSettings)..addAll(data);
    return merged;
  } catch (_) {
    return Map<String, dynamic>.from(defaultSettings);
  }
}

/// 设置结构迁移入口：根据旧文件中的 schema_version 逐级升级。
/// 当前只有 v1，后续新增字段时在此追加（保持幂等，失败不动原数据）。
void migrateSettings(Map<String, dynamic> data) {
  final ver = data['schema_version'] as num? ?? 0;
  if (ver == kSchemaVersion) return;
  data['schema_version'] = kSchemaVersion;
  // 示例（未来版本升级）：
  // if (ver < 2) { ... }
}

/// 原子写：先写临时文件再 rename 替换，避免崩溃/断电损坏主数据。
void _atomicWrite(File file, String content) {
  configDir().createSync(recursive: true);
  final tmp = File('${file.path}.tmp');
  tmp.writeAsStringSync(content, flush: true);
  if (file.existsSync()) {
    // 写前保留一份备份，供手动恢复
    final bak = File('${file.path}.bak');
    if (!bak.existsSync()) file.copySync(bak.path);
  }
  tmp.renameSync(file.path);
}

void saveSettings(Map<String, dynamic> settings) {
  try {
    settings['schema_version'] = kSchemaVersion;
    _atomicWrite(configPath(), const JsonEncoder.withIndent('  ').convert(settings));
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
    _atomicWrite(statsPath(), const JsonEncoder.withIndent('  ').convert(stats));
  } catch (_) {}
}

/// 重置全部数据（设置与统计），返回是否成功。
bool resetAllData() {
  try {
    for (final f in [configPath(), statsPath()]) {
      if (f.existsSync()) f.deleteSync();
    }
    return true;
  } catch (_) {
    return false;
  }
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