import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What the reply stream carries besides text.
sealed class AiEvent {}

class AiText extends AiEvent {
  AiText(this.text);
  final String text;
}

/// A server failed mid-answer: drop the partial text, another server answers from the start.
class AiReset extends AiEvent {}

/// The server now answering, shown under the reply.
class AiVia extends AiEvent {
  AiVia(this.name);
  final String name;
}

/// Progress while servers are busy: [code] is 'switching' (to [name]) or 'waiting'.
class AiStatus extends AiEvent {
  AiStatus(this.code, [this.name]);
  final String code;
  final String? name;
}

const _system = '''
You are the assistant of a file and image reading app. People rely on your answers about their own documents (invoices, contracts, reports, spreadsheets, photos), so accuracy matters more than anything else. Reply in the language the user writes in (Arabic or English), clearly and without filler.

When files or images are attached to the conversation, every answer about them must come from their content and nothing else:
- Read the whole file before answering: every page, slide, sheet, table, header, footnote and every part of an image. Do not stop at the first match; when the question asks for all items, totals or a list, include every one that appears, and say how many there are.
- Copy numbers, amounts, dates, names, codes and quotes exactly as written, with the same digits, currency and units. Never round, convert or "correct" them. If you calculate something (a sum, a difference), show the values you used so the user can check them.
- Never add facts, figures or assumptions that are not in the files, and never fill gaps from general knowledge. If something is partly there, give the part that is there and say clearly what is missing.
- If text in a file or image is blurry, cut off, handwritten or otherwise hard to read, say which part is unclear instead of guessing it.
- If the answer is not in the files, reply exactly: "لم أجد هذه المعلومة في الملفات التي رفعتها، لذلك لا أستطيع تأكيد الإجابة." (in English: "I couldn't find this information in the files you uploaded, so I can't confirm an answer.") Do not follow it with a guess.
- If the files contradict each other or themselves, show both values and where each appears.
- Separate what the file states explicitly from anything you infer, and label the inference as such.
- End every answer that uses a file with a line "المصدر:" (or "Source:") naming the file and, only when certain, the page (PDF), slide number (PowerPoint), sheet and cell (Excel) or section heading (Word). Never invent a page or cell.
When nothing is attached, answer normally as a helpful assistant, and say so if you are unsure.
''';

enum Backend { gemini, mistral, free }

class Attempt {
  const Attempt(this.backend, this.model, this.label);
  final Backend backend;
  final String model;
  final String label;
  @override
  String toString() => '$backend/$model';
}

/// Why one attempt failed, and what that means for the next ones.
class _Fail implements Exception {
  _Fail(this.code, {this.retryable = false, this.backendDead = false, this.replacement});
  final String code;

  /// Busy, rate limited or a network drop: worth trying again later.
  final bool retryable;

  /// Bad key: skip every model of this backend.
  final bool backendDead;

  /// A retired Gemini model's successor, tried next.
  final String? replacement;
}

/// Base URLs, overridden in tests.
class Endpoints {
  const Endpoints({
    this.gemini = 'https://generativelanguage.googleapis.com',
    this.mistral = 'https://api.mistral.ai',
    this.free = 'https://text.pollinations.ai',
  });
  final String gemini;
  final String mistral;
  final String free;
}

/// Streams a reply, moving through a chain of servers so a busy or failing one
/// never ends the answer: Gemini models first (they read PDFs and images
/// themselves), then Mistral when its key is set, then a free server that
/// needs no key. When every one is busy it waits and goes round again.
class AiClient {
  AiClient({
    required this.geminiKey,
    this.mistralKey = '',
    this.geminiModel = defaultGeminiModel,
    this.onModelChanged,
    this.endpoints = const Endpoints(),
    this.roundPauses = const [Duration(seconds: 3), Duration(seconds: 8)],
  });

  /// Google's alias for its current Flash model, so the app keeps working when
  /// older versions are retired.
  static const defaultGeminiModel = 'gemini-flash-latest';

  final String geminiKey;
  final String mistralKey;
  final String geminiModel;

  /// Called when Google retired [geminiModel] and its successor answered.
  final void Function(String model)? onModelChanged;
  final Endpoints endpoints;

  /// Pauses before the second and later rounds through the chain.
  final List<Duration> roundPauses;

  static const maxInlineBytes = 18 * 1024 * 1024;

  List<Attempt> chain() => [
        if (geminiKey.trim().isNotEmpty)
          for (final m in {geminiModel, defaultGeminiModel, 'gemini-pro-latest', 'gemini-flash-lite-latest'})
            Attempt(Backend.gemini, m, 'Gemini'),
        if (mistralKey.trim().isNotEmpty) ...[
          const Attempt(Backend.mistral, 'mistral-medium-latest', 'Mistral'),
          const Attempt(Backend.mistral, 'mistral-small-latest', 'Mistral'),
        ],
        const Attempt(Backend.free, 'openai', 'الخادم المجاني'),
      ];

  Stream<AiEvent> reply(Conversation conv) async* {
    final attempts = chain();
    final dead = <String>{};
    final deadBackends = <Backend>{};
    String? lastError;
    String? via;
    for (var round = 0; round <= roundPauses.length; round++) {
      if (round > 0) {
        yield AiStatus('waiting');
        await Future<void>.delayed(roundPauses[round - 1]);
      }
      for (var i = 0; i < attempts.length; i++) {
        final a = attempts[i];
        if (dead.contains('$a') || deadBackends.contains(a.backend)) continue;
        var wrote = false;
        try {
          await for (final text in _run(a, conv)) {
            if (via != a.label) {
              via = a.label;
              yield AiVia(a.label);
            }
            wrote = true;
            yield AiText(text);
          }
          if (!wrote) throw _Fail('empty', retryable: true);
          return;
        } on _Fail catch (f) {
          lastError = f.code;
          if (f.code == 'blocked') throw AiException('blocked');
          if (f.backendDead) deadBackends.add(a.backend);
          if (!f.retryable) dead.add('$a');
          final r = f.replacement;
          if (r != null && !attempts.any((x) => x.model == r)) {
            attempts.insert(i + 1, Attempt(a.backend, r, a.label));
            onModelChanged?.call(r);
          }
          if (wrote) yield AiReset();
          final next = attempts.skip(i + 1).where((x) => !dead.contains('$x') && !deadBackends.contains(x.backend));
          if (next.isNotEmpty && next.first.label != a.label) yield AiStatus('switching', next.first.label);
        }
      }
      if (attempts.every((a) => dead.contains('$a') || deadBackends.contains(a.backend))) break;
    }
    throw AiException(lastError ?? 'busy');
  }

  Stream<String> _run(Attempt a, Conversation conv) async* {
    final http.Request req;
    switch (a.backend) {
      case Backend.gemini:
        req = http.Request('POST', Uri.parse('${endpoints.gemini}/v1beta/models/${a.model}:streamGenerateContent?alt=sse'))
          ..headers.addAll({'Content-Type': 'application/json', 'x-goog-api-key': geminiKey.trim()})
          ..body = jsonEncode({
            'contents': await _geminiContents(conv),
            'systemInstruction': {
              'parts': [
                {'text': _system},
              ],
            },
          });
      case Backend.mistral:
        req = http.Request('POST', Uri.parse('${endpoints.mistral}/v1/chat/completions'))
          ..headers.addAll({'Content-Type': 'application/json', 'Authorization': 'Bearer ${mistralKey.trim()}'})
          ..body = jsonEncode({
            'model': a.model,
            'stream': true,
            'messages': await _openAiMessages(conv, mistralImages: true),
          });
      case Backend.free:
        req = http.Request('POST', Uri.parse('${endpoints.free}/openai'))
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode({'model': a.model, 'stream': true, 'messages': await _openAiMessages(conv)});
    }

    final client = http.Client();
    try {
      final http.StreamedResponse res;
      try {
        res = await client.send(req).timeout(const Duration(seconds: 120));
      } on TimeoutException {
        throw _Fail('timeout', retryable: true);
      } on SocketException {
        throw _Fail('offline', retryable: true);
      } on http.ClientException {
        throw _Fail('network', retryable: true);
      }
      if (res.statusCode >= 400) {
        final body = await res.stream.bytesToString();
        throw _failFor(a, res.statusCode, body);
      }
      final sse = (res.headers['content-type'] ?? '').contains('event-stream');
      if (!sse) {
        final raw = await res.stream.bytesToString();
        final text = _fullText(raw);
        if (text.trim().isNotEmpty) yield text;
        return;
      }
      var buffer = '';
      await for (final chunk in res.stream.transform(utf8.decoder)) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();
        for (final line in lines) {
          final t = line.trim();
          if (!t.startsWith('data:')) continue;
          final data = t.substring(5).trim();
          if (data.isEmpty) continue;
          if (data == '[DONE]') return;
          Map<String, dynamic> j;
          try {
            j = jsonDecode(data) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
          if (j['error'] != null) throw _Fail('busy', retryable: true);
          if (a.backend == Backend.gemini) {
            final cand = (j['candidates'] as List?)?.firstOrNull as Map<String, dynamic>?;
            for (final p in (cand?['content']?['parts'] as List?) ?? const []) {
              final text = p is Map && p['thought'] != true ? p['text'] : null;
              if (text is String && text.isNotEmpty) yield text;
            }
            final finish = cand?['finishReason'];
            if (finish == 'SAFETY' || finish == 'PROHIBITED_CONTENT') throw _Fail('blocked');
          } else {
            final d = (j['choices'] as List?)?.firstOrNull?['delta']?['content'];
            if (d is String && d.isNotEmpty) yield d;
          }
        }
      }
    } on TimeoutException {
      throw _Fail('timeout', retryable: true);
    } on SocketException {
      throw _Fail('offline', retryable: true);
    } on http.ClientException {
      throw _Fail('network', retryable: true);
    } finally {
      client.close();
    }
  }

  _Fail _failFor(Attempt a, int code, String body) {
    var msg = body;
    try {
      msg = (jsonDecode(body)['error']?['message'] as String?) ?? body;
    } catch (_) {}
    if (code == 401 || code == 403 || (code == 400 && msg.contains('API key'))) {
      return _Fail(a.backend == Backend.mistral ? 'badMistralKey' : 'badKey', backendDead: true);
    }
    if (code == 404 && a.backend == Backend.gemini) {
      return _Fail('busy', replacement: replacementModel(msg, {a.model}));
    }
    if (code == 429) return _Fail('rateLimited', retryable: true);
    if (code >= 500) return _Fail('busy', retryable: true);
    if (code == 413) return _Fail('tooLargeTotal');
    if (msg.length > 300) msg = msg.substring(0, 300);
    return _Fail('HTTP $code: $msg');
  }

  /// The successor Google names in a "model retired" message, if any.
  static String? replacementModel(String error, Set<String> tried) {
    for (final m in RegExp(r'models/(gemini-[\w.\-]*\w)').allMatches(error)) {
      final name = m.group(1)!;
      if (!tried.contains(name)) return name;
    }
    return null;
  }

  String _fullText(String raw) {
    try {
      final j = jsonDecode(raw);
      final c = j['choices']?[0]?['message']?['content'];
      if (c is String) return c;
    } catch (_) {}
    return raw;
  }

  /// Gemini reads PDFs and images itself. Attachments are sent in the turn
  /// where they were uploaded, so later questions still "see" every file.
  Future<List<Map<String, dynamic>>> _geminiContents(Conversation conv) async {
    final contents = <Map<String, dynamic>>[];
    var inlineBytes = 0;
    for (final m in _history(conv)) {
      final role = m.role == Role.assistant ? 'model' : 'user';
      final parts = <Map<String, dynamic>>[];
      for (final a in m.attachments) {
        final bytes = a.sentAsBinary ? await _bytes(a) : null;
        if (bytes != null && inlineBytes + bytes.length <= maxInlineBytes) {
          inlineBytes += bytes.length;
          parts.add({'text': '[ملف مرفق: ${a.name}]'});
          parts.add({
            'inline_data': {'mime_type': a.mime, 'data': base64Encode(bytes)},
          });
        } else {
          // Too big to send whole, or a document: send the text read on the phone.
          parts.add({'text': _asText(a)});
        }
      }
      if (m.text.trim().isNotEmpty) parts.add({'text': m.text});
      if (parts.isEmpty) continue;
      if (contents.isNotEmpty && contents.last['role'] == role) {
        (contents.last['parts'] as List).addAll(parts);
      } else {
        contents.add({'role': role, 'parts': parts});
      }
    }
    return contents;
  }

  /// OpenAI-style messages for Mistral and the free server: document and PDF
  /// text as read on the phone, images inline.
  Future<List<Map<String, dynamic>>> _openAiMessages(Conversation conv, {bool mistralImages = false}) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _system},
    ];
    for (final m in _history(conv)) {
      final role = m.role == Role.assistant ? 'assistant' : 'user';
      final parts = <Map<String, dynamic>>[];
      for (final a in m.attachments) {
        final bytes = a.isImage ? await _bytes(a) : null;
        if (bytes != null) {
          final url = 'data:${a.mime};base64,${base64Encode(bytes)}';
          parts.add({'type': 'text', 'text': '[صورة مرفقة: ${a.name}]'});
          parts.add({
            'type': 'image_url',
            'image_url': mistralImages ? url : {'url': url},
          });
        } else {
          parts.add({'type': 'text', 'text': _asText(a)});
        }
      }
      if (m.text.trim().isNotEmpty) parts.add({'type': 'text', 'text': m.text});
      if (parts.isEmpty) continue;
      if (messages.last['role'] == role && messages.last['content'] is List) {
        (messages.last['content'] as List).addAll(parts);
      } else {
        messages.add({'role': role, 'content': role == 'assistant' ? parts.map((p) => p['text']).join('\n') : parts});
      }
    }
    return messages;
  }

  /// Completed turns, starting with the user.
  List<Message> _history(Conversation conv) {
    final list = conv.messages.where((m) => m.role == Role.user || m.status == MsgStatus.complete).toList();
    while (list.isNotEmpty && list.first.role != Role.user) {
      list.removeAt(0);
    }
    return list;
  }

  Future<List<int>?> _bytes(Attachment a) async {
    final f = File(a.path);
    return await f.exists() ? f.readAsBytes() : null;
  }

  String _asText(Attachment a) {
    final text = a.extractedText;
    if (text != null && text.trim().isNotEmpty) {
      return '[ملف مرفق: ${a.name} (${a.typeLabel})]\n$text\n[نهاية الملف: ${a.name}]';
    }
    return '[ملف مرفق: ${a.name} — لا يمكن قراءة محتواه على هذا الخادم (قد يكون ممسوحاً ضوئياً أو محذوفاً). لا تخمّن محتواه، وأخبر المستخدم بذلك.]';
  }
}
