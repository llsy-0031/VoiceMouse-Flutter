import 'dart:async';
import 'package:flutter/material.dart';
import '../installer_shell.dart';
import '../theme.dart';

class InstallingScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const InstallingScreen({super.key, required this.onFinished});

  @override
  State<InstallingScreen> createState() => _InstallingScreenState();
}

class _InstallingScreenState extends State<InstallingScreen> {
  double _progress = 0.0;
  int _currentStep = 0;
  final List<String> _logs = [];
  final List<String> _steps = [
    '创建安装目录',
    '复制主程序',
    '注册系统快捷方式',
    '解压语音模型资源',
    '配置麦克风权限',
    '完成安装',
  ];

  @override
  void initState() {
    super.initState();
    _startSimulation();
  }

  void _startSimulation() {
    Timer.periodic(const Duration(milliseconds: 120), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _progress += 0.008;
        if (_progress >= 1.0) {
          _progress = 1.0;
          timer.cancel();
          Future.delayed(const Duration(milliseconds: 400), widget.onFinished);
        }
        _currentStep = (_progress * _steps.length).floor().clamp(0, _steps.length - 1);
        if (_logs.length < _currentStep + 1) {
          _logs.add('[${DateTime.now().toIso8601String().substring(11, 19)}] ${_steps[_currentStep]}...');
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress * 100).round();
    return InstallerShell(
      currentStep: 3,
      totalSteps: 5,
      title: 'VoiceMouse 安装向导',
      primaryLabel: '下一步',
      primaryEnabled: false,
      secondaryLabel: '取消安装',
      onSecondary: () {
        // TODO: 取消安装流程
      },
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 160,
              height: 160,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 10,
                    backgroundColor: InstallerTheme.surfaceVariant,
                    valueColor: const AlwaysStoppedAnimation(InstallerTheme.primary),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$percent%',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: InstallerTheme.onSurface,
                          ),
                        ),
                        const Text(
                          '正在安装',
                          style: TextStyle(
                            fontSize: 12,
                            color: InstallerTheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: InstallerTheme.surfaceVariant,
                border: Border.all(color: InstallerTheme.outlineVariant),
                borderRadius: BorderRadius.circular(InstallerTheme.radiusLg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: InstallerTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _steps[_currentStep],
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: InstallerTheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        '剩余约 12 秒',
                        style: TextStyle(
                          fontSize: 12,
                          color: InstallerTheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 100,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: InstallerTheme.surface,
                      border: Border.all(color: InstallerTheme.outline),
                      borderRadius: BorderRadius.circular(InstallerTheme.radiusMd),
                    ),
                    child: ListView.builder(
                      reverse: true,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        return Text(
                          _logs[_logs.length - 1 - index],
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.6,
                            fontFamily: 'Consolas',
                            color: InstallerTheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

