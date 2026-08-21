import 'package:flutter/material.dart';
import '../installer_shell.dart';
import '../models.dart';
import '../theme.dart';

class LicenseScreen extends StatefulWidget {
  final InstallState state;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const LicenseScreen({
    super.key,
    required this.state,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  @override
  Widget build(BuildContext context) {
    return InstallerShell(
      currentStep: 1,
      totalSteps: 5,
      title: 'VoiceMouse 安装向导',
      primaryLabel: '下一步',
      onPrimary: widget.state.licenseAgreed ? widget.onNext : null,
      primaryEnabled: widget.state.licenseAgreed,
      secondaryLabel: '返回',
      onSecondary: widget.onBack,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '许可协议',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: InstallerTheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '在安装 VoiceMouse 之前，请仔细阅读以下用户许可协议。继续安装即表示你同意受本协议条款约束。',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: InstallerTheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: InstallerTheme.surfaceVariant,
                  border: Border.all(color: InstallerTheme.outline),
                  borderRadius: BorderRadius.circular(InstallerTheme.radiusLg),
                ),
                child: const SingleChildScrollView(
                  child: Text(
                    '''VoiceMouse 用户许可协议

1. 授权许可
本软件著作权归 VoiceMouse 开发团队所有。根据本协议条款，我们授予你一项非独占、不可转让的有限许可，允许你在单台设备上安装并使用本软件。

2. 使用限制
你不得对本软件进行反向工程、反编译、反汇编或以其他方式试图发现源代码。不得出租、出借、再许可或分发本软件。

3. 隐私说明
语音指令仅在本地识别处理，不会上传至远程服务器。我们仅在发生崩溃时收集匿名日志以改进产品。

4. 免责条款
本软件按“现状”提供，作者不对因使用或无法使用本软件而导致的任何直接、间接损失承担责任。

5. 其他
本协议受中华人民共和国法律管辖。如有争议，双方应友好协商解决。''',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.7,
                      color: InstallerTheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () {
                setState(() {
                  widget.state.licenseAgreed = !widget.state.licenseAgreed;
                });
              },
              child: Row(
                children: [
                  Checkbox(
                    value: widget.state.licenseAgreed,
                    onChanged: (v) {
                      setState(() {
                        widget.state.licenseAgreed = v ?? false;
                      });
                    },
                  ),
                  const Expanded(
                    child: Text(
                      '我已阅读并同意《VoiceMouse 用户许可协议》',
                      style: TextStyle(
                        fontSize: 14,
                        color: InstallerTheme.onSurface,
                      ),
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

