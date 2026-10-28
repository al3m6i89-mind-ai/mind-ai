import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../services/settings_service.dart';
import 'ai_models.dart';

/// Ready-made styles used across the studio. Each adds a prompt suffix.
class ImageStyle {
  const ImageStyle(this.id, this.label, this.suffix, this.emoji);
  final String id;
  final String label;
  final String suffix;
  final String emoji;

  static const all = [
    ImageStyle('none', 'بدون', '', '✨'),
    ImageStyle('real', 'واقعي', 'photorealistic, 8k, sharp focus, natural light', '📷'),
    ImageStyle('anime', 'أنمي', 'anime style, vibrant colors, studio quality', '🌸'),
    ImageStyle('3d', 'ثلاثي الأبعاد', '3d render, pixar style, soft lighting, cute', '🧸'),
    ImageStyle('cartoon', 'كرتون', 'cartoon illustration, bold outlines, flat colors', '🎨'),
    ImageStyle('oil', 'زيتي', 'oil painting, rich brush strokes, artistic', '🖼️'),
    ImageStyle('cyber', 'سايبر', 'cyberpunk, neon lights, futuristic', '🌃'),
    ImageStyle('logo', 'شعار', 'minimal vector logo, flat, centered, white background', '🔷'),
  ];
}

class ImageGen {
  ImageGen(this.settings);

  final SettingsService settings;

  Future<GeneratedImage> generate(
    String prompt, {
    int width = 1024,
    int height = 1024,
    int? seed,
    Uint8List? reference,
    String? model,
  }) async {
    seed ??= Random().nextInt(1 << 31);
    try {
      final bytes = switch (settings.imageBackend) {
        ImageBackend.pollinations =>
          await _pollinations(prompt, width, height, seed, model, reference),
        ImageBackend.gemini => await _gemini(prompt, reference),
        ImageBackend.custom => await _custom(prompt, width, height, seed),
      };
      return GeneratedImage(bytes, prompt: prompt);
    } on TimeoutException {
      throw AiException('استغرق إنشاء الصورة وقتاً طويلاً. حاول مرة أخرى.');
    }
  }

  Future<Uint8List> _pollinations(
    String prompt,
    int w,
    int h,
    int seed,
    String? model,
    Uint8List? reference,
  ) async {
    final token = settings.pollinationsToken;
    final params = {
      'width': '$w',
      'height': '$h',
      'seed': '$seed',
      'nologo': 'true',
      'enhance': 'true',
      'model': model ?? settings.imageModel,
      if (token.isNotEmpty) 'token': token,
    };
    // Pollinations accepts a reference image only by URL, so editing a local photo
    // needs Gemini. Without a reference this is a plain text-to-image call.
    if (reference != null && settings.textKey(TextBackend.gemini).isNotEmpty) {
      return _gemini(prompt, reference);
    }
    final uri = Uri.https(
      'image.pollinations.ai',
      '/prompt/${Uri.encodeComponent(prompt)}',
      params,
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 120));
    _check(res);
    return res.bodyBytes;
  }

  Future<Uint8List> _gemini(String prompt, Uint8List? reference) async {
    final key = settings.textKey(TextBackend.gemini);
    if (key.isEmpty) {
      throw AiException('أضف مفتاح Gemini المجاني من الإعدادات لاستخدام هذه الميزة.');
    }
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent',
    );
    final parts = <Map<String, dynamic>>[
      {'text': prompt},
      if (reference != null)
        {
          'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(reference)},
        },
    ];
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': key},
          body: jsonEncode({
            'contents': [
              {'parts': parts},
            ],
            'generationConfig': {
              'responseModalities': ['IMAGE', 'TEXT'],
            },
          }),
        )
        .timeout(const Duration(seconds: 120));
    _check(res);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final candidates = j['candidates'] as List? ?? const [];
    for (final c in candidates) {
      for (final p in (c['content']?['parts'] as List? ?? const [])) {
        final data = (p['inlineData'] ?? p['inline_data'])?['data'];
        if (data is String) return base64Decode(data);
      }
    }
    throw AiException('لم يرجع Gemini صورة. جرّب وصفاً مختلفاً.');
  }

  Future<Uint8List> _custom(String prompt, int w, int h, int seed) async {
    final tpl = settings.customImageUrl;
    if (tpl.isEmpty) throw AiException('أضف رابط مزوّد الصور المخصص من الإعدادات.');
    final url = tpl
        .replaceAll('{prompt}', Uri.encodeComponent(prompt))
        .replaceAll('{width}', '$w')
        .replaceAll('{height}', '$h')
        .replaceAll('{seed}', '$seed');
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 120));
    _check(res);
    return res.bodyBytes;
  }

  void _check(http.Response res) {
    if (res.statusCode == 429) {
      throw AiException('الحد المجاني للمزوّد ممتلئ مؤقتاً. انتظر دقيقة ثم أعد المحاولة.');
    }
    if (res.statusCode >= 400) {
      throw AiException('تعذّر إنشاء الصورة (${res.statusCode}).');
    }
    final type = res.headers['content-type'] ?? '';
    if (type.contains('json') && !res.request!.url.host.contains('googleapis')) {
      throw AiException('رد غير متوقع من المزوّد: ${res.body.substring(0, min(160, res.body.length))}');
    }
  }
}
