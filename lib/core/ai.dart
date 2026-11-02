import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'models.dart';
import 'retrieve.dart';

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

/// One server that failed and why, kept with the reply so problems can be diagnosed.
class AiTrace extends AiEvent {
  AiTrace(this.line);
  final String line;
}

const _system = '''
You are the assistant of a file and image reading app. People rely on your answers about their own documents (invoices, contracts, reports, spreadsheets, photos), so accuracy matters more than anything else. Reply in the language the user writes in (Arabic or English).

Be brief: give the exact answer first, in as few words as it needs. No introduction, no repeating the question, no closing offers. Use a short list only when the answer has several items. Brevity never removes a required item, number, the file's explanation or the source line.

When the file itself answers the question (a textbook, teacher's guide, exam, worksheet or Q&A, often marked "الجواب:" or "Answer:"), answer in this order:
1. **الجواب النهائي:** the final answer exactly as the file gives it (in English: **Final answer:**).
2. **الشرح من الملف:** the explanation or reasoning the file gives for it, kept close to the file's wording (in English: **Explanation from the file:**).
3. If the file follows the same item with related questions (for example "هل العدد أقرب إلى ٣٢٠٠ أم إلى ٣٣٠٠؟"), list each with its answer from the file.
4. The source line.
Numbers in PDF text can come out reversed or run together (for example "٥٣٢٤١٠٣٢٥" for "٣٢٤١ < ٣٢٥٠"); read them from their context and write them cleanly, in the digits the user used.

When files or images are attached to the conversation, every answer about them must come from their content and nothing else:
- Read the whole file before answering: every page, slide, sheet, table, header, footnote and every part of an image. When the question asks for all items, totals or a list, include every one that appears.
- Copy numbers, amounts, dates, names, codes and quotes exactly as written, with the same digits, currency and units. Never round, convert or "correct" them. If you calculate something, show the values you used in one line.
- Never add facts, figures or assumptions that are not in the files, and never fill gaps from general knowledge. If something is partly there, give the part that is there and say what is missing.
- If text is blurry, cut off or hard to read, say which part is unclear instead of guessing it.
- If the answer is not in the files, reply exactly: "لم أجد هذه المعلومة في الملفات التي رفعتها، لذلك لا أستطيع تأكيد الإجابة." (in English: "I couldn't find this information in the files you uploaded, so I can't confirm an answer.") Do not follow it with a guess.
- If the files contradict each other, show both values and where each appears.
- End every answer that uses a file with a line "المصدر:" (or "Source:") naming the file and, only when certain, the page (PDF), slide (PowerPoint), sheet and cell (Excel) or section heading (Word). Never invent a page or cell.
When nothing is attached, answer briefly and accurately as a helpful assistant, and say so if you are unsure.
''';

/// How a server is spoken to: Gemini's own API, or the OpenAI chat format
/// that Groq, Mistral, OpenRouter, Cerebras and Pollinations share.
enum Backend { gemini, openai }

/// One server and model in the fallback chain. [provider] is the proxy's
/// short name for the service (g, q, m, o, c, p).
class Attempt {
  const Attempt(this.backend, this.model, this.provider, {this.vision = false, this.direct = false});
  final Backend backend;
  final String model;
  final String provider;

  /// Reads images itself (Gemini always does).
  final bool vision;

  /// Called straight from the phone instead of through the proxy (the keyless
  /// free server, the last resort when the proxy itself is unreachable).
  final bool direct;

  bool get readsImages => backend == Backend.gemini || vision;

  static Attempt? fromJson(Object? j) {
    if (j is! Map) return null;
    final model = j['model'], p = j['p'];
    if (model is! String || p is! String) return null;
    return Attempt(j['backend'] == 'gemini' ? Backend.gemini : Backend.openai, model, p, vision: j['vision'] == true);
  }

  @override
  String toString() => '${direct ? 'direct:' : ''}$provider/$model';
}

/// Why one attempt failed, and what that means for the next ones.
class _Fail implements Exception {
  _Fail(this.code, {this.retryable = false, this.proxyDead = false, this.providerDead = false, this.replacement, this.detail});
  final String code;

  /// The server's own words, for the trace.
  final String? detail;

  /// Busy, rate limited or a network drop: worth trying again later.
  final bool retryable;

  /// The proxy refused the app: skip everything that goes through it.
  final bool proxyDead;

  /// The proxy has no key for this service: skip all its models.
  final bool providerDead;

  /// A retired Gemini model's successor, tried next.
  final String? replacement;
}

/// The app's own server, which holds the AI services' keys so they never ship
/// inside the app. Set at build time with --dart-define.
class Proxy {
  const Proxy(this.url, this.token);
  static const build = Proxy(String.fromEnvironment('PROXY_URL'), String.fromEnvironment('APP_TOKEN'));
  final String url;
  final String token;
  bool get enabled => url.isNotEmpty;
  String get base => url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

/// Streams a reply, moving through a chain of AI services behind the proxy so
/// a busy or failing one never ends the answer. The chain comes from the
/// proxy's /config (so it can change without an app update), with a built-in
/// copy as fallback. When every one is busy it waits and goes round again.
class AiClient {
  AiClient({
    this.proxy = Proxy.build,
    this.freeUrl = 'https://text.pollinations.ai',
    this.preferPro = false,
    this.geminiModel = defaultGeminiModel,
    this.onModelChanged,
    this.roundPauses = const [
      Duration(seconds: 2),
      Duration(seconds: 6),
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(seconds: 45),
    ],
    this.filePollInterval = const Duration(seconds: 2),
    this.headerTimeout = const Duration(seconds: 20),
    this.idleTimeout = const Duration(seconds: 45),
    this.system = _system,
    this.session = const {},
    this.onQuotaLeft,
  });

  /// Who is asking, sent with every request to the proxy: the signed-in user's
  /// token, the device, the question's id (all requests for one answer share it)
  /// and the plan. The proxy counts the daily questions from these.
  final Map<String, String> session;

  /// The proxy's count of questions left today, from each response.
  final void Function(int left)? onQuotaLeft;

  void _quota(Map<String, String> headers) {
    final left = int.tryParse(headers['x-quota-left'] ?? '');
    if (left != null) onQuotaLeft?.call(left);
  }

  /// Instructions sent with every request (the help bot uses its own).
  final String system;

  final Proxy proxy;
  final String freeUrl;

  /// A busy server that has not even started answering is left quickly for
  /// the next one; once text flows, pauses up to [idleTimeout] are allowed.
  final Duration headerTimeout;
  final Duration idleTimeout;
  final Duration filePollInterval;

  /// Google's alias for its current Flash model, so the app keeps working when
  /// older versions are retired.
  static const defaultGeminiModel = 'gemini-flash-latest';
  final String geminiModel;

  /// Paid plan: start with Gemini Pro, the most accurate model.
  final bool preferPro;

  /// Called when Google retired [geminiModel] and its successor answered.
  final void Function(String model)? onModelChanged;

  /// Pauses before the second and later rounds through the chain.
  final List<Duration> roundPauses;

  /// Inline data must stay well under Gemini's 20 MB request limit; bigger
  /// files are uploaded to its file store instead.
  static const maxInlineBytes = 14 * 1024 * 1024;
  static const maxInlineFile = 4 * 1024 * 1024;
  static const maxGeminiPdf = 50 * 1024 * 1024;

  /// Characters of a big document's text sent with each question.
  static const retrievalBudget = 48000;

  /// Used when the proxy's /config cannot be read. Mirrors proxy/src/index.js.
  static const defaultChain = [
    Attempt(Backend.gemini, 'gemini-flash-lite-latest', 'g'),
    Attempt(Backend.gemini, 'gemini-flash-latest', 'g'),
    Attempt(Backend.openai, 'openai/gpt-oss-120b', 'q'),
    Attempt(Backend.openai, 'openai/gpt-oss-20b', 'q'),
    Attempt(Backend.openai, 'mistral-medium-latest', 'm', vision: true),
    Attempt(Backend.openai, 'mistral-small-latest', 'm', vision: true),
    Attempt(Backend.openai, 'gpt-oss-120b', 'c'),
    Attempt(Backend.openai, 'openrouter/free', 'o', vision: true),
    Attempt(Backend.openai, 'openai', 'p', vision: true),
  ];

  /// The keyless free server called directly, so answers keep coming even if
  /// the proxy is down.
  static const directFree = Attempt(Backend.openai, 'openai', 'p', vision: true, direct: true);

  static List<Attempt>? _config;
  static DateTime? _configAt;

  @visibleForTesting
  static void resetConfig() => _config = _configAt = null;

  /// The proxy's chain, cached for ten minutes.
  Future<List<Attempt>> _proxyChain() async {
    final at = _configAt;
    if (_config != null && at != null && DateTime.now().difference(at) < const Duration(minutes: 10)) return _config!;
    try {
      final r = await http
          .get(Uri.parse('${proxy.base}/config'), headers: {'x-app-token': proxy.token})
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final list = [
          for (final e in (jsonDecode(r.body)['chain'] as List? ?? const [])) ?Attempt.fromJson(e),
        ];
        _config = list;
        _configAt = DateTime.now();
        return list;
      }
    } catch (_) {}
    return defaultChain;
  }

  /// The full order for this reply.
  Future<List<Attempt>> chain() async {
    final base = proxy.enabled ? await _proxyChain() : const <Attempt>[];
    final gemini = base.where((a) => a.backend == Backend.gemini).map((a) => a.model).toList();
    return [
      if (gemini.isNotEmpty)
        for (final m in {
          if (preferPro && gemini.contains('gemini-pro-latest')) 'gemini-pro-latest',
          if (gemini.contains(defaultGeminiModel)) geminiModel,
          ...gemini,
        })
          Attempt(Backend.gemini, m, 'g'),
      ...base.where((a) => a.backend != Backend.gemini),
      directFree,
    ];
  }

  /// True when a file can only be read by Gemini (a scanned PDF has no text layer).
  static bool needsGemini(Conversation conv) =>
      conv.attachments.any((a) => a.isPdf && (a.extractedText ?? '').trim().isEmpty);

  static bool hasImages(Conversation conv) => conv.attachments.any((a) => a.isImage);

  Stream<AiEvent> reply(Conversation conv) async* {
    var attempts = await chain();
    // Accuracy before speed: a model that cannot see the file would only answer
    // "not found" or guess, so it is never asked.
    if (hasImages(conv)) attempts = attempts.where((a) => a.readsImages).toList();
    if (needsGemini(conv) && attempts.any((a) => a.backend == Backend.gemini)) {
      attempts = attempts.where((a) => a.backend == Backend.gemini).toList();
    }
    final dead = <String>{};
    final deadProviders = <String>{};
    var proxyDead = false;
    bool skip(Attempt a) => dead.contains('$a') || (!a.direct && (proxyDead || deadProviders.contains(a.provider)));
    String? lastError;
    for (var round = 0; round <= roundPauses.length; round++) {
      if (round > 0) {
        yield AiStatus('waiting');
        await Future<void>.delayed(roundPauses[round - 1]);
      }
      for (var i = 0; i < attempts.length; i++) {
        final a = attempts[i];
        if (skip(a)) continue;
        var wrote = false;
        try {
          await for (final text in _run(a, conv)) {
            wrote = true;
            yield AiText(text);
          }
          if (!wrote) throw _Fail('empty', retryable: true);
          return;
        } on _Fail catch (f) {
          if (lastError == null || f.code == 'blocked' || const {'busy', 'rateLimited', 'timeout', 'network', 'offline'}.contains(f.code)) {
            lastError = f.code;
          }
          final d = f.detail == null ? '' : ' — ${f.detail}';
          yield AiTrace('$a: ${f.code}$d');
          // Out of questions or signed out: no other server may answer instead.
          if (const {'blocked', 'quota', 'signIn', 'suspended'}.contains(f.code)) throw AiException(f.code);
          if (f.proxyDead) proxyDead = true;
          if (f.providerDead) deadProviders.add(a.provider);
          if (!f.retryable) dead.add('$a');
          final r = f.replacement;
          if (r != null && !attempts.any((x) => x.model == r)) {
            attempts.insert(i + 1, Attempt(a.backend, r, a.provider));
            onModelChanged?.call(r);
          }
          if (wrote) yield AiReset();
        }
      }
      if (attempts.every(skip)) break;
    }
    throw AiException(const {'busy', 'rateLimited', 'timeout', 'network', 'offline', 'tooLargeTotal', 'fileFailed'}.contains(lastError)
        ? lastError!
        : 'busy');
  }

  Map<String, String> _headers(Attempt a, [int? slot]) => {
        if (!a.direct && proxy.token.isNotEmpty) 'x-app-token': proxy.token,
        if (!a.direct) ...session,
        if (slot != null) 'x-key-slot': '$slot',
      };

  String _url(Attempt a, String path) => a.direct ? '$freeUrl$path' : '${proxy.base}/${a.provider}$path';

  Stream<String> _run(Attempt a, Conversation conv) async* {
    final http.Request req;
    switch (a.backend) {
      case Backend.gemini:
        final (contents, slot) = await _geminiContents(a, conv);
        req = http.Request('POST', Uri.parse(_url(a, '/v1beta/models/${a.model}:streamGenerateContent?alt=sse')))
          ..headers.addAll({'Content-Type': 'application/json', ..._headers(a, slot)})
          ..body = jsonEncode({
            'contents': contents,
            'systemInstruction': {
              'parts': [
                {'text': system},
              ],
            },
          });
      case Backend.openai:
        req = http.Request('POST', Uri.parse(_url(a, a.direct ? '/openai' : '/v1/chat/completions')))
          ..headers.addAll({'Content-Type': 'application/json', ..._headers(a)})
          ..body = jsonEncode({
            'model': a.model,
            'stream': true,
            'messages': await _openAiMessages(conv, images: a.readsImages, stringImages: a.provider == 'm'),
          });
    }

    final client = http.Client();
    try {
      final http.StreamedResponse res;
      try {
        res = await client.send(req).timeout(headerTimeout);
      } on TimeoutException {
        throw _Fail('timeout', retryable: true);
      } on SocketException {
        throw _Fail('offline', retryable: true);
      } on http.ClientException {
        throw _Fail('network', retryable: true);
      }
      if (res.statusCode >= 400) {
        final body = await res.stream.bytesToString();
        throw _failFor(a, res.statusCode, body, res.headers);
      }
      _quota(res.headers);
      final sse = (res.headers['content-type'] ?? '').contains('event-stream');
      if (!sse) {
        final raw = await res.stream.bytesToString();
        final text = _fullText(raw);
        if (text.trim().isNotEmpty) yield text;
        return;
      }
      var buffer = '';
      // A stream that goes quiet for too long is treated as a dropped server.
      await for (final chunk in res.stream.timeout(idleTimeout).transform(utf8.decoder)) {
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
          if (j['error'] != null) throw _Fail('busy', retryable: true, detail: _short('${j['error']['message'] ?? j['error']}'));
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

  _Fail _failFor(Attempt a, int code, String body, Map<String, String> headers) {
    var msg = body;
    try {
      msg = (jsonDecode(body)['error']?['message'] as String?) ?? body;
    } catch (_) {}
    final detail = 'HTTP $code ${_short(msg)}';
    // The proxy's own answers are marked, so they are not mistaken for the service's.
    if (headers['x-proxy-error'] == 'token') return _Fail('busy', proxyDead: true, detail: detail);
    if (headers['x-proxy-error'] == 'quota') {
      _quota(headers);
      return _Fail('quota', detail: detail);
    }
    if (headers['x-proxy-error'] == 'auth') return _Fail('signIn', detail: detail);
    if (headers['x-proxy-error'] == 'blocked') return _Fail('suspended', detail: detail);
    if (headers['x-proxy-error'] == 'question') return _Fail('busy', proxyDead: true, detail: detail);
    if (headers['x-proxy-error'] == 'path') return _Fail('busy', proxyDead: true, detail: detail);
    if (headers['x-proxy-error'] == 'unconfigured') return _Fail('busy', providerDead: true, detail: detail);
    if (code == 401 || code == 403 || (code == 400 && msg.contains('API key'))) {
      // One of the proxy's keys is bad; the next attempt draws another.
      return _Fail('badKey', detail: detail);
    }
    if (code == 404 && a.backend == Backend.gemini) {
      return _Fail('busy', replacement: replacementModel(msg, {a.model}), detail: detail);
    }
    if (code == 429) return _Fail('rateLimited', retryable: true, detail: detail);
    if (code >= 500) return _Fail('busy', retryable: true, detail: detail);
    if (code == 413) return _Fail('tooLargeTotal', detail: detail);
    return _Fail('HTTP $code', detail: detail);
  }

  static String _short(String s) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length > 160 ? '${one.substring(0, 160)}…' : one;
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
  /// Returns the proxy key slot the uploaded files belong to, if any: a file
  /// in Gemini's store can only be read with the key that uploaded it.
  Future<(List<Map<String, dynamic>>, int?)> _geminiContents(Attempt via, Conversation conv) async {
    final contents = <Map<String, dynamic>>[];
    var inlineBytes = 0;
    int? slot;
    for (final m in _history(conv)) {
      final role = m.role == Role.assistant ? 'model' : 'user';
      final parts = <Map<String, dynamic>>[];
      for (final a in m.attachments) {
        // Gemini reads PDFs up to 50 MB. Bigger ones, and big PDFs that are all
        // text, go as the text read on the phone: the pages that answer the
        // question, which is much faster than uploading and reading the book.
        final asText = !a.sentAsBinary || (a.isPdf && (a.size > maxGeminiPdf || (a.size > maxInlineFile && a.textual)));
        final bytes = asText ? null : await _bytes(a);
        if (bytes == null) {
          parts.add({'text': _asText(a, conv)});
        } else if (bytes.length <= maxInlineFile && inlineBytes + bytes.length <= maxInlineBytes) {
          inlineBytes += bytes.length;
          parts.add({'text': '[ملف مرفق: ${a.name}]'});
          parts.add({
            'inline_data': {'mime_type': a.mime, 'data': base64Encode(bytes)},
          });
        } else {
          // Big files go through Gemini's file store, which takes PDFs up to 50 MB.
          final (uri, s) = await _geminiFile(via, a, bytes, slot);
          slot = s;
          parts.add({'text': '[ملف مرفق: ${a.name}]'});
          parts.add({
            'file_data': {'mime_type': a.mime, 'file_uri': uri},
          });
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
    return (contents, slot);
  }

  /// Uploads [a] to Gemini's file store once (resumable upload) and waits until
  /// Google has processed it. The link is reused until shortly before it
  /// expires, as long as it belongs to the same key as the other files.
  Future<(String, int?)> _geminiFile(Attempt via, Attachment a, List<int> bytes, int? slot) async {
    final cached = a.geminiUri;
    final expires = a.geminiUriExpires;
    if (cached != null &&
        expires != null &&
        expires.isAfter(DateTime.now().add(const Duration(hours: 1))) &&
        (slot == null || slot == a.geminiSlot)) {
      return (cached, a.geminiSlot);
    }
    const files = Attempt(Backend.gemini, 'files', 'g');
    final client = http.Client();
    try {
      final start = await client
          .post(
            Uri.parse(_url(via, '/upload/v1beta/files')),
            headers: {
              ..._headers(via, slot),
              'X-Goog-Upload-Protocol': 'resumable',
              'X-Goog-Upload-Command': 'start',
              'X-Goog-Upload-Header-Content-Length': '${bytes.length}',
              'X-Goog-Upload-Header-Content-Type': a.mime,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'file': {'display_name': a.name},
            }),
          )
          .timeout(const Duration(seconds: 60));
      final uploadUrl = start.headers['x-goog-upload-url'];
      if (start.statusCode >= 400 || uploadUrl == null) {
        throw _failFor(files, start.statusCode, start.body, start.headers);
      }
      final used = int.tryParse(start.headers['x-key-slot'] ?? '') ?? slot;
      final done = await client
          .post(
            Uri.parse(uploadUrl),
            headers: {
              ..._headers(via, used),
              'X-Goog-Upload-Offset': '0',
              'X-Goog-Upload-Command': 'upload, finalize',
            },
            body: bytes,
          )
          .timeout(const Duration(minutes: 5));
      if (done.statusCode >= 400) throw _failFor(files, done.statusCode, done.body, done.headers);
      var file = (jsonDecode(done.body) as Map<String, dynamic>)['file'] as Map<String, dynamic>;
      // PDFs are processed for a moment before they can be read.
      for (var i = 0; i < 60 && file['state'] == 'PROCESSING'; i++) {
        await Future<void>.delayed(filePollInterval);
        final r = await client
            .get(Uri.parse(_url(via, '/v1beta/${file['name']}')), headers: _headers(via, used))
            .timeout(const Duration(seconds: 30));
        if (r.statusCode >= 400) throw _failFor(files, r.statusCode, r.body, r.headers);
        file = jsonDecode(r.body) as Map<String, dynamic>;
      }
      if (file['state'] == 'FAILED') throw _Fail('fileFailed', detail: 'Gemini could not process ${a.name}');
      final uri = file['uri'] as String;
      a
        ..geminiUri = uri
        ..geminiSlot = used
        ..geminiUriExpires = DateTime.tryParse(file['expirationTime'] as String? ?? '') ??
            DateTime.now().add(const Duration(hours: 47));
      return (uri, used);
    } on TimeoutException {
      throw _Fail('timeout', retryable: true, detail: 'upload of ${a.name}');
    } on SocketException {
      throw _Fail('offline', retryable: true);
    } on http.ClientException {
      throw _Fail('network', retryable: true, detail: 'upload of ${a.name}');
    } finally {
      client.close();
    }
  }

  /// OpenAI-style messages: document and PDF text as read on the phone, images
  /// inline (Mistral wants the data URL as a plain string).
  Future<List<Map<String, dynamic>>> _openAiMessages(Conversation conv, {bool images = true, bool stringImages = false}) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
    ];
    for (final m in _history(conv)) {
      final role = m.role == Role.assistant ? 'assistant' : 'user';
      final parts = <Map<String, dynamic>>[];
      for (final a in m.attachments) {
        final bytes = a.isImage && images ? await _bytes(a) : null;
        if (bytes != null) {
          final url = 'data:${a.mime};base64,${base64Encode(bytes)}';
          parts.add({'type': 'text', 'text': '[صورة مرفقة: ${a.name}]'});
          parts.add({
            'type': 'image_url',
            'image_url': stringImages ? url : {'url': url},
          });
        } else {
          parts.add({'type': 'text', 'text': _asText(a, conv)});
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

  String _asText(Attachment a, Conversation conv) {
    final text = a.extractedText;
    if (text != null && text.trim().isNotEmpty) {
      final asks = [for (final m in conv.messages) if (m.role == Role.user && m.text.trim().isNotEmpty) m.text];
      final r = relevant(text,
          asks.isEmpty ? '' : asks.last, context: asks.length > 1 ? asks[asks.length - 2] : '', budget: retrievalBudget);
      if (r.whole) return '[ملف مرفق: ${a.name} (${a.typeLabel})]\n$text\n[نهاية الملف: ${a.name}]';
      return '[ملف مرفق: ${a.name} (${a.typeLabel}) — ملف كبير، هذه ${r.shown} من أصل ${r.total} '
          '${a.isPdf ? 'صفحة' : 'جزء'} هي الأكثر صلة بالسؤال الأخير. أجب منها واذكر رقم الصفحة. '
          'إذا لم تجد الإجابة فيها فقل ذلك، واقترح على المستخدم كلمات أدق أو رقم الصفحة.]\n'
          '${r.text}\n[نهاية المقتطفات من: ${a.name}]';
    }
    return '[ملف مرفق: ${a.name} — لا يمكن قراءة محتواه على هذا الخادم (قد يكون ممسوحاً ضوئياً أو محذوفاً). لا تخمّن محتواه، وأخبر المستخدم بذلك.]';
  }
}
