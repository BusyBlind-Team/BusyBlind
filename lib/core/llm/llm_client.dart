import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// OpenAI 兼容接口的连接配置。
class LlmConfig {
  const LlmConfig({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  final String baseUrl;
  final String model;
  final String apiKey;

  LlmConfig copyWith({String? baseUrl, String? model, String? apiKey}) =>
      LlmConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
      );

  /// chat/completions 完整地址；容忍 baseUrl 带不带尾斜杠。
  String get endpoint =>
      '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}/chat/completions';
}

/// 三家预设（Key 一律留空，由用户在设置里填写）；GLM 为默认。
abstract final class LlmPresets {
  static const glm = LlmConfig(
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4-flash',
    apiKey: '',
  );
  static const deepseek = LlmConfig(
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat',
    apiKey: '',
  );
  static const openai = LlmConfig(
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    apiKey: '',
  );
}

/// 一条对话消息（role: system / user / assistant）。
class LlmMessage {
  const LlmMessage({required this.role, required this.content});
  final String role;
  final String content;

  Map<String, Object?> toJson() => {'role': role, 'content': content};
}

/// LLM 调用失败：message 是可直接展示给用户的中文原因。
class LlmException implements Exception {
  LlmException(this.message);
  final String message;

  @override
  String toString() => 'LlmException: $message';
}

/// 报告生成的客户端契约：测试注入假实现，生产用 [HttpLlmClient]。
abstract class LlmClient {
  Future<String> chat(List<LlmMessage> messages, {int maxTokens = 1024});
}

/// OpenAI 兼容 /chat/completions 客户端。
///
/// 状态码与超时统一映射成用户能看懂的一句话，页面不再分类。
class HttpLlmClient implements LlmClient {
  HttpLlmClient({
    required this.config,
    this.timeout = const Duration(seconds: 30),
    this.httpClient,
  });

  final LlmConfig config;
  final Duration timeout;

  /// 注入测试用；留空则每次调用自建短命连接、用完即关。
  final http.Client? httpClient;

  @override
  Future<String> chat(List<LlmMessage> messages, {int maxTokens = 1024}) async {
    final client = httpClient ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse(config.endpoint),
            headers: {
              'Authorization': 'Bearer ${config.apiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': config.model,
              'messages': messages.map((m) => m.toJson()).toList(),
              'temperature': 0.7,
              'max_tokens': maxTokens,
              'stream': false,
            }),
          )
          .timeout(timeout);
      return _parse(response);
    } on TimeoutException {
      throw LlmException('网络异常：请求超时，请检查网络后重试');
    } on http.ClientException {
      throw LlmException('网络异常：无法连接服务，请检查网络后重试');
    } finally {
      if (httpClient == null) client.close();
    }
  }

  String _parse(http.Response response) {
    switch (response.statusCode) {
      case 401:
      case 403:
        throw LlmException('API Key 无效或无权限，请到设置里检查');
      case 429:
        throw LlmException('额度不足或请求过于频繁，请稍后再试');
    }
    if (response.statusCode != 200) {
      throw LlmException('服务异常（HTTP ${response.statusCode}），请稍后再试');
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw LlmException('服务返回了无法解析的内容');
    }
    // 边界校验响应结构（复审 R6）：兼容接口可能返回数组正文、choices
    // 元素或 content 类型异常。强转失败抛的是 TypeError（属 Error 不是
    // Exception），会绕过页面的 on Exception 兜底，这里统一归一成
    // LlmException。
    final String? text;
    try {
      final choices = (body as Map?)?['choices'];
      final first = choices is List && choices.isNotEmpty ? choices.first : null;
      final content = first is Map ? first['message'] : null;
      text = content is Map ? content['content'] as String? : null;
    } catch (_) {
      throw LlmException('服务返回了异常的结构，请重试');
    }
    if (text == null || text.trim().isEmpty) {
      throw LlmException('模型没有返回内容，请重试');
    }
    return text.trim();
  }
}
