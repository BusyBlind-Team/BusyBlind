import 'package:busy_blind/core/llm/llm_client.dart';
import 'package:busy_blind/data/app_store.dart';
import 'package:busy_blind/di.dart';
import 'package:busy_blind/features/report/report_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录每次调用并按注入行为返回/抛错的假客户端。
class FakeLlmClient implements LlmClient {
  FakeLlmClient(this.behavior);

  final Future<String> Function(List<LlmMessage> messages) behavior;
  final List<List<LlmMessage>> calls = [];

  @override
  Future<String> chat(List<LlmMessage> messages, {int maxTokens = 1024}) {
    calls.add(messages);
    return behavior(messages);
  }
}

AppStore storeWithSessions() {
  final store = AppStore.inMemory();
  store
    ..addSession(
      practiceId: 'wooden_fish',
      merit: 12,
      completed: true,
      durationMs: 110000,
      metrics: {'totalMs': 110000, 'intervalMeanUs': 1000000, 'intervalStdUs': 80000},
    )
    ..addSession(
      practiceId: 'tide_breath',
      merit: 9,
      completed: true,
      durationMs: 300000,
      metrics: {'avgSync': 0.9},
    );
  return store;
}

Widget harness(AppStore store, {LlmClient? client}) => ProviderScope(
      overrides: [storeProvider.overrideWith((ref) => store)],
      child: MaterialApp(home: ReportPage(client: client)),
    );

void main() {
  testWidgets('未配 Key：显示引导卡，可在设置里填 Key 并保存', (tester) async {
    final store = storeWithSessions();
    await tester.pumpWidget(harness(store));

    expect(find.text('请一位 AI 禅友总结你的修行'), findsOneWidget);
    expect(find.text('生成修炼报告'), findsNothing); // 未配 Key 不给生成入口

    await tester.tap(find.text('去填 Key'));
    await tester.pumpAndSettle();
    expect(find.text('模型设置'), findsOneWidget);
    expect(find.textContaining('明文存在手机本地'), findsOneWidget);

    // sheet 里三个输入框：baseUrl / 模型 / API Key。
    await tester.enterText(find.byType(TextField).at(2), 'sk-test-123');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(store.llmReady, isTrue);
    expect(store.llmConfig.apiKey, 'sk-test-123');
    // 保存后回到空态（配好 Key、还没有报告）。
    expect(find.text('生成修炼报告'), findsOneWidget);
  });

  testWidgets('生成流程：提示词带 digest，报告写入 store 并渲染', (tester) async {
    final store = storeWithSessions()
      ..saveLlmConfig(const LlmConfig(
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        model: 'glm-4-flash',
        apiKey: 'sk-test',
      ));
    final fake = FakeLlmClient(
      (_) async => '【本期概览】你已修行 2 次，木鱼稳定度尚可。\n【值得肯定】坚持本身即是修行。',
    );
    await tester.pumpWidget(harness(store, client: fake));

    await tester.tap(find.text('生成修炼报告'));
    await tester.pumpAndSettle();

    // 报告渲染 + 入库。
    expect(find.textContaining('你已修行 2 次'), findsOneWidget);
    expect(find.textContaining('glm-4-flash'), findsOneWidget); // 元信息里的模型名
    expect(store.reports.length, 1);
    expect(store.reports.first['source'], 'llm');
    expect(store.reports.first['model'], 'glm-4-flash');

    // 提示词：system 设定口吻，user 内嵌聚合 JSON。
    expect(fake.calls, hasLength(1));
    expect(fake.calls.single.first.role, 'system');
    expect(fake.calls.single.first.content, contains('禅修导师'));
    expect(fake.calls.single.last.role, 'user');
    expect(fake.calls.single.last.content, contains('"overview"'));
    expect(fake.calls.single.last.content, contains('"streakDays"'));
    // 隐私红线：上传的只有聚合数字，不包含 metrics 原始键名。
    expect(fake.calls.single.last.content.contains('intervalMeanUs'), isFalse);
  });

  testWidgets('失败降级：错误信息可见，一键改生成本地报告', (tester) async {
    final store = storeWithSessions()
      ..saveLlmConfig(LlmPresets.glm.copyWith(apiKey: 'sk-test'));
    final fake = FakeLlmClient(
      (_) async => throw LlmException('额度不足或请求过于频繁，请稍后再试'),
    );
    await tester.pumpWidget(harness(store, client: fake));

    await tester.tap(find.text('生成修炼报告'));
    await tester.pumpAndSettle();

    expect(find.text('这次没能生成'), findsOneWidget);
    expect(find.textContaining('额度不足'), findsOneWidget);

    await tester.tap(find.text('生成本地报告'));
    await tester.pumpAndSettle();

    expect(find.textContaining('【本期概览】'), findsOneWidget);
    expect(find.textContaining('本地生成'), findsOneWidget);
    expect(store.reports.first['source'], 'local');
    expect(store.reports.first['model'], '本地模板');
  });

  testWidgets('不配 Key 也能从引导卡直接生成本地报告', (tester) async {
    final store = storeWithSessions();
    await tester.pumpWidget(harness(store));

    await tester.tap(find.text('本地报告'));
    await tester.pumpAndSettle();

    expect(find.textContaining('【本期概览】'), findsOneWidget);
    expect(store.reports.first['source'], 'local');
  });

  testWidgets('无修行记录点生成：提示先去修行，不发请求', (tester) async {
    final store = AppStore.inMemory()
      ..saveLlmConfig(LlmPresets.glm.copyWith(apiKey: 'sk-test'));
    final fake = FakeLlmClient((_) async => '不该出现');
    await tester.pumpWidget(harness(store, client: fake));

    await tester.tap(find.text('生成修炼报告'));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有修行记录'), findsOneWidget);
    expect(fake.calls, isEmpty);
    expect(store.reports, isEmpty);
  });
}
