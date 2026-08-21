import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../installer_shell.dart';
import '../models.dart';
import '../theme.dart';

class FinishScreen extends StatefulWidget {
  final InstallState state;

  const FinishScreen({super.key, required this.state});

  @override
  State<FinishScreen> createState() => _FinishScreenState();
}

class _FinishScreenState extends State<FinishScreen> {
  @override
  Widget build(BuildContext context) {
    return InstallerShell(
      currentStep: 4,
      totalSteps: 5,
      title: 'VoiceMouse 安装向导',
      primaryLabel: '完成',
      onPrimary: () async {
        // TODO: 若选中 launchAfterInstall 则启动 VoiceMouse
        await windowManager.close();
      },
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                color: InstallerTheme.successContainer,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check,
                size: 52,
                color: InstallerTheme.success,
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              '安装完成',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: InstallerTheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'VoiceMouse 已成功安装到你的电脑。首次使用前，请确保麦克风已连接并允许应用访问音频设备。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: InstallerTheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: InstallerTheme.surfaceVariant,
                border: Border.all(color: InstallerTheme.outlineVariant),
                borderRadius: BorderRadius.circular(InstallerTheme.radiusLg),
              ),
              child: InkWell(
                onTap: () {
                  setState(() {
                    widget.state.launchAfterInstall = !widget.state.launchAfterInstall;
                  });
                },
                child: Row(
                  children: [
                    Checkbox(
                      value: widget.state.launchAfterInstall,
                      onChanged: (v) {
                        setState(() {
                          widget.state.launchAfterInstall = v ?? false;
                        });
                      },
                    ),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '立即运行 VoiceMouse',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: InstallerTheme.onSurface,
                            ),
                          ),
                          Text(
                            '关闭安装向导后自动启动应用',
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
            ),
          ],
        ),
      ),
    );
  }
}

