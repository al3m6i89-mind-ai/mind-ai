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

enum Provider { gemini, pollinations }

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

/// Streams a reply. Gemini reads PDFs and images itself; extracted text from
/// Word, Excel and PowerPoint is sent as text.
class AiClient {
  AiClient({required this.provider, required this.geminiKey, this.model = defaultGeminiModel, this.onModelChanged, this.baseUrl = 'https://generativelanguage.googleapis.com'});

  /// Google's alias for its current Flash model, so the app keeps working when
  /// older versions are retired.
  static const defaultGeminiModel = 'gemini-flash-latest';

  /// Lighter models tried when the main one is overloaded or out of free quota.
  static const backupModels = ['gemini-flash-lite-latest', 'gemini-2.5-flash-lite'];

  final Provider provider;
  final String geminiKey;
  final String model;

  /// Called when Google retired [model] and another one answered instead.
  final void Function(String model)? onModelChanged;

  /// Overridden in tests.
  final String baseUrl;

  static const maxInlineBytes = 18 * 1024 * 1024;

  Stream<String> reply(Conversation conv) {
    if (provider == Provider.gemini) {
      if (geminiKey.trim().isEmpty) throw AiException('missingKey');
      return _gemini(conv);
    }
    return _pollinations(conv);
  }

  /// Attachments are sent once, in the turn where they were uploaded, so later
  /// questions still "see" every file in the conversation.
  Future<List<Map<String, dynamic>>> _geminiContents(Conversation conv) async {
    final contents = <Map<String, dynamic>>[];
    var inlineBytes = 0;
    for (final m in conv.messages) {
      if (m.role == Role.assistant && m.status != MsgStatus.complete) continue;
      final role = m.role == Role.assistant ? 'model' : 'user';
      final parts = <Map<String, dynamic>>[];
      for (final a in m.attachments) {
        if (a.sentAsBinary) {
          final f = File(a.path);
          if (!await f.exists()) {
            parts.add({'text': '[الملف «${a.name}» حُذف من الجهاز]'});
            continue;
          }
          final bytes = await f.readAsBytes();
          inlineBytes += bytes.length;
          if (inlineBytes > maxInlineBytes) throw AiException('tooLargeTotal');
          parts.add({'text': '[ملف مرفق: ${a.name}]'});
          parts.add({
            'inline_data': {'mime_type': a.mime, 'data': base64Encode(bytes)},
          });
        } else if (a.readable) {
          parts.add({'text': '[ملف مرفق: ${a.name} (${a.typeLabel})]\n${a.extractedText}\n[نهاية الملف: ${a.name}]'});
        } else {
          parts.add({'text': '[ملف مرفق: ${a.name} — تعذّرت قراءة محتواه]'});
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
    while (contents.isNotEmpty && contents.first['role'] != 'user') {
      contents.removeAt(0);
    }
    return contents;
  }

  Stream<String> _gemini(Conversation conv) async* {
    final contents = await _geminiContents(conv);
    if (contents.isEmpty) return;
    final body = jsonEncode({
      'contents': contents,
      'systemInstruction': {
        'parts': [
          {'text': _system},
        ],
      },
    });
    final client = http.Client();
    try {
      // Nothing has been shown yet, so retrying is safe:
      // - 404: the model was retired; try the one Google names, then the alias, and remember it.
      // - 5xx (overloaded): retry once after a pause, then fall back to a lighter model.
      // - 429 (this model's free quota is used up): fall back to a lighter model, which has its own quota.
      final tried = <String>{};
      var current = model;
      String? replacement;
      var retriedBusy = false;
      var retriedNetwork = false;
      late http.StreamedResponse res;
      while (true) {
        tried.add(current);
        final url = '$baseUrl/v1beta/models/$current:streamGenerateContent?alt=sse';
        final req = http.Request('POST', Uri.parse(url))
          ..headers.addAll({'Content-Type': 'application/json', 'x-goog-api-key': geminiKey.trim()})
          ..body = body;
        try {
          res = await client.send(req).timeout(const Duration(seconds: 120));
        } on http.ClientException {
          // A dropped connection (switching Wi-Fi/mobile data, brief signal loss): try once more.
          if (retriedNetwork) rethrow;
          retriedNetwork = true;
          tried.remove(current);
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          continue;
        }
        if (res.statusCode < 400) break;
        final err = await res.stream.bytesToString();
        final code = res.statusCode;
        String? next;
        if (code == 404) {
          next = replacementModel(err, tried);
          replacement = next;
        } else if (code >= 500 && !retriedBusy) {
          retriedBusy = true;
          await Future<void>.delayed(const Duration(seconds: 2));
          next = current;
          tried.remove(current);
        } else if (code >= 500 || code == 429) {
          next = backupModels.where((m) => !tried.contains(m)).firstOrNull;
        }
        if (next == null) throw AiException(code >= 500 ? 'busy' : _friendly(code, err));
        current = next;
      }
      if (replacement != null && current == replacement) onModelChanged?.call(current);
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
          Map<String, dynamic> j;
          try {
            j = jsonDecode(data) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
          if (j['error'] != null) throw AiException(j['error']['message']?.toString() ?? 'Gemini error');
          final cand = (j['candidates'] as List?)?.firstOrNull as Map<String, dynamic>?;
          final parts = cand?['content']?['parts'] as List?;
          for (final p in parts ?? const []) {
            final text = p is Map ? p['text'] : null;
            if (text is String && text.isNotEmpty) yield text;
          }
          final finish = cand?['finishReason'];
          if (finish == 'SAFETY' || finish == 'PROHIBITED_CONTENT') throw AiException('blocked');
        }
      }
    } on TimeoutException {
      throw AiException('timeout');
    } on SocketException {
      throw AiException('offline');
    } on http.ClientException {
      throw AiException('network');
    } finally {
      client.close();
    }
  }

  /// The model to try after [error] said the last one is gone: the one Google
  /// names in the message, else the Flash alias. Null when all were tried.
  static String? replacementModel(String error, Set<String> tried) {
    for (final m in RegExp(r'models/(gemini-[\w.\-]+)').allMatches(error)) {
      final name = m.group(1)!;
      if (!tried.contains(name)) return name;
    }
    return tried.contains(defaultGeminiModel) ? null : defaultGeminiModel;
  }

  /// Free, no key. Text only: it cannot read PDFs or images.
  Stream<String> _pollinations(Conversation conv) async* {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _system},
    ];
    for (final m in conv.messages) {
      if (m.role == Role.assistant && m.status != MsgStatus.complete) continue;
      final buf = StringBuffer();
      for (final a in m.attachments) {
        if (a.sentAsBinary) {
          buf.writeln('[ملف مرفق: ${a.name} — لا يمكن قراءته في الوضع المجاني بدون مفتاح؛ أخبر المستخدم بإضافة مفتاح Gemini المجاني من الإعدادات]');
        } else if (a.readable) {
          buf.writeln('[ملف مرفق: ${a.name} (${a.typeLabel})]\n${a.extractedText}\n[نهاية الملف]');
        }
      }
      buf.write(m.text);
      final role = m.role == Role.assistant ? 'assistant' : 'user';
      if (messages.last['role'] == role) {
        messages.last['content'] = '${messages.last['content']}\n\n$buf';
      } else {
        messages.add({'role': role, 'content': buf.toString()});
      }
    }
    final req = http.Request('POST', Uri.parse('https://text.pollinations.ai/openai'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'model': 'openai', 'messages': messages, 'stream': true});
    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(seconds: 90));
      if (res.statusCode >= 400) {
        final body = await res.stream.bytesToString();
        throw AiException(_friendly(res.statusCode, body));
      }
      if (!(res.headers['content-type'] ?? '').contains('event-stream')) {
        final raw = await res.stream.bytesToString();
        try {
          yield (jsonDecode(raw)['choices'][0]['message']['content'] as String?) ?? raw;
        } catch (_) {
          yield raw;
        }
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
          if (data == '[DONE]') return;
          try {
            final d = (jsonDecode(data)['choices'] as List?)?.firstOrNull?['delta']?['content'];
            if (d is String && d.isNotEmpty) yield d;
          } catch (_) {}
        }
      }
    } on TimeoutException {
      throw AiException('timeout');
    } on SocketException {
      throw AiException('offline');
    } on http.ClientException {
      throw AiException('network');
    } finally {
      client.close();
    }
  }

  String _friendly(int code, String body) {
    String msg = body;
    try {
      msg = (jsonDecode(body)['error']?['message'] as String?) ?? body;
    } catch (_) {}
    if (code == 400 && msg.contains('API key')) return 'badKey';
    if (code == 401 || code == 403) return 'badKey';
    if (code == 429) return 'rateLimited';
    if (msg.length > 300) msg = msg.substring(0, 300);
    return 'HTTP $code: $msg';
  }
}
