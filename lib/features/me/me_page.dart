import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_store.dart';
import '../../di.dart';
import '../../theme.dart';
import '../report/report_page.dart';
import '../tutorial/calibration_page.dart';

/// 我（右页）：v0.1 占位页。
/// 策划案明确暂不开发；先放数据概览、校准入口与调试工具。
class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          if (store.persistenceError != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x22C97B6B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                store.persistenceError!,
                style: const TextStyle(color: AppTheme.inkDim, fontSize: 12, height: 1.5),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0x10FFFFFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('无名忙僧', style: TextStyle(color: AppTheme.ink, fontSize: 18)),
                const SizedBox(height: 6),
                Text(
                  '累计修行 ${store.sessionCount} 次 · 修为 ${store.merit}',
                  style: const TextStyle(color: AppTheme.inkDim, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.graphic_eq, color: AppTheme.gold),
            title: const Text('时机校准', style: TextStyle(color: AppTheme.ink)),
            subtitle: Text(
              '判定线 5 下，取偏差中位数（当前 L_user = ${store.lUserUs} µs）',
              style: const TextStyle(color: AppTheme.inkFaint, fontSize: 12),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CalibrationPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome, color: AppTheme.gold),
            title: const Text('修炼报告', style: TextStyle(color: AppTheme.ink)),
            subtitle: Text(
              _reportSubtitle(store),
              style: const TextStyle(color: AppTheme.inkFaint, fontSize: 12),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ReportPage()),
            ),
          ),
          const Divider(color: Color(0x14E8DFC8)),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppTheme.inkDim),
            title: const Text('清空本地数据（调试）', style: TextStyle(color: AppTheme.inkDim)),
            onTap: () => _confirmReset(context, ref),
          ),
          const SizedBox(height: 16),
          const Text(
            '个人页按策划案暂不开发，此页仅占位。\n'
            '数据本地优先：断网时除加好友外全部功能可用。',
            style: TextStyle(color: AppTheme.inkFaint, fontSize: 12, height: 1.7),
          ),
        ],
      ),
    );
  }

  /// 报告入口副标题：有报告显示上次时间，否则一句话说明。
  String _reportSubtitle(AppStore store) {
    if (store.reports.isEmpty) return '汇总修行统计，请 AI 写一份带禅意的总结';
    final t = DateTime.tryParse(store.reports.first['generatedAt'] as String? ?? '');
    if (t == null) return '汇总修行统计，请 AI 写一份带禅意的总结';
    return '上次报告：${t.month}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  void _confirmReset(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: const Text('清空本地数据', style: TextStyle(color: AppTheme.ink)),
        content: const Text(
          '修为、花瓣、成就与修行记录将全部清空，且无法恢复。确定吗？',
          style: TextStyle(color: AppTheme.inkDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref.read(storeProvider).reset();
              Navigator.of(ctx).pop();
            },
            child: const Text('清空', style: TextStyle(color: Color(0xFFC97B6B))),
          ),
        ],
      ),
    );
  }
}
