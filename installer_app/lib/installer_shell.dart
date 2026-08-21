import 'package:flutter/material.dart';
import 'theme.dart';

class InstallerShell extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final String title;
  final Widget body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool primaryEnabled;
  final bool isFinal;

  const InstallerShell({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.title,
    required this.body,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.primaryEnabled = true,
    this.isFinal = false,
  });

  static const List<String> _stepNames = ['欢迎', '协议', '位置', '安装', '完成'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: InstallerTheme.background,
      body: Center(
        child: Container(
          width: InstallerTheme.installerWidth,
          height: InstallerTheme.installerHeight,
          decoration: BoxDecoration(
            color: InstallerTheme.surface,
            borderRadius: BorderRadius.circular(InstallerTheme.radiusXl),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildTitleBar(),
              _buildStepper(),
              Expanded(child: body),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: InstallerTheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: InstallerTheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: InstallerTheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(totalSteps * 2 - 1, (index) {
          if (index.isOdd) {
            return Container(
              width: 22,
              height: 1,
              color: InstallerTheme.outline,
            );
          }
          final stepIndex = index ~/ 2;
          final isActive = stepIndex == currentStep;
          final isCompleted = stepIndex < currentStep;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isActive
                        ? InstallerTheme.primary
                        : isCompleted
                            ? InstallerTheme.successContainer
                            : InstallerTheme.surfaceVariant,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${stepIndex + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? InstallerTheme.onPrimary
                            : isCompleted
                                ? InstallerTheme.success
                                : InstallerTheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _stepNames[stepIndex],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? InstallerTheme.primary
                        : isCompleted
                            ? InstallerTheme.success
                            : InstallerTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: InstallerTheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          if (secondaryLabel != null)
            TextButton(
              onPressed: onSecondary,
              child: Text(secondaryLabel!),
            )
          else
            const Spacer(),
          const Spacer(),
          if (primaryLabel != null)
            FilledButton(
              onPressed: primaryEnabled ? onPrimary : null,
              child: Text(primaryLabel!),
            ),
        ],
      ),
    );
  }
}
