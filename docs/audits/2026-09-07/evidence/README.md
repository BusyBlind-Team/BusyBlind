# Fuckthon 审计证据

基准提交：91698f453605711565c8a4a19f723ace82d24397。
环境：Flutter 3.47.2 / Dart 3.13.2，macOS。

- baseline-test.log：原有 45 个测试全部通过；包含试听点击未命中警告。
- baseline-analyze.log：原有 lib/test 的 Dart 静态分析结果，无 issue。
- audit_reproduction_test.dart.txt：13 个审计复现用例。
- reproduction-test.log：12 个用例确认缺陷行为，R7 因抽签回调在组件卸载后读取 ref 产生未处理异常而失败。

复现方式：在上述提交的独立副本中，将 audit_reproduction_test.dart.txt 复制到 test/ 下并重命名为 audit_reproduction_test.dart；该文件复用仓库现有 test/helpers/fake_clock.dart 与 test/practices_test.dart 的辅助方法。

```sh
cp docs/audits/2026-09-07/evidence/audit_reproduction_test.dart.txt test/audit_reproduction_test.dart
flutter pub get
flutter test test/audit_reproduction_test.dart --reporter expanded
```

这些是证据用例，大部分断言的是已观察到的错误行为；通过不表示业务正确。R7 预期会因当前产品缺陷而返回非零退出状态。修复时应把断言改为正确行为，并处理 R7 的未处理异常。

本次实际使用已安装 SDK 的 flutter_tools.snapshot 和 --no-pub 运行测试，复用已有 package_config/package_graph，不重新解析或升级依赖。静态分析在加入审计用例之前执行。本机审计未修改原仓库，也未向 GitHub 提交报告或代码。
