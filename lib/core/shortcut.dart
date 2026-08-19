/// 快捷键解析：字符串格式跨平台一致（CTRL+SHIFT+V），各平台后端负责映射成本机按键。
library;

const List<String> modifierNames = ['CTRL', 'SHIFT', 'ALT', 'WIN'];

final Map<String, int> vkMap = _createVkMap();

Map<String, int> _createVkMap() {
  final map = <String, int>{
    'CTRL': 0x11,
    'CONTROL': 0x11,
    'SHIFT': 0x10,
    'ALT': 0x12,
    'WIN': 0x5B,
    'WINDOWS': 0x5B,
    'SPACE': 0x20,
    'ENTER': 0x0D,
    'RETURN': 0x0D,
    'TAB': 0x09,
    'ESC': 0x1B,
    'ESCAPE': 0x1B,
    'BACKSPACE': 0x08,
    'DELETE': 0x2E,
    'INSERT': 0x2D,
    'HOME': 0x24,
    'END': 0x23,
    'PGUP': 0x21,
    'PAGEUP': 0x21,
    'PGDN': 0x22,
    'PAGEDOWN': 0x22,
    'LEFT': 0x25,
    'UP': 0x26,
    'RIGHT': 0x27,
    'DOWN': 0x28,
    'CAPSLOCK': 0x14,
    'NUMLOCK': 0x90,
    ';': 0xBA,
    "'": 0xDE,
    '[': 0xDB,
    ']': 0xDD,
    '\\': 0xDC,
    '`': 0xC0,
    ',': 0xBC,
    '.': 0xBE,
    '/': 0xBF,
    '-': 0xBD,
    '=': 0xBB,
  };
  for (var i = 1; i <= 24; i++) {
    map['F$i'] = 0x6F + i;
  }
  for (final ch in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) {
    map[ch] = ch.codeUnitAt(0);
  }
  for (final d in '0123456789'.split('')) {
    map[d] = d.codeUnitAt(0);
  }
  return map;
}

/// 修饰键虚拟键码集合（含左右键码）。
const Set<int> modifierVks = {
  0x10, 0x11, 0x12, 0x5B, 0x5C, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5,
};

// macOS virtual keycodes（Apple kVK），保留以备 macOS 后端使用
final Map<String, int> macKeycodeMap = <String, int>{
  'A': 0x00, 'S': 0x01, 'D': 0x02, 'F': 0x03, 'H': 0x04, 'G': 0x05, 'Z': 0x06,
  'X': 0x07, 'C': 0x08, 'V': 0x09, 'B': 0x0B, 'Q': 0x0C, 'W': 0x0D, 'E': 0x0E,
  'R': 0x0F, 'Y': 0x10, 'T': 0x11, 'O': 0x1F, 'U': 0x20, 'I': 0x22, 'P': 0x23,
  'L': 0x25, 'J': 0x26, 'K': 0x28, 'N': 0x2D, 'M': 0x2E,
  '1': 0x12, '2': 0x13, '3': 0x14, '4': 0x15, '5': 0x17, '6': 0x16,
  '7': 0x1A, '8': 0x1C, '9': 0x19, '0': 0x1D,
  'SPACE': 0x31, 'ENTER': 0x24, 'TAB': 0x30, 'ESC': 0x35,
  'BACKSPACE': 0x33, 'DELETE': 0x75, 'HOME': 0x73, 'END': 0x77,
  'PGUP': 0x74, 'PGDN': 0x79, 'LEFT': 0x7B, 'RIGHT': 0x7C,
  'UP': 0x7E, 'DOWN': 0x7D, 'CAPSLOCK': 0x39, 'NUMLOCK': 0x47,
  ';': 0x29, "'": 0x27, '[': 0x21, ']': 0x1E, '\\': 0x2A,
  '`': 0x32, ',': 0x2B, '.': 0x2F, '/': 0x2C, '-': 0x1B, '=': 0x18,
};
// F1-F24 macOS keycodes（kVK_F1..kVK_F24）
final Map<String, int> macFnKeycodes = <String, int>{
  'F1': 0x7A, 'F2': 0x78, 'F3': 0x63, 'F4': 0x76, 'F5': 0x60,
  'F6': 0x61, 'F7': 0x62, 'F8': 0x64, 'F9': 0x65, 'F10': 0x6D,
  'F11': 0x67, 'F12': 0x6F, 'F13': 0x69, 'F14': 0x6B, 'F15': 0x71,
  'F16': 0x6A, 'F17': 0x40, 'F18': 0x4F, 'F19': 0x50, 'F20': 0x5A,
};

/// 规范化快捷键字符串："win + h" -> "WIN+H"；别名统一；非法按键抛 FormatException。
String normalizeShortcut(String text) {
  final parts = text
      .replaceAll(' ', '')
      .split('+')
      .where((p) => p.trim().isNotEmpty)
      .map((p) => p.trim().toUpperCase())
      .toList();
  if (parts.isEmpty) {
    throw const FormatException('快捷键不能为空');
  }
  const aliases = {
    'CONTROL': 'CTRL',
    'WINDOWS': 'WIN',
    'RETURN': 'ENTER',
    'ESCAPE': 'ESC',
    'PAGEUP': 'PGUP',
    'PAGEDOWN': 'PGDN',
  };
  final mapped = parts.map((p) => aliases[p] ?? p).toList();
  if (!mapped.any((p) => !modifierNames.contains(p))) {
    throw const FormatException('快捷键至少需要一个非修饰键');
  }
  for (final p in mapped) {
    if (!vkMap.containsKey(p) && !(p.startsWith('VK_') && p.length == 5)) {
      throw FormatException('暂不识别按键：$p');
    }
  }
  final mods = modifierNames.where(mapped.contains).toList();
  final mains = mapped.where((p) => !modifierNames.contains(p)).toList();
  return [...mods, ...mains].join('+');
}

/// 解析已规范化的快捷键，返回 (修饰键列表, 主键)。
({List<String> mods, String main}) parseShortcut(String shortcut) {
  final parts = shortcut.split('+');
  final mods = parts.where(modifierNames.contains).toList();
  final mains = parts.where((p) => !modifierNames.contains(p)).toList();
  if (mains.isEmpty) {
    throw const FormatException('快捷键至少需要一个非修饰键');
  }
  return (mods: mods, main: mains.first);
}

int tokenToVk(String token) {
  final t = token.toUpperCase();
  if (vkMap.containsKey(t)) return vkMap[t]!;
  if (t.startsWith('VK_')) return int.parse(t.substring(3), radix: 16);
  throw FormatException(t);
}

int tokenToMacKeycode(String token) {
  final t = token.toUpperCase();
  if (macKeycodeMap.containsKey(t)) return macKeycodeMap[t]!;
  if (macFnKeycodes.containsKey(t)) return macFnKeycodes[t]!;
  if (t.startsWith('VK_')) return int.parse(t.substring(3), radix: 16);
  throw FormatException(t);
}

String macKeycodeToName(int keycode) {
  final reversed = {for (final e in macKeycodeMap.entries) e.value: e.key};
  return reversed[keycode] ?? 'VK_${keycode.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

String vkToName(int vk) {
  const reverse = {
    0x20: 'SPACE', 0x0D: 'ENTER', 0x09: 'TAB', 0x1B: 'ESC',
    0x08: 'BACKSPACE', 0x2E: 'DELETE', 0x2D: 'INSERT', 0x24: 'HOME',
    0x23: 'END', 0x21: 'PGUP', 0x22: 'PGDN', 0x25: 'LEFT', 0x26: 'UP',
    0x27: 'RIGHT', 0x28: 'DOWN', 0x14: 'CAPSLOCK', 0x90: 'NUMLOCK',
    0xBA: ';', 0xDE: "'", 0xDB: '[', 0xDD: ']', 0xDC: '\\', 0xC0: '`',
    0xBC: ',', 0xBE: '.', 0xBF: '/', 0xBD: '-', 0xBB: '=',
  };
  if (vk >= 0x41 && vk <= 0x5A || vk >= 0x30 && vk <= 0x39) {
    return String.fromCharCode(vk);
  }
  if (vk >= 0x70 && vk <= 0x87) return 'F${vk - 0x6F}';
  return reverse[vk] ?? 'VK_${vk.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}