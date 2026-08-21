/// 设置页：触发 / 语音 / 通用 三组 + 弹窗（自动识别、录制校准、关于）。
library;

import 'dart:io';

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

    // 快捷键来源按平台区分：Windows 不显示 macOS 项，macOS 不显示 system 项。
    // 「自定义」（原"输入法"）放在最前 —— 高频场景是录制第三方输入法或任何软件自带的语音快捷键；
    // 系统听写（Windows WIN+H / macOS Fn连按）作为后备放在后面。
    final sourceOptions = <(String, String)>[
      ('ime', '自定义'),
      if (Platform.isWindows) ('system', '系统'),
      if (Platform.isMacOS) ('macos', 'macOS'),
    ];

    // 在tap_double模式下，把当前双击判定窗口（毫秒）拼到mode副标题末尾，让用户明确当前延迟。
    final modeHintBase = modeHints[mode] ?? '';
    final modeSubtitle = mode == 'tap_double'
        ? '$modeHintBase（双击窗口 ${c.doubleClickWindowMs} ms）'
        : modeHintBase;

    return SingleChildScrollView(
      key: const ValueKey('settings'),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
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
                  // 使用按键影响范围说明：动态告知用户选的是中键还是侧键、滚轮/其他键是否受影响、双击窗口多少ms。
                  subtitle: c.buttonImpactNote,
                  trailing: const SizedBox.shrink(),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // ⚠️ 不再硬编码中键/侧键1/侧键2。
                    //    根据 backend.getMouseButtons() 动态生成实际可用的按键：
                    //    5键鼠标（左+右+中+X1+X2）→ 自动显示 3 个选项（中键/侧键1/侧键2）
                    //    6键及以上 → 继续追加侧键3/4/5。
                    VMSegmented(
                      options: [
                        for (final opt in c.availableButtonOptions) (opt.$1, opt.$2),
                      ],
                      value: '${c.settings['button'] ?? 'middle'}',
                      onChanged: c.setButton,
                    ),
                    const Spacer(),
                    VMGhostButton(
                        label: '自动识别（仅鼠标键）', onPressed: () => _openDetect(context)),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: colors.hairline),
                const SizedBox(height: 4),
                VMListRow(
                  title: '触发模式',
                  subtitle: modeSubtitle,
                  trailing: VMSegmented(
                    options: const [
                      ('tap_double', '单击语音'),
                      ('replace', '完全替换'),
                    ],
                    value: mode,
                    onChanged: c.setMode,
                  ),
                ),
                // P1-②：完全替换模式加红色警告色与警示图标，防止用户误切把原功能废了
                if (mode == 'replace') ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: colors.redSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '警告：完全替换模式下，所选按键的原始功能将彻底失效（包括中键翻页、侧键前进/后退等）。建议优先使用「单击语音」模式。',
                            style: TextStyle(
                                fontSize: 12,
                                color: colors.red,
                                height: 1.5,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                    options: sourceOptions,
                    value: src,
                    onChanged: c.setSource,
                  ),
                ),
                const SizedBox(height: 4),
                Divider(height: 1, color: colors.hairline),
                const SizedBox(height: 4),
                Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (src == 'ime') ...[
                              // 🔴 2026-08-20 产品命名修正：ime 来源的实际含义已经是"用户自定义录制任意快捷键"（通用），
                              //    不再只绑定"输入法语音"。这里的 UI 区块本来是"根据系统已安装语音软件/输入法，一键填入其常用快捷键的推荐预设"，
                              //    是【可选的辅助功能】，不是"必须选一个输入法"。把标题从"输入法"改为"推荐预设（可选）"避免误导。
                              // ⚠️ 注意：不能加 const！因为 colors.text/colors.text3 是主题运行时对象，非编译期常量！
                              Text('推荐预设（可选）',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: colors.text)),
                              const SizedBox(height: 4),
                              Text('识别到本机常用的语音软件/输入法，点一下可快速填入其常用快捷键；也可以跳过，直接点「录制校准」录制任意组合键。',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: colors.text3,
                                      height: 1.4)),
                              const SizedBox(height: 6),
                              _ImeSelector(controller: c),
                              if (_imeNote(c) != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(_imeNote(c)!,
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: colors.text3,
                                          height: 1.4)),
                                ),
                              const SizedBox(height: 10),
                            ],
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
                      // 录制中禁用"测试"按钮：录制期间键盘被拦截，注入事件也可能被吞，结果不准
                      IgnorePointer(
                        ignoring: c.recordingCombo != null,
                        child: Opacity(
                          opacity: c.recordingCombo != null ? 0.4 : 1.0,
                          child: VMGhostButton(label: '测试', onPressed: c.testShortcut),
                        ),
                      ),
                      const SizedBox(width: 8),
                      VMGhostButton(label: '录制校准', onPressed: () => _openRecal(context)),
                    ],
                  ),
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
                Divider(height: 1, color: colors.hairline),
                VMListRow(
                  title: '导出诊断包',
                  subtitle: '日志 + 系统信息 + 配置（不含密钥），导出到桌面',
                  trailing: IconButton(
                    tooltip: '导出诊断包',
                    onPressed: c.exportDiagnostics,
                    icon: Icon(Icons.download_outlined, size: 19, color: colors.accent),
                  ),
                ),
                Divider(height: 1, color: colors.hairline),
                VMListRow(
                  title: '重置设置',
                  subtitle: '恢复默认设置并清空统计',
                  trailing: IconButton(
                    tooltip: '重置设置',
                    onPressed: () => _confirmReset(context),
                    icon: Icon(Icons.restart_alt, size: 19, color: colors.red),
                  ),
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
        ),
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    showVMModal(
      context,
      title: '重置设置',
      child: const Text('将恢复默认设置并清空使用统计（不会删除诊断日志）。确定继续？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        VMFilledButton(
          label: '重置',
          onPressed: () {
            Navigator.of(context).pop();
            controller.resetSettings();
          },
        ),
      ],
    );
  }

  String _srcHint(String src) => switch (src) {
        'system' => 'Windows 自带语音输入，默认 WIN+H（可在系统设置中修改）',
        'macos' => 'macOS 听写，固定：连按两下 Fn（需在系统设置中开启听写）',
        // 'ime' 内部 key 不变，UI 统一叫「自定义」：
        // 支持录制第三方输入法的语音快捷键，也支持某软件自带的语音热键（通用任意单键/组合键）。
        'ime' => '录制任意快捷键：输入法语音键、软件自带的语音热键、或单键如 F7',
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
      title: '按下鼠标键自动识别（仅鼠标）',
      dismissible: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: colorsOf(context).amberSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '⚠️  本功能只识别鼠标按键（中键 / 侧键 1~5）\n'
              '        不能识别 Ctrl / Shift / Win+H 等键盘快捷键\n'
              '        录制键盘快捷键 → 请回到上一页点「录制校准」',
              style: TextStyle(
                  fontSize: 12.5,
                  color: colorsOf(context).amber,
                  height: 1.6,
                  fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 14),
          Text('按一下你要用来触发语音的中键或任一侧键，程序会自动识别并选上；也可以直接点下面的按钮手动选择。',
              style: TextStyle(fontSize: 13, color: colorsOf(context).text2, height: 1.5)),
          const SizedBox(height: 14),
          // ⚠️ 动态根据鼠标按键数生成可选列表：
          //    5键鼠标 → 显示 3 个（中键+侧键1+侧键2）；8键鼠标 → 显示6个（中+5个侧键）
          for (final opt in c.availableButtonOptions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: VMGhostButton(
                  label: '${opt.$3}  ·  ${opt.$4}',
                  expand: true,
                  foreground: colorsOf(context).text,
                  onPressed: () {
                    Navigator.of(context).pop();
                    c.setButtonManual(opt.$1);
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
    // 🔴 2026-08-20 修复：打开弹窗时，手动输入框默认填上【当前实际快捷键】——
    //    除了 macOS 的"FN 连按两下"（存储值='FN'，不能字符串手动模拟），其他所有值一律显示，
    //    哪怕就是 WIN+H，也要给用户看到当前配置，不再因为等于 WIN+H 就空着。
    final scRaw = controller.settings['shortcut'];
    final defaultText = (scRaw is String && scRaw.isNotEmpty && scRaw != 'FN') ? scRaw : '';
    final manualCtrl = TextEditingController(text: defaultText);
    showVMModal(
      context,
      title: '录制你的语音快捷键',
      dismissible: false, // ← 禁止点弹窗外部关闭：防止误关后键盘钩子还在，按键被吞
      child: StatefulBuilder(
        builder: (ctx, setState) {
          final c = controller;
          return ListenableBuilder(
            listenable: c,
            builder: (context, _) {
              final isListening = c.isRecordingListening;
              final hasResult = c.recordingCombo != null && c.recordingCombo!.isNotEmpty;
              return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  isListening
                      ? '现在按键会被拦截（不触发输入法）。按完你要的快捷键后，点右下角「录制完成」停止监听；最后点「确认」保存。按 ESC 取消本次录制。'
                      : '先选「单键」或「多键」，点「开始录制」后按下你的快捷键，最后点「确认」保存。按 ESC 取消。',
                  style: TextStyle(fontSize: 13, color: colors.text2, height: 1.5)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('按键数量',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600, color: colors.text)),
                  const Spacer(),
                  // 录制中禁用单键/多键切换，避免用户误切换以为生效
                  IgnorePointer(
                    ignoring: isListening,
                    child: Opacity(
                      opacity: isListening ? 0.5 : 1.0,
                      child: VMSegmented(
                        options: const [
                          ('single', '单键'),
                          ('multi', '多键'),
                        ],
                        value: recMode,
                        onChanged: (v) => setState(() => recMode = v),
                      ),
                    ),
                  ),
                ],
              ),
              // P1-④：录制中灰显区追加小字提示，消除"为什么点不动"的失灵感
              if (isListening) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 12, color: colors.amber),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '※ 录制进行中，请先点「录制完成」再切换',
                        style: TextStyle(fontSize: 11.5, color: colors.amber, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ],
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
                      isListening
                          ? hasResult
                              ? '已按下：${c.recordingCombo}（想重新按就再按一次新组合）'
                              : '正在监听，按下你要用来触发语音的键盘快捷键…'
                          : hasResult
                              ? '录制完成！已识别：${c.recordingCombo} · 点「确认」保存，或点「开始录制」重新来。'
                              : '点「开始录制」，然后按下你的键盘快捷键…',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isListening
                              ? colors.accent
                              : hasResult
                                  ? colors.green
                                  : colors.text2),
                    ),
                    if (isListening) ...[
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
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text('或手动输入快捷键',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: colors.text)),
              const SizedBox(height: 4),
              Text('格式如 WIN+H、CTRL+SHIFT+V、F8；不区分大小写。',
                  style: TextStyle(fontSize: 12.5, color: colors.text3)),
              const SizedBox(height: 8),
              // 录制中禁用手动输入区，防止混乱
              IgnorePointer(
                ignoring: isListening,
                child: Opacity(
                  opacity: isListening ? 0.5 : 1.0,
                  child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: manualCtrl,
                      style: TextStyle(fontSize: 14, color: colors.text),
                      decoration: InputDecoration(
                        hintText: isListening ? '录制中禁用，请先点「录制完成」' : '例如 WIN+H',
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
                  VMFilledButton(
                    label: '应用',
                    onPressed: isListening
                        ? () {}
                        : () {
                      final text = manualCtrl.text.trim();
                      if (text.isEmpty) {
                        c.recalCancel();
                        Navigator.of(context).pop();
                        return;
                      }
                      try {
                        c.applyManualShortcut(text);
                        Navigator.of(context).pop();
                      } catch (e) {
                        controller.showAlert('快捷键无效', '$e');
                      }
                    },
                  ),
                ],
              ),
                ),
              ),
              // P1-④：手动输入区同样追加录制中提示
              if (isListening) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 12, color: colors.amber),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '※ 录制进行中，请先点「录制完成」再手动输入',
                        style: TextStyle(fontSize: 11.5, color: colors.amber, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ],
              // ==================== 按钮栏（移到这里！放在ListenableBuilder内部，才能随状态实时刷新）====================
              const SizedBox(height: 22),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  VMGhostButton(
                    label: '取消',
                    onPressed: () {
                      c.recalCancel(); // 取消时立刻卸键盘钩子（防吞）
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(width: 10),
                  // 🔴 三态按钮：现在在ListenableBuilder里面了→状态变化时实时重绘！
                  () {
                    if (isListening) {
                      return VMFilledButton(
                        label: '录制完成',
                        onPressed: () {
                          c.recalStopListening(); // 卸钩子，但保留结果，不退出弹窗
                        },
                      );
                    }
                    if (hasResult) {
                      return VMFilledButton(
                        label: '确认',
                        onPressed: () {
                          c.recalConfirm();
                          Navigator.of(context).pop();
                        },
                      );
                    }
                    // idle 态：开始录制
                    return VMFilledButton(
                      label: '开始录制',
                      onPressed: () => c.recalStart(recMode),
                    );
                  }(),
                ],
              ),
            ],
              );
            },
          );
        },
      ),
      // ⚠️ actions留空！所有按钮全部移到child的Column末尾，保证随状态实时刷新
      actions: const [],
    ).whenComplete(() {
      // 🔴 兜底！无论弹窗如何关闭（点取消/点确认/ESC），
      //    都确保键盘钩子被卸载，不会出现"关了弹窗还在吞键盘"的严重bug。
      controller.recalCancel();
    });
  }

  void _openDevices(BuildContext context) {
    final c = controller;
    final colors = colorsOf(context);
    c.refreshDevices();
    final infos = c.backend.enumerateMice();
    final totalBtns = (() {
      try { return c.backend.getMouseButtons(); } catch (_) { return 3; }
    })();
    final opts = c.availableButtonOptions;
    showVMModal(
      context,
      title: '检测到的鼠标设备',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (infos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('未从系统输入设备列表中发现鼠标（远程桌面环境属正常限制）',
                  style: TextStyle(fontSize: 13, color: colors.text2, height: 1.4)),
            )
          else
            for (final m in infos)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name,
                        style: TextStyle(fontSize: 13, color: colors.text, height: 1.4)),
                    const SizedBox(height: 2),
                    Text('    · 物理按键数：${m.buttons}',
                        style: TextStyle(fontSize: 12, color: colors.text2, height: 1.4)),
                  ],
                ),
              ),
          const SizedBox(height: 4),
          Divider(height: 1, color: colors.hairline),
          const SizedBox(height: 10),
          Text('系统识别：当前鼠标共计 $totalBtns 个按键（含左右键）',
              style: TextStyle(
                  fontSize: 13,
                  color: colors.text,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final opt in opts)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: colors.cardAlt,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(opt.$3,
                      style: TextStyle(fontSize: 12, color: colors.text2)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text('* 侧键3+ 需要鼠标厂商驱动支持标准 XButton 映射；若无效请在鼠标驱动软件中把该侧键改映射为「XButton」。',
              style: TextStyle(fontSize: 11, color: colors.text3, height: 1.4)),
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
    final mode = '${controller.settings['mode'] ?? 'tap_double'}';
    final macLimit = Platform.isMacOS
        ? '\n· macOS 当前版本暂无全屏/高权限窗口检测（建议用 Ctrl+Alt+F12 紧急停用）'
        : '';
    final clickLine = mode == 'tap_double'
        ? '单击触发键即语音输入\n· 双击保留鼠标原功能'
        : '按下触发键立即触发语音\n· 鼠标原功能不再生效';
    showVMModal(
      context,
      title: 'VoiceMouse',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // P1-③：关于页醒目说明紧急停用快捷键 Ctrl+Alt+F12（救命快捷键写最上面大字号琥珀色）
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: colors.amberSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.emergency_outlined, size: 18, color: colors.amber),
                    const SizedBox(width: 8),
                    Text('紧急停用快捷键',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.amber)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Ctrl + Alt + F12',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: colors.amber,
                        letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text('鼠标异常、想临时恢复原功能时，随时按这组快捷键即可紧急停用',
                    style: TextStyle(fontSize: 12, color: colors.amber, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text('把鼠标按键变成你的语音输入键，说话就能打字。仅适用于无专用驱动程序的鼠标；Windows 10/11 与 macOS 均可用。',
              style: TextStyle(fontSize: 13, color: colors.text2, height: 1.5)),
          const SizedBox(height: 12),
          Text('· $clickLine\n· 全屏 / 游戏窗口自动保持原功能（Windows）$macLimit\n· Ctrl+Alt+F12 随时紧急停用',
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