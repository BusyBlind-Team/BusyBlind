import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:busy_blind/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  StreamSubscription<HttpRequest>? handler;

  // 假端点状态：监听只建立一次，切换响应只改这几个变量。
  var status = 200;
  var body = '{}';
  var delayMs = 0; // >0 时延迟回包（超时用例；HttpServer 不能重听，只能改状态）
  late (String, String, String, String) lastRequest; // path, auth, type, body

  setUp(() async {
    status = 200;
    body = '{}';
    delayMs = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    handler = server.listen((req) async {
      final text = await utf8.decoder.bind(req).join(); // 读完请求体再回包
      lastRequest = (
        req.uri.path,
        req.headers.value(HttpHeaders.authorizationHeader) ?? '',
        req.headers.contentType?.value ?? '',
        text,
      );
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
      try {
        req.response
          ..statusCode = status
          ..write(body)
          ..close();
      } catch (_) {
        // 延迟期间连接被客户端断开是预期内的，忽略。
      }
    });
  });

  tearDown(() async {
    await handler?.cancel();
    await server.close(force: true);
  });

  LlmConfig makeConfig() => LlmConfig(
        baseUrl: 'http://127.0.0.1:${server.port}',
        model: 'glm-4-flash',
        apiKey: 'k-test-123',
      );

  void respond(int s, {String b = '{}'}) {
    status = s;
    body = b;
  }

  test('预设常量：默认智谱 GLM，endpoint 拼接容忍尾斜杠', () {
    expect(LlmPresets.glm.model, 'glm-4-flash');
    expect(LlmPresets.glm.baseUrl, contains('bigmodel'));
    expect(
      LlmConfig(baseUrl: 'https://api.example.com/v1/', model: 'm', apiKey: 'k')
          .endpoint,
      'https://api.example.com/v1/chat/completions',
    );
    expect(
      LlmConfig(baseUrl: 'https://api.example.com/v1', model: 'm', apiKey: 'k')
          .endpoint,
      'https://api.example.com/v1/chat/completions',
    );
  });

  test('请求路径/头/体与响应解析', () async {
    respond(200,
        b: jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': '  山不在高，有仙则名。  '},
            }
          ]
        }));

    final client = HttpLlmClient(config: makeConfig());
    final text = await client.chat(const [
      LlmMessage(role: 'system', content: '你是禅修导师'),
      LlmMessage(role: 'user', content: '统计 JSON 在这里'),
    ]);

    expect(text, '山不在高，有仙则名。'); // 首尾空白被裁掉
    expect(lastRequest.$1, '/chat/completions');
    expect(lastRequest.$2, 'Bearer k-test-123');
    expect(lastRequest.$3, 'application/json');
    final sent = jsonDecode(lastRequest.$4) as Map<String, Object?>;
    expect(sent['model'], 'glm-4-flash');
    expect(sent['temperature'], 0.7);
    expect(sent['max_tokens'], 1024);
    expect(sent['stream'], false);
    expect((sent['messages'] as List).length, 2);
    expect((sent['messages'] as List).first,
        {'role': 'system', 'content': '你是禅修导师'});
  });

  test('401/403 → Key 无效；429 → 额度不足', () async {
    respond(401);
    await expectLater(
      HttpLlmClient(config: makeConfig())
          .chat(const [LlmMessage(role: 'user', content: 'hi')]),
      throwsA(isA<LlmException>().having((e) => e.message, 'message', contains('Key'))),
    );

    respond(403);
    await expectLater(
      HttpLlmClient(config: makeConfig())
          .chat(const [LlmMessage(role: 'user', content: 'hi')]),
      throwsA(isA<LlmException>().having((e) => e.message, 'message', contains('Key'))),
    );

    respond(429);
    await expectLater(
      HttpLlmClient(config: makeConfig())
          .chat(const [LlmMessage(role: 'user', content: 'hi')]),
      throwsA(isA<LlmException>().having((e) => e.message, 'message', contains('额度'))),
    );
  });

  test('超时 → 网络异常', () async {
    delayMs = 2000; // 服务端故意慢 2s，客户端 200ms 就该超时
    final client =
        HttpLlmClient(config: makeConfig(), timeout: const Duration(milliseconds: 200));
    await expectLater(
      client.chat(const [LlmMessage(role: 'user', content: 'hi')]),
      throwsA(isA<LlmException>().having((e) => e.message, 'message', contains('网络'))),
    );
  });

  test('响应缺内容 → 明确报错', () async {
    respond(200, b: jsonEncode({'choices': []}));
    await expectLater(
      HttpLlmClient(config: makeConfig())
          .chat(const [LlmMessage(role: 'user', content: 'hi')]),
      throwsA(isA<LlmException>()),
    );
  });
}
