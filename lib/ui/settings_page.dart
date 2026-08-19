/// 设置页：触发 / 语音 / 通用 三组 + 弹窗（自动识别、录制校准、关于）。
library;

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = colorsOf(context);
    final src = '${c.settings['shortcut_source'] ?? 'system'}';
    final mode = '${c.settings['mode'] ?? 'tap_double'}';
    final appearance = '${c.settings['appearance'] ?? 'system'}';

    return SingleChildScrollView(
      key: const ValueKey('settings'),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设置', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: colors.text)),
          const SizedBox(height: 2),
          Text('选择触发按键与语音快捷键，改动即时保存生效',
              style: TextStyle(fontSize: 13, color: colors.text2)),
          const SizedBox(height: 8),

          // ===== 触发 =====
          const VMGroupHead('触发', icon: Icons.mouse_outlined),
          VMCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VMListRow(
                  title: '使用按键',
                  subtitle: '单击触发语音 · 双击保留原功能',
                  trailing: const SizedBox.shrink(),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    VMSegmented(
                      options: const [
                        ('middle', '中键'),
                        ('x1', '侧键 1'),
                        ('x2', '侧键 2'),
                      ],
                      value: '${c.settings['button'] ?? 'middle'}',
                      onChanged: c.setButton,
                    ),
                    const Spacer(),
                    VMGhostButton(label: '自动识别', onPressed: () => _openDetect(context)),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: colors.hairline),
                const SizedBox(height: 4),
                VMListRow(
                  title: '触发模式',
                  subtitle: modeHints[mode] ?? '',
                  trailing: VMSegmented(
                    options: const [
                      ('tap_double', '单击语音'),
                      ('replace', '完全替换'),
                    ],
                    value: mode,
                    onChanged: c.setMode,
                  ),
                ),
                const SizedBox(height: 8),
                VMGhostButton(label: '设备详情', expand: true, onPressed: () => _openDevices(context)),
              ],
            ),
          ),

          // ===== 语音 =====
          const VMGroupHead('语音', icon: Icons.keyboard_outlined),
          VMCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VMListRow(
                  title: '快捷键来源',
                  subtitle: _srcHint(src),
                  trailing: VMSegmented(
                    options: const [
                      ('system', '系统'),
                      ('macos', 'macOS'),
                      ('ime', '输入法'),
                    ],
                    value: src,
                    onChanged: c.setSource,
                  ),
                ),
                const SizedBox(height: 4),
                Divider(height: 1, color: colors.hairline),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('当前快捷键',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w500, color: colors.text)),
                          const SizedBox(height: 4),
                          if (c.displayShortcut == 'FN 连按两下')
                            const KeyBadge('FN ×2')
                          else
                            ShortcutBadges(c.displayShortcut),
                        ],
                      ),
                    ),
                    VMGhostButton(label: '测试', onPressed: c.testShortcut),
                  ],
                ),
                if (src == 'ime') ...[
                  const SizedBox(height: 12),
                  Divider(height: 1, color: colors.hairline),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('输入法',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: colors.text)),
                            const SizedBox(height: 4),
                            _ImeSelector(controller: c),
                            if (_imeNote(c) != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(_imeNote(c)!,
                                    style: TextStyle(
                                        fontSize: 11.5, color: colors.text3, height: 1.4)),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      VMGhostButton(label: '录制校准', onPressed: () => _openRecal(context)),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // ===== 通用 =====
          const VMGroupHead('通用', icon: Icons.settings_outlined),
          VMCard(
            child: Column(
              children: [
                VMListRow(
                  title: '外观',
                  subtitle: '跟随系统 / 浅色 / 深色',
                  trailing: VMSegmented(
                    options: const [
                      ('system', '跟随系统'),
                      ('light', '浅色'),
                      ('dark', '深色'),
                    ],
                    value: appearance,
                    onChanged: c.setAppearance,
                  ),
                ),
                Divider(height: 1, color: colors.hairline),
                VMSwitchRow(
                  title: '开机自启动',
                  subtitle: '后台常驻，不打扰',
                  value: c.settings['autostart'] == true,
                  onChanged: c.setAutostart,
                ),
              ],
            ),
          ),

          const SizedBox(height: 26),
          Center(
            child: TextButton(
              onPressed: () => _openAbout(context),
              child: Text('关于 VoiceMouse',
                  style: TextStyle(fontSize: 13, color: colors.text3)),
            ),
          ),
        ],
      ),
    );
  }

  String _srcHint(String src) => switch (src) {
        'system' => 'Windows 自带语音输入，固定 WIN+H',
        'macos' => 'macOS 听写，固定：连按两下 Fn',
        'ime' => '识别已安装输入法的语音快捷键',
        _ => '',
      };

  String? _imeNote(AppController c) {
    for (final o in c.imeOptions) {
      if (o.name == c.settings['ime_selection']) return o.note;
    }
    return null;
  }

  void _openDetect(BuildContext context) {
    final c = controller;
    c.openDetect();
    showVMModal(
      context,
      title: '按下你要用的鼠标键',
      dismissible: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('开启后程序会监听你的鼠标，按一下中键 / 上侧键 / 下侧键即自动识别并选上；也可以直接点下面的按钮手动选择。',
              style: TextStyle(fontSize: 13, color: colorsOf(context).text2, height: 1.5)),
          const SizedBox(height: 14),
          for (final (btn, label, hint) in const [
            ('middle', '鼠标中键', '滚轮往下按'),
            ('x1', '上侧键（侧键 1）', 'XButton1'),
            ('x2', '下侧键（侧键 2）', 'XButton2'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: VMGhostButton(
                  label: '$label  ·  $hint',
                  expand: true,
                  foreground: colorsOf(context).text,
                  onPressed: () {
                    Navigator.of(context).pop();
                    c.setButtonManual(btn);
                  },
                ),
              ),
            ),
        ],
      ),
      actions: [
        VMGhostButton(
          label: '取消',
          onPressed: () {
            c.cancelDetect();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  void _openRecal(BuildContext context) {
    final colors = colorsOf(context);
    String recMode = 'multi';
    showVMModal(
      context,
      title: '录制你的语音快捷键',
      child: StatefulBuilder(
        builder: (ctx, setState) {
          final c = controller;
          final recording = c.recordingCombo != null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '先选「单键」或「多键」，点「开始录制」后按下按键，最后点「确认」完成。按 ESC 取消。\n录制期间你的按键会被拦截（吞掉），不会真的触发桌面输入法的语音工具，放心按输入法里设好的那个快捷键。',
                  style: TextStyle(fontSize: 13, color: colors.text2, height: 1.5)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('按键数量',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600, color: colors.text)),
                  const Spacer(),
                  VMSegmented(
                    options: const [
                      ('single', '单键'),
                      ('multi', '多键'),
                    ],
                    value: recMode,
                    onChanged: (v) => setState(() => recMode = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.cardAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      recording
                          ? (c.recordingCombo?.isEmpty ?? true)
                              ? '正在监听，按下按键…'
                              : '已按下：${c.recordingCombo}'
                          : '点「开始录制」，然后按下你的快捷键…',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: recording ? colors.accent : colors.text2),
                    ),
                    if (recording) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline, size: 13, color: colors.green),
                          const SizedBox(width: 5),
                          Text('按键拦截已开启 · 你的按键不会触发输入法语音',
                              style: TextStyle(fontSize: 12, color: colors.text3)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        VMGhostButton(
          label: '取消',
          onPressed: () {
            controller.recalCancel();
            Navigator.of(context).pop();
          },
        ),
        if (controller.recordingCombo == null)
          VMFilledButton(
            label: '开始录制',
            onPressed: () => controller.recalStart(recMode),
          )
        else
          VMFilledButton(
            label: '确认',
            onPressed: () {
              controller.recalConfirm();
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }

  void _openDevices(BuildContext context) {
    final c = controller;
    final colors = colorsOf(context);
    c.refreshDevices();
    showVMModal(
      context,
      title: '检测到的鼠标设备',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final name in c.deviceNames)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(name,
                  style: TextStyle(fontSize: 13, color: colors.text2, height: 1.4)),
            ),
        ],
      ),
      actions: [
        VMGhostButton(
          label: '关闭',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  void _openAbout(BuildContext context) {
    final colors = colorsOf(context);
    showVMModal(
      context,
      title: 'VoiceMouse',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('把鼠标按键变成你的语音输入键，说话就能打字。仅适用于无专用驱动程序的鼠标；Windows 10/11 与 macOS 均可用。',
              style: TextStyle(fontSize: 13, color: colors.text2, height: 1.5)),
          const SizedBox(height: 12),
          Text('· 单击触发键即语音输入\n· 双击保留鼠标原功能\n· 全屏 / 游戏窗口自动保持原功能\n· Ctrl+Alt+F12 随时紧急停用',
              style: TextStyle(fontSize: 12.5, color: colors.text3, height: 1.7)),
          const SizedBox(height: 12),
          Text('隐私承诺：本工具完全在本地运行，不联网、不向任何服务器发送数据，也绝不会记录或保存你的任何按键内容。',
              style: TextStyle(
                  fontSize: 12.5,
                  color: colors.text3,
                  height: 1.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
      actions: [
        VMGhostButton(
          label: '关闭',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// 输入法下拉选择器
class _ImeSelector extends StatelessWidget {
  const _ImeSelector({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = colorsOf(context);
    if (c.imeOptions.isEmpty) {
      return Text('未检测到输入法，可尝试「录制校准」',
          style: TextStyle(fontSize: 12, color: colors.text3));
    }
    return DropdownButton<String>(
      value: '${c.settings['ime_selection'] ?? ''}',
      isDense: true,
      underline: const SizedBox.shrink(),
      dropdownColor: colors.card,
      style: TextStyle(fontSize: 13.5, color: colors.text),
      items: [
        for (final o in c.imeOptions)
          DropdownMenuItem(value: o.name, child: Text(o.name)),
      ],
      onChanged: (v) {
        if (v != null) c.selectIme(v);
      },
    );
  }
}