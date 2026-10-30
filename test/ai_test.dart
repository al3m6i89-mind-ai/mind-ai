import 'dart:convert';
import 'dart:io';

import 'package:file_chat/core/ai.dart';
import 'package:file_chat/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake Gemini that answers each model with the given status codes in turn.
Future<(HttpServer, List<String>)> fakeGemini(Map<String, List<int>> plan) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final calls = <String>[];
  server.listen((req) async {
    await utf8.decodeStream(req);
    final model = req.uri.pathSegments.last.split(':').first;
    calls.add(model);
    final codes = plan[model] ?? [404];
    final code = codes.isEmpty ? 200 : codes.removeAt(0);
    req.response.statusCode = code;
    if (code == 200) {
      req.response.headers.contentType = ContentType('text', 'event-stream');
      req.response.write('data: ${jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'ok from $model'},
                  ],
                },
              },
            ],
          })}\n\n');
    } else {
      req.response.write(jsonEncode({
        'error': {'code': code, 'message': code == 404 ? 'use models/gemini-9-flash' : 'busy'},
      }));
    }
    await req.response.close();
  });
  return (server, calls);
}

Conversation conv() => Conversation(id: 'c', title: 't', messages: [Message(id: 'm', role: Role.user, text: 'hi')]);

void main() {
  test('busy model is retried, then a lighter model answers', () async {
    final (server, calls) = await fakeGemini({
      'gemini-flash-latest': [503, 503],
      'gemini-flash-lite-latest': [],
    });
    String? saved;
    final ai = AiClient(
      provider: Provider.gemini,
      geminiKey: 'k',
      baseUrl: 'http://127.0.0.1:${server.port}',
      onModelChanged: (m) => saved = m,
    );
    expect(await ai.reply(conv()).join(), 'ok from gemini-flash-lite-latest');
    expect(calls, ['gemini-flash-latest', 'gemini-flash-latest', 'gemini-flash-lite-latest']);
    expect(saved, isNull, reason: 'a busy fallback is not remembered');
    await server.close(force: true);
  });

  test('retired model switches to the named one and remembers it', () async {
    final (server, calls) = await fakeGemini({'gemini-flash-latest': [404], 'gemini-9-flash': []});
    String? saved;
    final ai = AiClient(
      provider: Provider.gemini,
      geminiKey: 'k',
      baseUrl: 'http://127.0.0.1:${server.port}',
      onModelChanged: (m) => saved = m,
    );
    expect(await ai.reply(conv()).join(), 'ok from gemini-9-flash');
    expect(saved, 'gemini-9-flash');
    await server.close(force: true);
  });

  test('all busy gives a friendly busy error', () async {
    final (server, _) = await fakeGemini({
      'gemini-flash-latest': [503, 503],
      'gemini-flash-lite-latest': [503],
      'gemini-2.5-flash-lite': [503],
    });
    final ai = AiClient(provider: Provider.gemini, geminiKey: 'k', baseUrl: 'http://127.0.0.1:${server.port}');
    await expectLater(ai.reply(conv()).join(), throwsA(isA<AiException>().having((e) => e.message, 'code', 'busy')));
    await server.close(force: true);
  });
}
