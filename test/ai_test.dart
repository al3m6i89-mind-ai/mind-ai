import 'dart:convert';
import 'dart:io';

import 'package:file_chat/core/ai.dart';
import 'package:file_chat/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake proxy plus the direct free server. [plan] maps `g:MODEL`,
/// `q:MODEL` (any provider id) or `direct` to what each call gets in turn: a
/// status code, 'drop' (connection cut), 'midfail' (some text, then an error)
/// or 'unconfigured'. When a list runs out the service answers normally.
class FakeAi {
  FakeAi(this.plan, {this.config});
  final Map<String, List<Object>> plan;

  /// Served at /config; null answers 500 so the app uses its built-in chain.
  final List<Map<String, Object>>? config;
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final slots = <String>[];
  final userTokens = <String, String?>{};
  int uploaded = 0;
  late HttpServer server;

  String get url => 'http://127.0.0.1:${server.port}';
  AiClient client({bool preferPro = false, String model = AiClient.defaultGeminiModel, void Function(String)? onModel}) =>
      AiClient(
        proxy: Proxy(url, 'tok'),
        freeUrl: '$url/direct',
        preferPro: preferPro,
        geminiModel: model,
        onModelChanged: onModel,
        roundPauses: const [Duration.zero, Duration.zero],
        filePollInterval: Duration.zero,
        headerTimeout: const Duration(milliseconds: 500),
      );

  Future<void> start() async {
    AiClient.resetConfig();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path;
      final direct = path.startsWith('/direct/');
      if (!direct && req.headers.value('x-app-token') != 'tok') {
        req.response
          ..statusCode = 401
          ..headers.set('x-proxy-error', 'token');
        await req.response.close();
        return;
      }
      if (path == '/config') {
        calls.add('config');
        if (config == null) {
          req.response.statusCode = 500;
        } else {
          req.response.write(jsonEncode({'chain': config}));
        }
        await req.response.close();
        return;
      }
      // Gemini file store: start, upload, then one "processing" poll.
      if (path == '/g/upload/v1beta/files') {
        await utf8.decodeStream(req);
        calls.add('upload-start');
        req.response.headers
          ..set('x-goog-upload-url', '$url/g/upload-session')
          ..set('x-key-slot', '3');
        await req.response.close();
        return;
      }
      if (path == '/g/upload-session') {
        uploaded = (await req.fold<List<int>>([], (a, b) => a..addAll(b))).length;
        calls.add('upload');
        slots.add(req.headers.value('x-key-slot') ?? '');
        req.response.write(jsonEncode({
          'file': {'name': 'files/abc', 'uri': 'https://files/abc', 'state': 'PROCESSING'},
        }));
        await req.response.close();
        return;
      }
      if (path == '/g/v1beta/files/abc') {
        calls.add('poll');
        req.response.write(jsonEncode({'name': 'files/abc', 'uri': 'https://files/abc', 'state': 'ACTIVE'}));
        await req.response.close();
        return;
      }
      final raw = await utf8.decodeStream(req);
      final body = jsonDecode(raw) as Map<String, dynamic>;
      final String key;
      if (path.startsWith('/g/v1beta/models/')) {
        key = 'g:${req.uri.pathSegments.last.split(':').first}';
        slots.add(req.headers.value('x-key-slot') ?? '');
      } else if (direct) {
        key = 'direct';
      } else {
        key = '${req.uri.pathSegments.first}:${body['model']}';
      }
      calls.add(key);
      bodies[key] = body;
      userTokens[key] = req.headers.value('x-user-token');
      final steps = plan[key] ?? <Object>[];
      final step = steps.isEmpty ? 200 : steps.removeAt(0);
      if (step == 'hang') {
        await Future<void>.delayed(const Duration(seconds: 3));
        req.response.statusCode = 503;
        await req.response.close();
        return;
      }
      if (step == 'drop') {
        (await req.response.detachSocket(writeHeaders: false)).destroy();
        return;
      }
      if (step == 'quota') {
        req.response
          ..statusCode = 429
          ..headers.set('x-proxy-error', 'quota')
          ..headers.set('x-quota-left', '0');
        await req.response.close();
        return;
      }
      if (step == 'unconfigured') {
        req.response
          ..statusCode = 501
          ..headers.set('x-proxy-error', 'unconfigured');
        await req.response.close();
        return;
      }
      final gemini = key.startsWith('g:');
      String frame(String t) => gemini
          ? 'data: ${jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': t},
                    ],
                  },
                },
              ],
            })}\n\n'
          : 'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': t},
                },
              ],
            })}\n\n';
      if (step is int && step != 200) {
        req.response.statusCode = step;
        req.response.write(jsonEncode({
          'error': {'message': step == 404 ? 'gone, use models/gemini-9-flash' : 'nope'},
        }));
      } else {
        req.response.headers.contentType = ContentType('text', 'event-stream');
        if (step == 'midfail') {
          req.response.write(frame('partial '));
          req.response.write('data: ${jsonEncode({'error': {'message': 'overloaded'}})}\n\n');
        } else {
          req.response.write(frame('ok from $key'));
          if (!gemini) req.response.write('data: [DONE]\n\n');
        }
      }
      await req.response.close();
    });
  }

  Future<void> stop() => server.close(force: true);
}

Conversation conv({List<Attachment> files = const []}) =>
    Conversation(id: 'c', title: 't', messages: [Message(id: 'm', role: Role.user, text: 'hi', attachments: files)]);

/// Runs a reply and returns the final text plus the other events, as strings.
Future<(String, List<String>)> run(AiClient ai, Conversation c) async {
  var text = '';
  final events = <String>[];
  await for (final e in ai.reply(c)) {
    switch (e) {
      case AiText(:final text) when text.isNotEmpty:
        events.add('text');
      case AiText() || AiTrace() || AiVia():
        break;
      case AiReset():
        events.add('reset');
      case AiStatus(:final code):
        events.add(code);
    }
    if (e is AiText) text += e.text;
    if (e is AiReset) text = '';
  }
  return (text, events);
}

Future<File> tempFile(String name, List<int> bytes) async =>
    File('${(await Directory.systemTemp.createTemp()).path}/$name')..writeAsBytesSync(bytes);

const gem = [
  {'backend': 'gemini', 'model': 'gemini-flash-latest', 'p': 'g'},
  {'backend': 'gemini', 'model': 'gemini-pro-latest', 'p': 'g'},
];

void main() {
  test('out of free questions: no other server answers instead', () async {
    final f = FakeAi({
      'g:gemini-flash-latest': ['quota'],
    }, config: gem);
    await f.start();
    int? left;
    final ai = AiClient(
      proxy: Proxy(f.url, 'tok'),
      freeUrl: '${f.url}/direct',
      roundPauses: const [Duration.zero],
      session: const {'x-user-token': 'id-token', 'x-question-id': 'q1'},
      onQuotaLeft: (n) => left = n,
    );
    await expectLater(run(ai, conv()), throwsA(isA<AiException>().having((e) => e.message, 'code', 'quota')));
    expect(f.calls, ['config', 'g:gemini-flash-latest']);
    expect(f.userTokens['g:gemini-flash-latest'], 'id-token');
    expect(left, 0);
    await f.stop();
  });

  test('who is asking goes to the proxy only, never to the direct free server', () async {
    final f = FakeAi({}, config: gem);
    await f.start();
    final ai = AiClient(
        proxy: Proxy(f.url, 'wrong'),
        freeUrl: '${f.url}/direct',
        roundPauses: const [Duration.zero],
        session: const {'x-user-token': 'id-token'});
    final (text, _) = await run(ai, conv());
    expect(text, 'ok from direct');
    expect(f.userTokens['direct'], isNull);
    await f.stop();
  });

  test('busy Gemini moves straight to the next model, through the proxy', () async {
    final f = FakeAi({
      'g:gemini-flash-latest': [503],
    }, config: gem);
    await f.start();
    final (text, events) = await run(f.client(), conv());
    expect(text, 'ok from g:gemini-pro-latest');
    expect(f.calls, ['config', 'g:gemini-flash-latest', 'g:gemini-pro-latest']);
    expect(events, ['text']);
    await f.stop();
  });

  test('every Gemini model busy: Groq answers, images only to models that see them', () async {
    final f = FakeAi({
      'g:gemini-flash-latest': [503],
      'g:gemini-pro-latest': [429],
    }, config: [
      ...gem,
      {'backend': 'openai', 'model': 'text-only', 'p': 'q'},
      {'backend': 'openai', 'model': 'scout', 'p': 'q', 'vision': true},
    ]);
    await f.start();
    final img = await tempFile('a.png', [0x89, 0x50, 0x4E, 0x47]);
    final (text, _) = await run(
        f.client(), conv(files: [Attachment(id: 'a', name: 'a.png', ext: 'png', size: 4, path: img.path)]));
    expect(text, 'ok from q:scout');
    expect(f.calls, isNot(contains('q:text-only')));
    final content = (f.bodies['q:scout']!['messages'] as List)[1]['content'] as List;
    expect(content.any((p) => p['type'] == 'image_url' && (p['image_url']['url'] as String).startsWith('data:image/png;base64,')),
        isTrue);
    await f.stop();
  });

  test('Mistral gets the image data URL as a plain string', () async {
    final f = FakeAi({}, config: [
      {'backend': 'openai', 'model': 'mistral-small-latest', 'p': 'm', 'vision': true},
    ]);
    await f.start();
    final img = await tempFile('a.png', [0x89, 0x50, 0x4E, 0x47]);
    await run(f.client(), conv(files: [Attachment(id: 'a', name: 'a.png', ext: 'png', size: 4, path: img.path)]));
    final content = (f.bodies['m:mistral-small-latest']!['messages'] as List)[1]['content'] as List;
    expect(content.any((p) => p['type'] == 'image_url' && p['image_url'] is String), isTrue);
    await f.stop();
  });

  test('a service the proxy has no key for is skipped entirely', () async {
    final f = FakeAi({
      'q:a': ['unconfigured'],
    }, config: [
      {'backend': 'openai', 'model': 'a', 'p': 'q'},
      {'backend': 'openai', 'model': 'b', 'p': 'q'},
      {'backend': 'openai', 'model': 'c', 'p': 'o'},
    ]);
    await f.start();
    final (text, _) = await run(f.client(), conv());
    expect(text, 'ok from o:c');
    expect(f.calls, ['config', 'q:a', 'o:c']);
    await f.stop();
  });

  test('a proxy that refuses the app falls back to the direct free server', () async {
    final f = FakeAi({}, config: gem);
    await f.start();
    final ai = AiClient(
        proxy: Proxy(f.url, 'wrong'), freeUrl: '${f.url}/direct', roundPauses: const [Duration.zero]);
    final pdf = Attachment(id: 'p', name: 'r.pdf', ext: 'pdf', size: 1, path: '/none', extractedText: '[Page 1]\nTotal 1250');
    final (text, _) = await run(ai, conv(files: [pdf]));
    expect(text, 'ok from direct');
    expect(jsonEncode(f.bodies['direct']), contains('Total 1250'));
    await f.stop();
  });

  test('without /config the built-in chain is used', () async {
    final f = FakeAi({});
    await f.start();
    final (text, _) = await run(f.client(), conv());
    expect(text, 'ok from g:gemini-flash-latest');
    expect(f.calls, ['config', 'g:gemini-flash-latest']);
    await f.stop();
  });

  test('a server that does not start answering is left quickly', () async {
    final f = FakeAi({
      'g:gemini-flash-latest': ['hang'],
    }, config: gem);
    await f.start();
    final sw = Stopwatch()..start();
    final (text, _) = await run(f.client(), conv());
    expect(text, 'ok from g:gemini-pro-latest');
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    await f.stop();
  });

  test('a server failing mid-answer is replaced and its partial text dropped', () async {
    final f = FakeAi({
      'g:gemini-flash-latest': ['midfail'],
    }, config: gem);
    await f.start();
    final (text, events) = await run(f.client(), conv());
    expect(text, 'ok from g:gemini-pro-latest');
    expect(events, ['text', 'reset', 'text']);
    await f.stop();
  });

  test('when everything is busy it waits and goes round again', () async {
    final f = FakeAi({
      'g:gemini-flash-latest': [503],
      'g:gemini-pro-latest': [503],
      'direct': [503],
    }, config: gem);
    await f.start();
    final (text, events) = await run(f.client(), conv());
    expect(text, 'ok from g:gemini-flash-latest');
    expect(events, ['waiting', 'text']);
    await f.stop();
  });

  test('gives up with a busy error only after every round', () async {
    final busy = [503, 503, 503];
    final f = FakeAi({
      'g:gemini-flash-latest': List.of(busy),
      'g:gemini-pro-latest': List.of(busy),
      'direct': ['drop', 'drop', 'drop'],
    }, config: gem);
    await f.start();
    await expectLater(run(f.client(), conv()), throwsA(isA<AiException>().having((e) => e.message, 'code', isIn(['busy', 'network']))));
    expect(f.calls.where((c) => c != 'config'), hasLength(9));
    await f.stop();
  });

  test('a retired Gemini model is replaced by the one Google names, and remembered', () async {
    final f = FakeAi({
      'g:gemini-old': [404],
    }, config: gem);
    await f.start();
    String? saved;
    final (text, _) = await run(f.client(model: 'gemini-old', onModel: (m) => saved = m), conv());
    expect(text, 'ok from g:gemini-9-flash');
    expect(saved, 'gemini-9-flash');
    await f.stop();
  });

  test('a scanned PDF stays with Gemini instead of a model that cannot read it', () async {
    final f = FakeAi({
      'g:gemini-flash-latest': [503, 503],
      'g:gemini-pro-latest': [503],
    }, config: [
      ...gem,
      {'backend': 'openai', 'model': 'x', 'p': 'q', 'vision': true},
    ]);
    await f.start();
    final pdf = await tempFile('s.pdf', utf8.encode('%PDF-1.4'));
    final (text, _) =
        await run(f.client(), conv(files: [Attachment(id: 's', name: 's.pdf', ext: 'pdf', size: 8, path: pdf.path)]));
    expect(text, 'ok from g:gemini-pro-latest');
    expect(f.calls.where((c) => !c.startsWith('g:') && c != 'config'), isEmpty);
    await f.stop();
  });

  test('a big PDF is uploaded once, with the same proxy key used to read it', () async {
    final f = FakeAi({}, config: gem);
    await f.start();
    final big = await tempFile('big.pdf', List.filled(5 * 1024 * 1024, 32));
    final a = Attachment(id: 'b', name: 'big.pdf', ext: 'pdf', size: 5 * 1024 * 1024, path: big.path, extractedText: 'x');
    final ai = f.client();
    final (text, _) = await run(ai, conv(files: [a]));
    expect(text, 'ok from g:gemini-flash-latest');
    expect(f.calls, ['config', 'upload-start', 'upload', 'poll', 'g:gemini-flash-latest']);
    expect(f.uploaded, 5 * 1024 * 1024);
    expect(f.slots, ['3', '3']);
    expect(jsonEncode(f.bodies['g:gemini-flash-latest']), contains('https://files/abc'));
    expect(a.geminiSlot, 3);
    // Asked again: the stored link is reused, nothing is uploaded.
    f.calls.clear();
    await run(ai, conv(files: [a]));
    expect(f.calls, ['g:gemini-flash-latest']);
    await f.stop();
  });

  test('a big PDF that is all text sends its relevant pages, without uploading', () async {
    final f = FakeAi({}, config: gem);
    await f.start();
    final big = await tempFile('book.pdf', List.filled(6 * 1024 * 1024, 32));
    final text = StringBuffer();
    for (var i = 1; i <= 300; i++) {
      text.writeln('\n[الصفحة $i / Page $i]');
      text.writeln(i == 210 ? 'Warranty period is 24 months.' : 'Chapter $i on soil, water and seasonal crops. ' * 10);
    }
    final a = Attachment(
        id: 'k', name: 'book.pdf', ext: 'pdf', size: 6 * 1024 * 1024, path: big.path,
        extractedText: text.toString(), pages: 300, textPages: 300);
    final c = Conversation(id: 'c', title: 't', messages: [
      Message(id: 'm', role: Role.user, text: 'How long is the warranty period?', attachments: [a]),
    ]);
    final (answer, _) = await run(f.client(), c);
    expect(answer, 'ok from g:gemini-flash-latest');
    expect(f.calls, ['config', 'g:gemini-flash-latest']);
    final sent = jsonEncode(f.bodies['g:gemini-flash-latest']);
    expect(sent, contains('Warranty period is 24 months'));
    expect(sent.length, lessThan(120000));
    await f.stop();
  });

  test('paid plan starts with Gemini Pro; the direct free server is always last', () async {
    final f = FakeAi({}, config: gem);
    await f.start();
    final chain = await f.client(preferPro: true).chain();
    expect(chain.first.model, 'gemini-pro-latest');
    expect(chain.where((a) => a.model == 'gemini-pro-latest'), hasLength(1));
    expect(chain.last.direct, isTrue);
    await f.stop();
  });

  test('without a proxy only the direct free server is used', () async {
    final chain = await AiClient(proxy: const Proxy('', '')).chain();
    expect(chain, [AiClient.directFree]);
  });
}
