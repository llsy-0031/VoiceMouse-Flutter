/// 通用 UI 组件（苹果风）。
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 分段选择器（segmented control）
class VMSegmented extends StatelessWidget {
  const VMSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.fontSize = 13,
  });

  final List<(String, String)> options; // (value, label)
  final String value;
  final ValueChanged<String> onChanged;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.segmentBg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in options)
            GestureDetector(
              onTap: () => onChanged(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: v == value ? c.thumb : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: v == value
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: v == value ? FontWeight.w600 : FontWeight.w400,
                    color: v == value ? c.text : c.text2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 卡片
class VMCard extends StatelessWidget {
  const VMCard({super.key, required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

/// 快捷键徽章（键帽样式）
class KeyBadge extends StatelessWidget {
  const KeyBadge(this.label, {super.key, this.small = false, this.accent = false});

  final String label;
  final bool small;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 7 : 9,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: accent ? c.accentSoft : c.cardAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent ? c.accent.withValues(alpha: 0.35) : c.hairline),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: small ? 11.5 : 13,
          fontWeight: FontWeight.w600,
          color: accent ? c.accent : c.text,
          fontFamily: 'Consolas',
        ),
      ),
    );
  }
}

/// 组合键显示：拆分 `CTRL+SHIFT+V` 为键帽
class ShortcutBadges extends StatelessWidget {
  const ShortcutBadges(this.shortcut, {super.key, this.small = false});

  final String shortcut;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final parts = shortcut
        .split('+')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          KeyBadge(parts[i], small: small, accent: i == parts.length - 1),
        ],
      ],
    );
  }
}

/// 开关行（标题 + 描述 + 开关）
class VMSwitchRow extends StatelessWidget {
  const VMSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.text)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: c.text3)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// 列表行（图标 + 标题/副标题 + 右侧内容）
class VMListRow extends StatelessWidget {
  const VMListRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500, color: c.text)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: c.text3)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// 组标题
class VMGroupHead extends StatelessWidget {
  const VMGroupHead(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: c.accent),
            const SizedBox(width: 5),
          ],
          Text(text,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                  letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

/// 主按钮
class VMFilledButton extends StatelessWidget {
  const VMFilledButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.background,
    this.expand = false,
  });

  final String label;
  final VoidCallback onPressed;
  final Color? background;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final btn = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: background ?? c.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// 幽灵按钮（次要动作）
class VMGhostButton extends StatelessWidget {
  const VMGhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.foreground,
    this.expand = false,
  });

  final String label;
  final VoidCallback onPressed;
  final Color? foreground;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final btn = OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground ?? c.accent,
        side: BorderSide(color: c.hairline),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// 模态对话框骨架
Future<void> showVMModal(
  BuildContext context, {
  required String title,
  required Widget child,
  List<Widget>? actions,
  bool dismissible = true,
}) {
  return showDialog(
    context: context,
    barrierDismissible: dismissible,
    builder: (ctx) {
      final c = colorsOf(ctx);
      return Dialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: c.text)),
                const SizedBox(height: 6),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [child],
                    ),
                  ),
                ),
                if (actions != null && actions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

extension VMColorsContext on BuildContext {
  VMColors get vmColors => colorsOf(this);
}

extension on BuildContext {
}
