import 'package:flutter/material.dart';

import 'shell/app_shell.dart';
import 'theme.dart';

class BusyBlindApp extends StatelessWidget {
  const BusyBlindApp({super.key, this.home = const AppShell()});

  /// 首屏由 main 依 tutorialDone 决定（教程页或主壳层）。
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '盲僧 busy·blind',
      theme: AppTheme.data,
      home: home,
      debugShowCheckedModeBanner: false,
    );
  }
}
