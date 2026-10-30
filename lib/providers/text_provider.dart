import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/settings_service.dart';
import 'ai_models.dart';

/// One client for every text backend. Claude uses the native Anthropic Messages
/// API; every other backend speaks the OpenAI chat-completions format.
class TextProvider {
  TextProvider(this.settings);

  final SettingsService settings;

  /// Streams the assistant reply token by token. Falls back to a single
  /// non-streamed response when the backend does not stream.
  Stream<String> chat(List<ChatMessage> history, {String? system, TextBackend? backend}) async* {
    backend ??= settings.textBackend;
    final url = settings.textBaseUrl(backend);
    final key = settings.textKey(backend);
    if (url.isEmpty) throw AiException('لم يتم ضبط رابط المزوّد في الإعدادات.');
    if (backend.needsKey && key.isEmpty) {
      throw AiException('أضف مفتاح ${backend.label} من الإعدادات، أو اختر Pollinations المجاني.');
    }
    if (backend == TextBackend.anthropic) {
      yield* _claude(url, key, settings.textModel(backend), history, system);
      return;
    }
    if (backend == TextBackend.gemini) {
      yield* _gemini(key, settings.textModel(backend), history, system);
      return;
    }

    final messages = <Map<String, dynamic>>[
      if (system != null) {'role': 'system', 'content': system},
      for (final m in history) _encode(m),
    ];

    final body = jsonEncode({'model': settings.textModel(backend), 'messages': messages, 'stream': true});

    final req = http.Request('POST', Uri.parse(url))
      ..headers.addAll({
        'Content-Type': 'application/json',
        if (key.isNotEmpty) 'Authorization': 'Bearer $key',
        if (backend == TextBackend.openrouter) 'X-Title': 'Mind Ai',
        if (backend == TextBackend.pollinations && settings.pollinationsToken.isNotEmpty)
          'Authorization': 'Bearer ${settings.pollinationsToken}',
      })
      ..body = body;

    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(seconds: 90));
      if (res.statusCode >= 400) {
        final err = await res.stream.bytesToString();
        throw AiException(_friendlyError(res.statusCode, err));
      }
      final isSse = (res.headers['content-type'] ?? '').contains('event-stream');
      if (!isSse) {
        final raw = await res.stream.bytesToString();
        yield _extractFull(raw);
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
            final j = jsonDecode(data) as Map<String, dynamic>;
            final delta = (j['choices'] as List?)?.firstOrNull?['delta']?['content'];
            if (delta is String && delta.isNotEmpty) yield delta;
          } catch (_) {
            // Keep-alive or partial frame; ignore.
          }
        }
      }
    } on TimeoutException {
      throw AiException('انتهت مهلة الاتصال بالمزوّد. حاول مرة أخرى.');
    } finally {
      client.close();
    }
  }

  /// Claude Messages API with streaming and adaptive thinking. Only text deltas
  /// are shown; thinking deltas are skipped.
  Stream<String> _claude(String url, String key, String model, List<ChatMessage> history, String? system) async* {
    // The API wants alternating turns that start with the user.
    final messages = <Map<String, dynamic>>[];
    for (final m in history.where((m) => m.role != Role.system)) {
      final enc = _encodeClaude(m);
      if (messages.isNotEmpty && messages.last['role'] == enc['role']) {
        final prev = messages.removeLast();
        enc['content'] = [..._blocks(prev['content']), ..._blocks(enc['content'])];
      }
      messages.add(enc);
    }
    while (messages.isNotEmpty && messages.first['role'] != 'user') {
      messages.removeAt(0);
    }
    if (messages.isEmpty) return;

    final req = http.Request('POST', Uri.parse(url))
      ..headers.addAll({'Content-Type': 'application/json', 'x-api-key': key, 'anthropic-version': '2026-10-21'})
      ..body = jsonEncode({
        'model': model,
        'max_tokens': 32000,
        'stream': true,
        'thinking': {'type': 'adaptive'},
        if (system != null) 'system': system,
        'messages': messages,
      });

    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(seconds: 120));
      if (res.statusCode >= 400) {
        final err = await res.stream.bytesToString();
        throw AiException(_friendlyError(res.statusCode, _claudeError(err)));
      }
      var buffer = '';
      var any = false;
      await for (final chunk in res.stream.transform(utf8.decoder)) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();
        for (final line in lines) {
          final t = line.trim();
          if (!t.startsWith('data:')) continue;
          Map<String, dynamic> j;
          try {
            j = jsonDecode(t.substring(5).trim()) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
          switch (j['type']) {
            case 'content_block_delta':
              final d = j['delta'];
              if (d?['type'] == 'text_delta' && d['text'] is String) {
                any = true;
                yield d['text'] as String;
              }
            case 'message_delta':
              final stop = j['delta']?['stop_reason'];
              if (stop == 'refusal') {
                yield any
                    ? '\n\n_(توقف Claude عن إكمال هذا الطلب.)_'
                    : 'اعتذر Claude عن هذا الطلب. جرّب صياغة مختلفة أو بدّل المزوّد.';
              } else if (stop == 'max_tokens') {
                yield '\n\n_(وصل الرد للحد الأقصى من الطول.)_';
              }
            case 'error':
              throw AiException('خطأ من Claude: ${j['error']?['message'] ?? ''}');
          }
        }
      }
    } on TimeoutException {
      throw AiException('انتهت مهلة الاتصال بـ Claude. حاول مرة أخرى.');
    } finally {
      client.close();
    }
  }

  /// Native Gemini API (generateContent) with SSE streaming. The OpenAI-compat
  /// shim rejects some model names ("unexpected model name format"), so chat
  /// talks to the native endpoint directly, like image and voice already do.
  Stream<String> _gemini(String key, String model, List<ChatMessage> history, String? system) async* {
    // Accept "models/gemini-…", "gemini-…", or a stray full path; keep the id.
    var m = model.trim();
    if (m.contains('/')) m = m.split('/').last;
    if (m.isEmpty) m = 'gemini-2.5-flash';

    final contents = <Map<String, dynamic>>[];
    for (final msg in history.where((e) => e.role != Role.system)) {
      final role = msg.role == Role.assistant ? 'model' : 'user';
      final parts = <Map<String, dynamic>>[];
      if (msg.imageBytes != null) {
        parts.add({
          'inline_data': {'mime_type': _mime(msg.imageBytes!), 'data': base64Encode(msg.imageBytes!)},
        });
      }
      parts.add({'text': msg.text.isEmpty ? (msg.imageBytes != null ? 'صف هذه الصورة' : '…') : msg.text});
      if (contents.isNotEmpty && contents.last['role'] == role) {
        (contents.last['parts'] as List).addAll(parts);
      } else {
        contents.add({'role': role, 'parts': parts});
      }
    }
    while (contents.isNotEmpty && contents.first['role'] != 'user') {
      contents.removeAt(0);
    }
    if (contents.isEmpty) return;

    final url = 'https://generativelanguage.googleapis.com/v1beta/models/$m:streamGenerateContent?alt=sse';
    final req = http.Request('POST', Uri.parse(url))
      ..headers.addAll({'Content-Type': 'application/json', 'x-goog-api-key': key})
      ..body = jsonEncode({
        'contents': contents,
        if (system != null && system.trim().isNotEmpty)
          'systemInstruction': {
            'parts': [
              {'text': system},
            ],
          },
      });

    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(seconds: 90));
      if (res.statusCode >= 400) {
        final err = await res.stream.bytesToString();
        throw AiException(_friendlyError(res.statusCode, _claudeError(err)));
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
          if (data.isEmpty || data == '[DONE]') continue;
          try {
            final j = jsonDecode(data) as Map<String, dynamic>;
            final parts = (j['candidates'] as List?)?.firstOrNull?['content']?['parts'] as List?;
            if (parts != null) {
              for (final p in parts) {
                final text = p is Map ? p['text'] : null;
                if (text is String && text.isNotEmpty) yield text;
              }
            }
          } catch (_) {
            // Keep-alive or partial frame; ignore.
          }
        }
      }
    } on TimeoutException {
      throw AiException('انتهت مهلة الاتصال بـ Gemini. حاول مرة أخرى.');
    } finally {
      client.close();
    }
  }

  List<dynamic> _blocks(dynamic content) => content is List
      ? content
      : [
          {'type': 'text', 'text': content as String},
        ];

  Map<String, dynamic> _encodeClaude(ChatMessage m) {
    final role = m.role == Role.assistant ? 'assistant' : 'user';
    final text = m.text.isEmpty ? (m.imageBytes != null ? 'صف هذه الصورة' : '…') : m.text;
    if (m.imageBytes == null) return {'role': role, 'content': text};
    return {
      'role': role,
      'content': [
        {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': _mime(m.imageBytes!), 'data': base64Encode(m.imageBytes!)},
        },
        {'type': 'text', 'text': text},
      ],
    };
  }

  String _mime(List<int> b) {
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'image/gif';
    if (b.length > 11 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
    return 'image/jpeg';
  }

  String _claudeError(String body) {
    try {
      return (jsonDecode(body)['error']?['message'] as String?) ?? body;
    } catch (_) {
      return body;
    }
  }

  /// Convenience: whole reply as one string.
  Future<String> complete(List<ChatMessage> history, {String? system, TextBackend? backend}) async {
    final sb = StringBuffer();
    await for (final t in chat(history, system: system, backend: backend)) {
      sb.write(t);
    }
    return sb.toString();
  }

  Map<String, dynamic> _encode(ChatMessage m) {
    final role = m.role.name;
    if (m.imageBytes == null) return {'role': role, 'content': m.text};
    return {
      'role': role,
      'content': [
        {'type': 'text', 'text': m.text.isEmpty ? 'صف هذه الصورة' : m.text},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:${_mime(m.imageBytes!)};base64,${base64Encode(m.imageBytes!)}'},
        },
      ],
    };
  }

  String _extractFull(String raw) {
    try {
      final j = jsonDecode(raw);
      final c = j['choices']?[0]?['message']?['content'];
      if (c is String) return c;
    } catch (_) {}
    return raw;
  }

  String _friendlyError(int code, String body) {
    if (code == 401 || code == 403) return 'المفتاح غير صحيح أو منتهي. راجع الإعدادات.';
    if (code == 429) return 'تم تجاوز الحد المجاني لهذا المزوّد مؤقتاً. انتظر قليلاً أو بدّل المزوّد.';
    final short = body.length > 200 ? body.substring(0, 200) : body;
    return 'خطأ من المزوّد ($code): $short';
  }
}
