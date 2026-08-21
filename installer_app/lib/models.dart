/// 安装器全局状态。
class InstallState {
  bool licenseAgreed = false;
  String installPath = r'C:\Program Files\VoiceMouse';
  bool createShortcut = true;
  bool launchAfterInstall = true;

  void reset() {
    licenseAgreed = false;
    installPath = r'C:\Program Files\VoiceMouse';
    createShortcut = true;
    launchAfterInstall = true;
  }
}
