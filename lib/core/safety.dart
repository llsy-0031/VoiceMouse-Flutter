/// 安全场景状态（跨平台共用）。
///
/// 本工具是常驻一键触发器：除全屏/游戏、高权限程序、锁屏等必须保留原功能
/// 的场景外，其余窗口一律正常触发语音。
library;

enum SafetyState {
  safeDesktopText('SAFE_DESKTOP_TEXT'),
  unsafeNoTextTarget('UNSAFE_NO_TEXT_TARGET'),
  unsafeFullscreen('UNSAFE_FULLSCREEN'),
  unsafeElevatedTarget('UNSAFE_ELEVATED_TARGET'),
  unsafeSecureDesktop('UNSAFE_SECURE_DESKTOP'),
  unsafePermissionDenied('UNSAFE_PERMISSION_DENIED'),
  unsafeUnknown('UNSAFE_UNKNOWN');

  const SafetyState(this.id);

  final String id;

  /// 只有需要保留鼠标原功能的场景才放行（不触发语音）。
  bool get safe =>
      this != SafetyState.unsafeFullscreen &&
      this != SafetyState.unsafeElevatedTarget &&
      this != SafetyState.unsafeSecureDesktop &&
      this != SafetyState.unsafePermissionDenied &&
      this != SafetyState.unsafeUnknown;

  static SafetyState fromId(String id) =>
      SafetyState.values.firstWhere((s) => s.id == id,
          orElse: () => SafetyState.unsafeUnknown);
}

/// 用户可读的状态说明
const Map<SafetyState, String> stateHints = {
  SafetyState.safeDesktopText: '正常，可触发语音',
  SafetyState.unsafeNoTextTarget: '正常（普通窗口），可触发语音',
  SafetyState.unsafeFullscreen: '全屏/游戏窗口，自动保持鼠标原功能',
  SafetyState.unsafeElevatedTarget: '高权限程序窗口，自动保持鼠标原功能',
  SafetyState.unsafeSecureDesktop: '锁屏/安全桌面，自动保持鼠标原功能',
  SafetyState.unsafePermissionDenied: '未获得系统辅助功能权限，无法监听鼠标',
  SafetyState.unsafeUnknown: '环境暂无法确认，暂时保持鼠标原功能',
};

String stateHint(SafetyState state) =>
    stateHints[state] ?? '环境暂无法确认，暂时保持鼠标原功能';