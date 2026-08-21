import 'package:flutter/material.dart';
import '../installer_shell.dart';
import '../theme.dart';

class WelcomeScreen extends StatelessWidget {
  final VoidCallback onNext;

  const WelcomeScreen({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return InstallerShell(
      currentStep: 0,
      totalSteps: 5,
      title: 'VoiceMouse 安装向导',
      primaryLabel: '开始安装',
      onPrimary: onNext,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(InstallerTheme.radiusXl),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [InstallerTheme.primary, Color(0xFF3B8DFF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: InstallerTheme.primary.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.mic,
                size: 64,
                color: InstallerTheme.onPrimary,
              ),
            ),
            const SizedBox(height: 36),
            const Text(
              '欢迎使用 VoiceMouse',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: InstallerTheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '语音操控，解放双手。VoiceMouse 让你通过语音指令快速控制鼠标、执行点击与拖拽，为无障碍操作和效率提升而生。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: InstallerTheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: InstallerTheme.primary95,
                borderRadius: BorderRadius.circular(InstallerTheme.radiusFull),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune,
                    size: 14,
                    color: InstallerTheme.primary,
                  ),
                  SizedBox(width: 8),
                  Text(
                    '版本 1.0.3 · Windows / macOS 安装包',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: InstallerTheme.primary,
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

