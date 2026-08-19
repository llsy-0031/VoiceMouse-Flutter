/// 苹果风主题（移植自原版 styles.css）。
library;

import 'package:flutter/material.dart';

class VMColors {
  const VMColors({
    required this.bg,
    required this.card,
    required this.cardAlt,
    required this.text,
    required this.text2,
    required this.text3,
    required this.hairline,
    required this.accent,
    required this.accentSoft,
    required this.green,
    required this.greenSoft,
    required this.red,
    required this.redSoft,
    required this.amber,
    required this.amberSoft,
    required this.segmentBg,
    required this.thumb,
    required this.overlay,
  });

  final Color bg;
  final Color card;
  final Color cardAlt;
  final Color text;
  final Color text2;
  final Color text3;
  final Color hairline;
  final Color accent;
  final Color accentSoft;
  final Color green;
  final Color greenSoft;
  final Color red;
  final Color redSoft;
  final Color amber;
  final Color amberSoft;
  final Color segmentBg;
  final Color thumb;
  final Color overlay;
}

/// 从 BuildContext 获取当前主题色板。
extension VMColorsContextLookup on BuildContext {
  VMColors get vmColors => _colorsOf(this);
}

/// 从 BuildContext 获取当前主题色板。
VMColors colorsOf(BuildContext context) => _colorsOf(context);

VMColors _colorsOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? vmDark : vmLight;

const VMColors vmLight = VMColors(
  bg: Color(0xFFF5F5F7),
  card: Color(0xFFFFFFFF),
  cardAlt: Color(0xFFF2F2F4),
  text: Color(0xFF1D1D1F),
  text2: Color(0xFF6E6E73),
  text3: Color(0xFF98989D),
  hairline: Color(0xFFE4E4E8),
  accent: Color(0xFF007AFF),
  accentSoft: Color(0xFFE5F1FF),
  green: Color(0xFF34C759),
  greenSoft: Color(0xFFE6F9EC),
  red: Color(0xFFFF3B30),
  redSoft: Color(0xFFFFE9E8),
  amber: Color(0xFFFF9500),
  amberSoft: Color(0xFFFFF4E2),
  segmentBg: Color(0xFFEBEBEE),
  thumb: Color(0xFFFFFFFF),
  overlay: Color(0x99000000),
);

const VMColors vmDark = VMColors(
  bg: Color(0xFF1C1C1E),
  card: Color(0xFF2C2C2E),
  cardAlt: Color(0xFF3A3A3C),
  text: Color(0xFFF5F5F7),
  text2: Color(0xFFAEAEB2),
  text3: Color(0xFF77777C),
  hairline: Color(0xFF3E3E41),
  accent: Color(0xFF0A84FF),
  accentSoft: Color(0xFF1B3A5C),
  green: Color(0xFF30D158),
  greenSoft: Color(0xFF1E3B26),
  red: Color(0xFFFF453A),
  redSoft: Color(0xFF4A2826),
  amber: Color(0xFFFFD60A),
  amberSoft: Color(0xFF4A3A1C),
  segmentBg: Color(0xFF1E1E20),
  thumb: Color(0xFF636366),
  overlay: Color(0xB3000000),
);

ThemeData buildTheme(VMColors c, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: brightness,
    primary: c.accent,
    surface: c.card,
  );
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    fontFamily: 'Microsoft YaHei',
    splashFactory: InkSparkle.splashFactory,
    textTheme: TextTheme(
      bodyLarge: TextStyle(fontSize: 15, color: c.text),
      bodyMedium: TextStyle(fontSize: 14, color: c.text),
      bodySmall: TextStyle(fontSize: 12.5, color: c.text2),
      titleLarge: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w700, color: c.text, height: 1.25),
      titleMedium: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, color: c.text, height: 1.3),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.text,
      contentTextStyle: TextStyle(color: c.bg, fontSize: 13.5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : c.text3),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.green : c.hairline),
    ),
  );
}
