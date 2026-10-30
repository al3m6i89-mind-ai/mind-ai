import 'dart:convert';
import 'dart:io';

import 'package:file_chat/core/ai.dart';
import 'package:file_chat/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// One fake server for all three backends. [plan] maps `gemini:MODEL`,
/// `mistral:MODEL` or `free` to what each call gets in turn: a status code,
/// 'drop' (connection cut) or 'midfail' (some text, then an error). When a
/// list runs out the backend answers normally.
class FakeAi {
  FakeAi(this.plan);
  final Map<String, List<Object>> plan;
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  late HttpServer server;

  Endpoints get endpoints {
    final u = 'http://127.0.0.1:${server.port}';
    return Endpoints(gemini: u, mistral: u, free: u);
  }

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final raw = await utf8.decodeStream(req);
      final body = jsonDecode(raw) as Map<String, dynamic>;
      final path = req.uri.path;
      final String key;
      if (path.startsWith('/v1beta/models/')) {
        key = 'gemini:${req.uri.pathSegments.last.split(':').first}';
      } else if (path == '/v1/chat/completions') {
        key = 'mistral:${body['model']}';
      } else {
        key = 'free';
      }
      calls.add(key);
      bodies[key] = body;
      final steps = plan[key] ?? <Object>[];
      final step = steps.isEmpty ? 200 : steps.removeAt(0);
      if (step == 'drop') {
        (await req.response.detachSocket(writeHeaders: false)).destroy();
        return;
      }
      final gemini = key.startsWith('gemini');
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
      case AiText():
        break;
      case AiReset():
        events.add('reset');
      case AiVia(:final name):
        events.add('via:$name');
      case AiStatus(:final code, :final name):
        events.add(name == null ? code : '$code:$name');
      case AiTrace():
        break;
    }
    if (e is AiText) text += e.text;
    if (e is AiReset) text = '';
  }
  return (text, events);
}

void main() {
  const noWait = [Duration.zero, Duration.zero];

  test('busy Gemini moves straight to the next Gemini model', () async {
    final f = FakeAi({
      'gemini:gemini-flash-latest': [503],
    });
    await f.start();
    final ai = AiClient(geminiKey: 'k', endpoints: f.endpoints, roundPauses: noWait);
    final (text, events) = await run(ai, conv());
    expect(text, 'ok from gemini:gemini-pro-latest');
    expect(f.calls, ['gemini:gemini-flash-latest', 'gemini:gemini-pro-latest']);
    expect(events, ['via:Gemini', 'text']);
    await f.stop();
  });

  test('all Gemini models busy: Mistral answers, images sent inline', () async {
    final f = FakeAi({
      'gemini:gemini-flash-latest': [503],
      'gemini:gemini-pro-latest': [429],
      'gemini:gemini-flash-lite-latest': ['drop'],
    });
    await f.start();
    final img = File('${(await Directory.systemTemp.createTemp()).path}/a.png')..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
    final ai = AiClient(geminiKey: 'k', mistralKey: 'm', endpoints: f.endpoints, roundPauses: noWait);
    final (text, events) = await run(
        ai, conv(files: [Attachment(id: 'a', name: 'a.png', ext: 'png', size: 4, path: img.path)]));
    expect(text, 'ok from mistral:mistral-medium-latest');
    expect(events, ['switching:Mistral', 'via:Mistral', 'text']);
    final content = (f.bodies['mistral:mistral-medium-latest']!['messages'] as List)[1]['content'] as List;
    expect(content.any((p) => p['type'] == 'image_url' && (p['image_url'] as String).startsWith('data:image/png;base64,')), isTrue);
    await f.stop();
  });

  test('no keys: the free server answers with the text read on the phone', () async {
    final f = FakeAi({});
    await f.start();
    final ai = AiClient(geminiKey: '', endpoints: f.endpoints, roundPauses: noWait);
    final pdf = Attachment(id: 'p', name: 'r.pdf', ext: 'pdf', size: 1, path: '/none', extractedText: '[Page 1]\nTotal 1250');
    final (text, _) = await run(ai, conv(files: [pdf]));
    expect(text, 'ok from free');
    expect(jsonEncode(f.bodies['free']), contains('Total 1250'));
    await f.stop();
  });

  test('a server failing mid-answer is replaced and its partial text dropped', () async {
    final f = FakeAi({
      'gemini:gemini-flash-latest': ['midfail'],
    });
    await f.start();
    final ai = AiClient(geminiKey: 'k', endpoints: f.endpoints, roundPauses: noWait);
    final (text, events) = await run(ai, conv());
    expect(text, 'ok from gemini:gemini-pro-latest');
    expect(events, ['via:Gemini', 'text', 'reset', 'text']);
    await f.stop();
  });

  test('when everything is busy it waits and goes round again', () async {
    final f = FakeAi({
      'gemini:gemini-flash-latest': [503],
      'gemini:gemini-pro-latest': [503],
      'gemini:gemini-flash-lite-latest': [503],
      'free': [503],
    });
    await f.start();
    final ai = AiClient(geminiKey: 'k', endpoints: f.endpoints, roundPauses: noWait);
    final (text, events) = await run(ai, conv());
    expect(text, 'ok from gemini:gemini-flash-latest');
    expect(events, ['switching:الخادم المجاني', 'waiting', 'via:Gemini', 'text']);
    await f.stop();
  });

  test('gives up with a busy error only after every round', () async {
    final busy = [503, 503, 503];
    final f = FakeAi({
      'gemini:gemini-flash-latest': List.of(busy),
      'gemini:gemini-pro-latest': List.of(busy),
      'gemini:gemini-flash-lite-latest': List.of(busy),
      'free': List.of(busy),
    });
    await f.start();
    final ai = AiClient(geminiKey: 'k', endpoints: f.endpoints, roundPauses: noWait);
    await expectLater(run(ai, conv()), throwsA(isA<AiException>().having((e) => e.message, 'code', 'busy')));
    expect(f.calls, hasLength(12));
    await f.stop();
  });

  test('a bad Gemini key skips Gemini and the free server answers', () async {
    final f = FakeAi({
      'gemini:gemini-flash-latest': [400],
    });
    // 400 without "API key" is a plain failure; use 403 for a bad key.
    f.plan['gemini:gemini-flash-latest'] = [403];
    await f.start();
    final ai = AiClient(geminiKey: 'bad', endpoints: f.endpoints, roundPauses: noWait);
    final (text, _) = await run(ai, conv());
    expect(text, 'ok from free');
    expect(f.calls, ['gemini:gemini-flash-latest', 'free']);
    await f.stop();
  });

  test('a retired Gemini model is replaced by the one Google names, and remembered', () async {
    final f = FakeAi({
      'gemini:gemini-old': [404],
    });
    await f.start();
    String? saved;
    final ai = AiClient(
        geminiKey: 'k', geminiModel: 'gemini-old', onModelChanged: (m) => saved = m, endpoints: f.endpoints, roundPauses: noWait);
    final (text, _) = await run(ai, conv());
    expect(text, 'ok from gemini:gemini-9-flash');
    expect(saved, 'gemini-9-flash');
    await f.stop();
  });

  test('a scanned PDF stays with Gemini instead of a server that cannot read it', () async {
    final f = FakeAi({
      'gemini:gemini-flash-latest': [503, 503],
      'gemini:gemini-pro-latest': [503, 503],
      'gemini:gemini-flash-lite-latest': [503],
    });
    await f.start();
    final pdf = File('${(await Directory.systemTemp.createTemp()).path}/s.pdf')..writeAsStringSync('%PDF-1.4');
    final ai = AiClient(geminiKey: 'k', mistralKey: 'm', endpoints: f.endpoints, roundPauses: noWait);
    final traces = <String>[];
    var text = '';
    await for (final e in ai.reply(conv(files: [Attachment(id: 's', name: 's.pdf', ext: 'pdf', size: 8, path: pdf.path)]))) {
      if (e is AiTrace) traces.add(e.line);
      if (e is AiText) text += e.text;
    }
    expect(text, 'ok from gemini:gemini-flash-lite-latest');
    expect(f.calls.where((c) => !c.startsWith('gemini')), isEmpty);
    expect(traces.first, startsWith('gemini-flash-latest: busy — HTTP 503'));
    await f.stop();
  });
}
