import 'package:flutter/material.dart';

import 'shell/app_shell.dart';
import 'theme.dart';

class BusyBlindApp extends StatelessWidget {
  const BusyBlindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '盲僧 busy·blind',
      theme: AppTheme.data,
      home: const AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}
