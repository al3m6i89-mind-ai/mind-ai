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
You are the assistant of a file and image analysis app. Reply in the language the user writes in (Arabic or English), directly and without filler.

When files or images are attached to the conversation:
- Answer ONLY from their content. Never invent or guess.
- If the answer is not in the files, say exactly: "لم أجد هذه المعلومة في الملفات التي رفعتها، لذلك لا أستطيع تأكيد الإجابة." (or the English equivalent if the user writes English).
- Mark what is stated explicitly versus what you infer from the content. If the files are unclear or contradict each other, say so.
- After each answer that uses a file, add a short "المصدر / Source" line with the file name and, when known for certain, the page (PDF), slide number (PowerPoint), sheet and cell (Excel) or section heading (Word). Never give a page number you are not sure of.
When nothing is attached, answer normally as a helpful assistant.
''';

/// Streams a reply. Gemini reads PDFs and images itself; extracted text from
/// Word, Excel and PowerPoint is sent as text.
class AiClient {
  AiClient({required this.provider, required this.geminiKey, this.model = 'gemini-2.5-flash'});

  final Provider provider;
  final String geminiKey;
  final String model;

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
    final url = 'https://generativelanguage.googleapis.com/v1beta/models/$model:streamGenerateContent?alt=sse';
    final req = http.Request('POST', Uri.parse(url))
      ..headers.addAll({'Content-Type': 'application/json', 'x-goog-api-key': geminiKey.trim()})
      ..body = jsonEncode({
        'contents': contents,
        'systemInstruction': {
          'parts': [
            {'text': _system},
          ],
        },
      });
    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(seconds: 120));
      if (res.statusCode >= 400) {
        final body = await res.stream.bytesToString();
        throw AiException(_friendly(res.statusCode, body));
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
    } finally {
      client.close();
    }
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
