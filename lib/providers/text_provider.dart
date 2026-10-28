import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/settings_service.dart';
import 'ai_models.dart';

/// One client for every text backend: all of them speak the OpenAI chat-completions format.
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

    final messages = <Map<String, dynamic>>[
      if (system != null) {'role': 'system', 'content': system},
      for (final m in history) _encode(m),
    ];

    final body = jsonEncode({
      'model': settings.textModel(backend),
      'messages': messages,
      'stream': true,
    });

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
          'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(m.imageBytes!)}'},
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
