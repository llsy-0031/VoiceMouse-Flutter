import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'models.dart';
import 'pages/finish_page.dart';
import 'pages/installing_page.dart';
import 'pages/license_page.dart';
import 'pages/location_page.dart';
import 'pages/welcome_page.dart';
import 'theme.dart';

final _installState = InstallState();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    title: 'VoiceMouse 安装向导',
    size: Size(InstallerTheme.installerWidth, InstallerTheme.installerHeight),
    minimumSize: Size(InstallerTheme.installerWidth, InstallerTheme.installerHeight),
    maximumSize: Size(InstallerTheme.installerWidth, InstallerTheme.installerHeight),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(
    windowOptions,
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  runApp(const VoiceMouseInstallerApp());
}

class VoiceMouseInstallerApp extends StatefulWidget {
  const VoiceMouseInstallerApp({super.key});

  @override
  State<VoiceMouseInstallerApp> createState() => _VoiceMouseInstallerAppState();
}

class _VoiceMouseInstallerAppState extends State<VoiceMouseInstallerApp> {
  int _pageIndex = 0;

  void _next() => setState(() => _pageIndex++);
  void _back() => setState(() => _pageIndex--);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoiceMouse 安装向导',
      debugShowCheckedModeBanner: false,
      theme: InstallerTheme.theme,
      home: IndexedStack(
        index: _pageIndex,
        children: [
          WelcomeScreen(onNext: _next),
          LicenseScreen(
            state: _installState,
            onNext: _next,
            onBack: _back,
          ),
          LocationScreen(
            state: _installState,
            onNext: _next,
            onBack: _back,
          ),
          InstallingScreen(onFinished: _next),
          FinishScreen(state: _installState),
        ],
      ),
    );
  }
}

