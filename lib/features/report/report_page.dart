import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/llm_client.dart';
import '../../di.dart';
import '../../domain/practice_stats.dart';
import '../../theme.dart';

/// 修炼报告页：把修行统计交给 LLM，换一份带禅意的总结。
///
/// 手动生成（无后台任务）；状态全部留在本页（与 PracticeHost 同模式，
/// 不做跨页响应式）。未配 Key 或请求失败时可一键降级为本地模板报告。
class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key, this.client});

  /// 测试注入假客户端；生产留空则每次生成时用最新配置建 HTTP 客户端。
  final LlmClient? client;

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  bool _generating = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final store = ref.read(storeProvider);
    final latest = store.reports.isNotEmpty ? store.reports.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('修炼报告'),
        actions: [
          IconButton(
            tooltip: '模型设置',
            icon: const Icon(Icons.tune),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          if (latest != null) ...[
            _ReportCard(report: latest),
            const SizedBox(height: 16),
          ],
          if (_generating)
            const _GeneratingCard()
          else if (_error != null)
            _ErrorCard(
              message: _error!,
              onRetry: _generate,
              onFallback: _generateLocal,
            )
          else if (latest == null && !store.llmReady)
            _GuideCard(
              onSettings: _openSettings,
              onFallback: _generateLocal,
            )
          else if (latest == null)
            _EmptyCard(onGenerate: _generate, onFallback: _generateLocal)
          else ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _generate,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('重新生成'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _generateLocal,
              child: const Text('不用 AI，生成本地报告', style: TextStyle(color: AppTheme.inkFaint)),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            '隐私：生成报告时只上传修行次数、时长、修为等聚合统计数字；'
            '签文文本与逐次记录明细不出本机。报告生成后缓存本地，重复打开不重复请求。',
            style: TextStyle(color: AppTheme.inkFaint, fontSize: 12, height: 1.7),
          ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    final store = ref.read(storeProvider);
    if (store.sessions.isEmpty) {
      _toast('还没有修行记录，先去修一行再来。');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final digest = buildPracticeDigest(store);
      final client = widget.client ?? HttpLlmClient(config: store.llmConfig);
      final text = await client.chat([
        const LlmMessage(role: 'system', content: kReportSystemPrompt),
        LlmMessage(role: 'user', content: buildReportUserPrompt(digest)),
      ]);
      store.addReport({
        'generatedAt': DateTime.now().toIso8601String(),
        'source': 'llm',
        'model': store.llmConfig.model,
        'text': text,
      });
    } on LlmException catch (e) {
      // 生成期间可能已离开页面：先查 mounted 再 setState（复审 P2-5）。
      if (mounted) setState(() => _error = e.message);
    } on Exception catch (e) {
      // 非预期异常也给出出路，不吞进异步黑洞（第 12 轮自检）。
      debugPrint('report generate failed: $e');
      if (mounted) {
        setState(() => _error = '生成失败，请重试，或改用本地报告。');
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _generateLocal() {
    final store = ref.read(storeProvider);
    if (store.sessions.isEmpty) {
      _toast('还没有修行记录，先去修一行再来。');
      return;
    }
    store.addReport({
      'generatedAt': DateTime.now().toIso8601String(),
      'source': 'local',
      'model': '本地模板',
      'text': buildLocalReport(buildPracticeDigest(store)),
    });
    setState(() => _error = null);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSettings() async {
    final store = ref.read(storeProvider);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16161E),
      // 弹层自建自毁输入控制器（随关闭动画安全释放），页面只收"是否保存"。
      builder: (ctx) => _LlmSettingsSheet(
        initial: store.llmConfig,
        storedKey: store.keyForBaseUrl,
        onSave: (config) {
          store.saveLlmConfig(config);
          Navigator.of(ctx).pop(true);
        },
      ),
    );
    if (saved == true && mounted) setState(() {});
  }
}

/// 报告正文卡片：元信息 + 四段正文。
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final Map<String, Object?> report;

  @override
  Widget build(BuildContext context) {
    final generatedAt = DateTime.tryParse(report['generatedAt'] as String? ?? '');
    final time = generatedAt == null
        ? ''
        : '${generatedAt.month}-${generatedAt.day.toString().padLeft(2, '0')} '
            '${generatedAt.hour.toString().padLeft(2, '0')}:${generatedAt.minute.toString().padLeft(2, '0')}';
    final source = report['source'] == 'llm' ? 'AI 生成' : '本地生成';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x10FFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${report['model']} · $time · $source',
            style: const TextStyle(color: AppTheme.inkFaint, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SelectableText(
            (report['text'] as String? ?? '').trim(),
            style: const TextStyle(color: AppTheme.ink, fontSize: 15, height: 1.9),
          ),
        ],
      ),
    );
  }
}

class _GeneratingCard extends StatelessWidget {
  const _GeneratingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0x10FFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Column(
          children: [
            CircularProgressIndicator(color: AppTheme.gold),
            SizedBox(height: 16),
            Text(
              '正在请山外的朋友读一读你的修行……',
              style: TextStyle(color: AppTheme.inkDim, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.onRetry,
    required this.onFallback,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onFallback;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x10FFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('这次没能生成', style: TextStyle(color: AppTheme.ink, fontSize: 15)),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: AppTheme.inkDim, fontSize: 13, height: 1.6)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: onFallback,
                  child: const Text('生成本地报告', style: TextStyle(color: AppTheme.gold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 未配 Key 的引导卡：可去设置，也可直接生成本地报告（断网可用）。
class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.onSettings, required this.onFallback});

  final VoidCallback onSettings;
  final VoidCallback onFallback;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x10FFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('请一位 AI 禅友总结你的修行', style: TextStyle(color: AppTheme.ink, fontSize: 15)),
          const SizedBox(height: 8),
          const Text(
            '填一个 OpenAI 兼容接口的 API Key（默认智谱 GLM，也可换 DeepSeek / OpenAI 或自定义），'
            '就能把修行统计交给大模型，生成一份带禅意的修炼报告。\n'
            '没有 Key 也可以先看本地模板版的统计结论。',
            style: TextStyle(color: AppTheme.inkDim, fontSize: 13, height: 1.7),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSettings,
                  icon: const Icon(Icons.tune),
                  label: const Text('去填 Key'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: onFallback,
                  child: const Text('本地报告', style: TextStyle(color: AppTheme.gold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onGenerate, required this.onFallback});

  final VoidCallback onGenerate;
  final VoidCallback onFallback;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x10FFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('把修行的脚印串成一句话', style: TextStyle(color: AppTheme.ink, fontSize: 15)),
          const SizedBox(height: 8),
          const Text(
            '汇总你全部修行的次数、时长与各项指标，请大模型写一份四段式的修炼报告：'
            '本期概览、值得肯定、可精进处、下期建议。',
            style: TextStyle(color: AppTheme.inkDim, fontSize: 13, height: 1.7),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onGenerate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('生成修炼报告'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onFallback,
            child: const Text('不用 AI，生成本地报告', style: TextStyle(color: AppTheme.inkFaint)),
          ),
        ],
      ),
    );
  }
}

/// 模型设置底部弹层：预设 + baseUrl / 模型 / Key 表单。
/// 自建自毁输入控制器，键盘弹起时自动上移（isScrollControlled + viewInsets）。
class _LlmSettingsSheet extends StatefulWidget {
  const _LlmSettingsSheet({
    required this.initial,
    required this.storedKey,
    required this.onSave,
  });

  final LlmConfig initial;

  /// 某服务商（baseUrl）此前保存过的 Key；切换服务商时据此换 Key。
  final String? Function(String baseUrl) storedKey;

  final void Function(LlmConfig config) onSave;

  @override
  State<_LlmSettingsSheet> createState() => _LlmSettingsSheetState();
}

class _LlmSettingsSheetState extends State<_LlmSettingsSheet> {
  late final TextEditingController _baseUrl =
      TextEditingController(text: widget.initial.baseUrl);
  late final TextEditingController _model =
      TextEditingController(text: widget.initial.model);
  late final TextEditingController _apiKey =
      TextEditingController(text: widget.initial.apiKey);
  late String _presetId;

  /// 当前 Key 输入框内容所属的 baseUrl——baseUrl 变化时据此换 Key，
  /// 不把上一家服务商的密钥发给下一家（复审 P1-2）。
  late String _keyOwner;

  static const _presets = [
    ('glm', '智谱 GLM', LlmPresets.glm),
    ('deepseek', 'DeepSeek', LlmPresets.deepseek),
    ('openai', 'OpenAI', LlmPresets.openai),
    ('custom', '自定义', null),
  ];

  @override
  void initState() {
    super.initState();
    _presetId = 'custom';
    for (final (id, _, preset) in _presets) {
      if (preset != null &&
          preset.baseUrl == _baseUrl.text &&
          preset.model == _model.text) {
        _presetId = id;
        break;
      }
    }
    _keyOwner = widget.initial.baseUrl;
    _baseUrl.addListener(_swapKeyWithBaseUrl);
  }

  void _swapKeyWithBaseUrl() {
    final baseUrl = _baseUrl.text.trim();
    if (baseUrl == _keyOwner) return;
    _keyOwner = baseUrl;
    final stored = widget.storedKey(baseUrl);
    final next = stored ?? '';
    if (_apiKey.text != next) {
      _apiKey.text = next;
    }
  }

  @override
  void dispose() {
    _baseUrl.removeListener(_swapKeyWithBaseUrl);
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('模型设置', style: TextStyle(color: AppTheme.ink, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'OpenAI 兼容接口。API Key 明文存在手机本地（busy_blind.json），'
              '仅发送给所选模型服务商。',
              style: TextStyle(color: AppTheme.inkFaint, fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final (id, label, preset) in _presets)
                  ChoiceChip(
                    label: Text(label),
                    selected: _presetId == id,
                    onSelected: (_) => setState(() {
                      _presetId = id;
                      if (preset != null) {
                        _baseUrl.text = preset.baseUrl;
                        _model.text = preset.model;
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _baseUrl,
              enabled: _presetId == 'custom',
              style: const TextStyle(color: AppTheme.ink, fontSize: 14),
              decoration: const InputDecoration(labelText: '接口地址 baseUrl'),
            ),
            TextField(
              controller: _model,
              enabled: _presetId == 'custom',
              style: const TextStyle(color: AppTheme.ink, fontSize: 14),
              decoration: const InputDecoration(labelText: '模型'),
            ),
            TextField(
              controller: _apiKey,
              obscureText: true,
              style: const TextStyle(color: AppTheme.ink, fontSize: 14),
              decoration: const InputDecoration(labelText: 'API Key'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => widget.onSave(LlmConfig(
                      baseUrl: _baseUrl.text.trim(),
                      model: _model.text.trim(),
                      apiKey: _apiKey.text.trim(),
                    )),
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
