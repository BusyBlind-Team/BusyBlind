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
      title: '忙僧 busy·blind',
      theme: AppTheme.data,
      // Bug#8（第二轮）：全局清掉黄色下划线。
      //
      // 根因不在我们代码里：WidgetsApp 用内部的 _errorTextStyle（红色等宽
      // 48px + **纯黄双下划线**）作为环境 DefaultTextStyle 包住整个 app，
      // 位置在 Theme 之上。凡是没有 Material/Scaffold 祖先的裸 Text
      //（修行页覆盖层里的「退出」「♪ 曲名」就是）都会继承它，而我们传的
      // TextStyle 只设了颜色/字号、没写 decoration，下划线就漏了出来。
      // 这里把环境默认样式换回主题正文，并显式 decoration: none。
      builder: (context, child) => DefaultTextStyle(
        style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(decoration: TextDecoration.none),
        child: child ?? const SizedBox.shrink(),
      ),
      home: home,
      debugShowCheckedModeBanner: false,
    );
  }
}
