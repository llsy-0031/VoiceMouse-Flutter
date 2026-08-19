/// 应用外壳：顶栏 + 分段导航 + 页面切换 + Toast + 全局弹窗。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import 'run_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'widgets.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String _page = 'run';
  Timer? _toastHide;
  int _lastToastSeq = 0;
  bool _alertShown = false;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (c.lastAlertTitle != null && !_alertShown) {
      _alertShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final t = c.lastAlertTitle!;
        final m = c.lastAlertMessage ?? '';
        c.clearAlert();
        showVMModal(context, title: t, child: Text(m)).then((_) {
          _alertShown = false;
        });
      });
    }
    if (c.toastSeq != _lastToastSeq) {
      _lastToastSeq = c.toastSeq;
      _toastHide?.cancel();
      _toastHide = Timer(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() {});
      });
      setState(() {});
    }
  }

  @override
  void dispose() {
    c.removeListener(_onControllerChanged);
    _toastHide?.cancel();
    super.dispose();
  }

  void _toggleTheme() {
    final cur = c.settings['appearance'] ?? 'system';
    final next = cur == 'dark' ? 'light' : 'dark';
    c.setAppearance(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Stack(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _page == 'run'
                        ? RunPage(key: const ValueKey('run'), controller: c)
                        : SettingsPage(key: const ValueKey('settings'), controller: c),
                  ),
                  if (c.toastText != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 18,
                      child: Center(child: _buildToast(context)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = colorsOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(bottom: BorderSide(color: colors.hairline, width: 0.5)),
      ),
      child: Row(
        children: [
          // Logo
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.mouse, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 9),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('VoiceMouse',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: colors.text)),
                  Text('把鼠标变成语音输入键',
                      style: TextStyle(fontSize: 10.5, color: colors.text3)),
                ],
              ),
            ],
          ),
          const Spacer(),
          VMSegmented(
            options: const [('run', '运行'), ('settings', '设置')],
            value: _page,
            onChanged: (v) => setState(() => _page = v),
          ),
          const Spacer(),
          IconButton(
            onPressed: _toggleTheme,
            tooltip: '切换深浅色',
            icon: Icon(
              (Theme.of(context).brightness == Brightness.dark)
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              size: 19,
              color: colors.text2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToast(BuildContext context) {
    final colors = colorsOf(context);
    final text = c.toastText ?? '';
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.text,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: colors.bg, fontWeight: FontWeight.w500)),
    );
  }
}