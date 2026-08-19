/// 运行页：状态卡片 + 紧急停用横幅 + 摘要 + 统计 + 实时测试 + 安全状态行。
library;

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class RunPage extends StatelessWidget {
  const RunPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = colorsOf(context);
    final emergency = c.backend.isEmergencyDisabled();

    return SingleChildScrollView(
      key: ValueKey('run'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== 状态卡片 =====
          _StatusCard(controller: c),
          const SizedBox(height: 14),

          // ===== 权限横幅 =====
          if (c.backend.needsPermission()) ...[
            _PermissionBanner(controller: c),
            const SizedBox(height: 14),
          ],

          // ===== 适用说明 =====
          _NoticeCard(colors: colors),
          const SizedBox(height: 14),

          // ===== 紧急停用横幅 =====
          if (emergency) ...[
            _EmergencyBanner(controller: c),
            const SizedBox(height: 14),
          ],

          // ===== 摘要 =====
          VMCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Column(
              children: [
                VMListRow(
                  title: '触发按键',
                  subtitle: '单击触发 · 双击保留原功能',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(buttonShort[c.settings['button']] ?? '中键',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colors.text)),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 18, color: colors.text3),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.hairline),
                VMListRow(
                  title: '语音快捷键',
                  subtitle: srcLabels[c.settings['shortcut_source']] ?? '',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (c.displayShortcut == 'FN 连按两下')
                        KeyBadge('FN ×2')
                      else
                        ShortcutBadges(c.displayShortcut, small: true),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 18, color: colors.text3),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ===== 为你节省 =====
          _StatsCard(controller: c),
          const SizedBox(height: 14),

          // ===== 实时测试 =====
          _TestCard(controller: c),
          const SizedBox(height: 16),

          // ===== 安全状态行 =====
          _SafetyLine(controller: c),
        ],
          ),
        ),
      ),
    );
  }
}

// ============================ 状态卡片 ============================

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = colorsOf(context);
    final running = c.running;
    final emergency = c.backend.isEmergencyDisabled();

    Color badge;
    String statusText;
    String desc;
    if (emergency) {
      badge = colors.red;
      statusText = '已紧急停用';
      desc = '鼠标按键已恢复原功能（Ctrl+Alt+F12 可随时触发）';
    } else if (running) {
      badge = colors.green;
      statusText = '正在运行';
      desc = '按一下触发键，说话即可输入';
    } else {
      badge = colors.text3;
      statusText = '已暂停';
      desc = '鼠标恢复原功能，随时可继续';
    }

    return VMCard(
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: badge,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: badge.withValues(alpha: 0.5), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusText,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: colors.text)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 12.5, color: colors.text2)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(running ? '运行中' : '已暂停',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: running ? colors.green : colors.text3)),
              const SizedBox(height: 6),
              Switch(
                value: running,
                onChanged: (v) => v ? c.startRunning() : c.pauseRunning(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================ 权限横幅 ============================

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.redSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.security, size: 18, color: colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text('需要「辅助功能」权限才能监听鼠标按键。',
                style: TextStyle(fontSize: 12.5, color: colors.text, height: 1.4)),
          ),
          const SizedBox(width: 10),
          VMFilledButton(
            label: '打开系统设置',
            background: colors.red,
            onPressed: controller.openPermission,
          ),
        ],
      ),
    );
  }
}

// ============================ 适用说明 ============================

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.colors});

  final VMColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardAlt.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: colors.text3),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 12.5, color: colors.text2, height: 1.45),
                children: [
                  const TextSpan(text: '本工具仅适用于'),
                  TextSpan(
                      text: '没有专用驱动程序的普通鼠标',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: colors.text)),
                  const TextSpan(
                      text: '。如果你的鼠标自带驱动软件（可在驱动里直接修改侧键功能），则无需使用本工具。'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ 紧急停用 ============================

class _EmergencyBanner extends StatelessWidget {
  const _EmergencyBanner({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.redSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text('语音鼠标已被紧急停用（你按过 Ctrl+Alt+F12），鼠标按键已恢复原功能。',
                style: TextStyle(fontSize: 12.5, color: colors.text, height: 1.4)),
          ),
          const SizedBox(width: 10),
          VMFilledButton(
            label: '解除紧急停用',
            background: colors.red,
            onPressed: controller.clearEmergency,
          ),
        ],
      ),
    );
  }
}

// ============================ 统计 ============================

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    final stats = controller.statsSnapshot();
    final minutes = stats['minutes_saved'] as int;

    return VMCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 16, color: colors.text2),
              const SizedBox(width: 6),
              Text('为你节省',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.text)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$minutes',
                  style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: colors.accent,
                      height: 1)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('分钟 累计',
                    style: TextStyle(fontSize: 13, color: colors.text3)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('这些时间，本来都要花在打字上（估算）',
              style: TextStyle(fontSize: 12.5, color: colors.text2)),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatCell(
                value: '${stats['words_est']}',
                unit: '字',
                label: '累计口述\n相当于少打这么多字',
                colors: colors,
              ),
              _StatCell(
                value: '${stats['speed_wpm']}',
                unit: '字/分',
                label: '平均口述速度',
                colors: colors,
              ),
              _StatCell(
                value: '${stats['days']}',
                unit: '天',
                label: '已陪伴你',
                colors: colors,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('从你第一次开口起，VoiceMouse 就一直在这里，记录、陪伴、见证你每一次说话成字。',
              style: TextStyle(fontSize: 12, color: colors.text3, height: 1.4)),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.value,
    required this.unit,
    required this.label,
    required this.colors,
  });

  final String value;
  final String unit;
  final String label;
  final VMColors colors;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                      height: 1)),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(unit,
                    style: TextStyle(fontSize: 11, color: colors.text3)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 11, color: colors.text2, height: 1.35)),
        ],
      ),
    );
  }
}

// ============================ 实时测试 ============================

class _TestCard extends StatelessWidget {
  const _TestCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    final textCtrl = TextEditingController();

    return VMCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.code, size: 17, color: colors.accent),
              const SizedBox(width: 6),
              Text('实时测试',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.text)),
            ],
          ),
          const SizedBox(height: 4),
          Text('设置完成后，在这里确认语音与滚轮都能正常工作。',
              style: TextStyle(fontSize: 12.5, color: colors.text2)),
          const SizedBox(height: 14),
          Text('语音输入', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.text2)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: textCtrl,
                  style: TextStyle(fontSize: 14, color: colors.text),
                  decoration: InputDecoration(
                    hintText: '点击这里获得输入焦点，然后按触发键说话…',
                    hintStyle: TextStyle(fontSize: 13, color: colors.text3),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: colors.cardAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              VMFilledButton(label: '测试', onPressed: controller.testShortcut),
            ],
          ),
          const SizedBox(height: 8),
          Text('点一下输入框 → 按你的触发键 → 说话，语音文字会直接出现在这里，不用再开记事本。',
              style: TextStyle(fontSize: 12, color: colors.text3, height: 1.4)),
          const SizedBox(height: 14),
          Text('滚轮 / 自动滚动', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.text2)),
          const SizedBox(height: 8),
          Container(
            height: 130,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.cardAlt,
              borderRadius: BorderRadius.circular(9),
            ),
            child: SingleChildScrollView(
              child: Text(
                '向上滚动查看上面的内容 · 1\n这是用于测试滚轮的示例内容 · 2\n滚动鼠标滚轮，内容应上下移动 · 3\n双击中键应触发自动滚动 · 4\n继续滚动查看更多 · 5\n如果滚轮没有反应 · 6\n说明设置影响了原功能 · 7\n请检查触发模式 · 8\n继续滚动 · 9\n示例行 · 10\n示例行 · 11\n示例行 · 12\n示例行 · 13\n示例行 · 14\n示例行 · 15\n示例行 · 16\n示例行 · 17\n到底了 · 18',
                style: TextStyle(fontSize: 12.5, color: colors.text2, height: 1.7),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('滚动鼠标滚轮，或按下中键（双击＝自动滚动），上方内容应随之滚动；若失效说明触发设置影响了原功能。',
              style: TextStyle(fontSize: 12, color: colors.text3, height: 1.4)),
        ],
      ),
    );
  }
}

// ============================ 安全状态行 ============================

class _SafetyLine extends StatelessWidget {
  const _SafetyLine({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    final s = controller.safety.state;
    final safe = s.safe;

    final (icon, color) = safe
        ? (Icons.spa, colors.green)
        : (Icons.lock_outline, colors.amber);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            controller.safetyLine,
            style: TextStyle(fontSize: 12.5, color: colors.text2),
          ),
        ),
      ],
    );
  }
}
