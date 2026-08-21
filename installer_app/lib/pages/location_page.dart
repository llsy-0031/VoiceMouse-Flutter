import 'package:flutter/material.dart';
import '../installer_shell.dart';
import '../models.dart';
import '../theme.dart';

class LocationScreen extends StatefulWidget {
  final InstallState state;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const LocationScreen({
    super.key,
    required this.state,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.installPath);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InstallerShell(
      currentStep: 2,
      totalSteps: 5,
      title: 'VoiceMouse 安装向导',
      primaryLabel: '开始安装',
      onPrimary: widget.onNext,
      secondaryLabel: '返回',
      onSecondary: widget.onBack,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择安装位置',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: InstallerTheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '选择 VoiceMouse 的安装文件夹。建议保留默认路径，以确保后续更新和语音模型资源正常加载。',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: InstallerTheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: InstallerTheme.surfaceVariant,
                border: Border.all(color: InstallerTheme.outlineVariant),
                borderRadius: BorderRadius.circular(InstallerTheme.radiusLg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '安装路径',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: InstallerTheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          onChanged: (v) => widget.state.installPath = v,
                          decoration: const InputDecoration(
                            hintText: 'C:\\Program Files\\VoiceMouse',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          // TODO: 接入 file_selector 实现真实浏览
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('浏览功能待接入 file_selector')),
                          );
                        },
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('浏览'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoCard(
                          icon: Icons.download,
                          label: '所需空间',
                          value: '约 142 MB',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _InfoCard(
                          icon: Icons.storage,
                          label: 'C 盘可用空间',
                          value: '128.6 GB',
                        ),
                      ),
                    ],
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

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: InstallerTheme.surface,
        border: Border.all(color: InstallerTheme.outlineVariant),
        borderRadius: BorderRadius.circular(InstallerTheme.radiusMd),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: InstallerTheme.primary95,
              borderRadius: BorderRadius.circular(InstallerTheme.radiusMd),
            ),
            child: Icon(icon, size: 18, color: InstallerTheme.primary),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: InstallerTheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: InstallerTheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

