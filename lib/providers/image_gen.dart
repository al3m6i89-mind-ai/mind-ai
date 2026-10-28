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

  /// True when a model that can redraw a given picture is configured.
  bool get canEdit => settings.arkKey.isNotEmpty || settings.textKey(TextBackend.gemini).isNotEmpty;

  Future<GeneratedImage> generate(
    String prompt, {
    int width = 1024,
    int height = 1024,
    int? seed,
    Uint8List? reference,
    String? model,
    ImageBackend? backend,
  }) async {
    seed ??= Random().nextInt(1 << 31);
    try {
      final bytes = switch (backend ?? settings.imageBackend) {
        ImageBackend.pollinations => await _pollinations(prompt, width, height, seed, model, reference),
        ImageBackend.cloudflare =>
          reference != null && canEdit
              ? await _pollinations(prompt, width, height, seed, model, reference)
              : await _cloudflare(prompt, seed),
        ImageBackend.seedream => await _seedream(prompt, width, height, seed, reference),
        ImageBackend.huggingface =>
          reference != null && canEdit
              ? await _pollinations(prompt, width, height, seed, model, reference)
              : await _huggingFace(prompt, width, height, seed),
        ImageBackend.gemini => await _gemini(prompt, reference),
        ImageBackend.custom => await _custom(prompt, width, height, seed),
      };
      return GeneratedImage(bytes, prompt: prompt);
    } on TimeoutException {
      throw AiException('استغرق إنشاء الصورة وقتاً طويلاً. حاول مرة أخرى.');
    }
  }

  Future<Uint8List> _pollinations(String prompt, int w, int h, int seed, String? model, Uint8List? reference) async {
    // Pollinations accepts a reference image only by URL, so editing a local photo
    // goes to Seedream or Gemini when a key exists.
    if (reference != null && settings.arkKey.isNotEmpty) {
      return _seedream(prompt, w, h, seed, reference);
    }
    if (reference != null && settings.textKey(TextBackend.gemini).isNotEmpty) {
      return _gemini(prompt, reference);
    }
    // The free tier is busy at peak times (402/429/503) and big sizes fail first,
    // so cap the size and retry with backoff, then with the faster model.
    final scale = min(1.0, 1024 / max(w, h));
    final ww = (w * scale).round(), hh = (h * scale).round();
    final token = settings.pollinationsToken;
    final first = model ?? settings.imageModel;
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      final params = {
        'width': '$ww',
        'height': '$hh',
        'seed': '${seed + attempt}',
        'nologo': 'true',
        'private': 'true',
        // Their prompt rewriter drifts from what the user asked for, so keep it off.
        'enhance': 'false',
        'model': attempt < 2 ? first : 'turbo',
        if (token.isNotEmpty) 'token': token,
      };
      final uri = Uri.https('image.pollinations.ai', '/prompt/${Uri.encodeComponent(prompt)}', params);
      try {
        final res = await http.get(uri).timeout(const Duration(seconds: 120));
        if (const {402, 429, 500, 502, 503, 504}.contains(res.statusCode)) {
          lastError = AiException('الخادم المجاني مشغول الآن (${res.statusCode}).');
        } else {
          _check(res);
          return res.bodyBytes;
        }
      } on TimeoutException catch (e) {
        lastError = e;
      }
      await Future<void>.delayed(Duration(seconds: 3 + attempt * 4));
    }
    if (lastError is AiException) {
      throw AiException('${lastError.message} حاول بعد دقيقة، أو أضف مفتاح Seedream/Gemini من الإعدادات لنتائج أقوى.');
    }
    throw AiException('الخادم المجاني لا يرد الآن. حاول بعد دقيقة.');
  }

  /// Seedream on BytePlus ModelArk. Takes an optional reference photo for edits.
  Future<Uint8List> _seedream(String prompt, int w, int h, int seed, Uint8List? reference) async {
    final key = settings.arkKey;
    if (key.isEmpty) {
      throw AiException('أضف مفتاح BytePlus ModelArk من الإعدادات لاستخدام Seedream.');
    }
    // Seedream wants at least ~1280x720 pixels; scale small requests up.
    final grow = max(1.0, sqrt(1280 * 720 / (w * h)));
    final ww = (w * grow / 8).ceil() * 8, hh = (h * grow / 8).ceil() * 8;
    final res = await http
        .post(
          Uri.parse('${settings.arkBaseUrl}/images/generations'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $key'},
          body: jsonEncode({
            'model': settings.seedreamModel,
            'prompt': prompt,
            'size': '${ww}x$hh',
            'seed': seed % 2147483647,
            'response_format': 'b64_json',
            'watermark': false,
            if (reference != null) 'image': 'data:image/jpeg;base64,${base64Encode(reference)}',
          }),
        )
        .timeout(const Duration(seconds: 180));
    if (res.statusCode >= 400) throw AiException(arkError('Seedream', res));
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final item = (j['data'] as List?)?.firstOrNull as Map<String, dynamic>?;
    final b64 = item?['b64_json'];
    if (b64 is String) return base64Decode(b64);
    final url = item?['url'];
    if (url is String) return http.readBytes(Uri.parse(url));
    throw AiException('لم يرجع Seedream صورة. جرّب وصفاً مختلفاً.');
  }

  /// Cloudflare Workers AI, FLUX.1 schnell (free daily allowance).
  Future<Uint8List> _cloudflare(String prompt, int seed) async {
    final id = settings.cfAccountId, token = settings.cfToken;
    if (id.isEmpty || token.isEmpty) throw AiException('أضف رقم حساب Cloudflare ورمزه من الإعدادات.');
    final res = await http
        .post(
          Uri.parse('https://api.cloudflare.com/client/v4/accounts/$id/ai/run/@cf/black-forest-labs/flux-1-schnell'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: jsonEncode({'prompt': prompt, 'steps': 8, 'seed': seed % 2147483647}),
        )
        .timeout(const Duration(seconds: 120));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw AiException('رمز Cloudflare غير صحيح، أو ما فيه صلاحية Workers AI.');
    }
    if (res.statusCode == 429) throw AiException('خلص رصيد Cloudflare المجاني لليوم. جرّب أداة ثانية.');
    if (res.statusCode >= 400) throw AiException('Cloudflare (${res.statusCode}).');
    final image = (jsonDecode(res.body) as Map<String, dynamic>)['result']?['image'];
    if (image is! String) throw AiException('لم يرجع Cloudflare صورة.');
    return base64Decode(image);
  }

  /// Hugging Face Inference (free token from huggingface.co/settings/tokens).
  Future<Uint8List> _huggingFace(String prompt, int w, int h, int seed) async {
    final token = settings.hfToken;
    if (token.isEmpty) throw AiException('أضف رمز Hugging Face المجاني من الإعدادات.');
    final scale = min(1.0, 1024 / max(w, h));
    for (var attempt = 0; attempt < 3; attempt++) {
      final res = await http
          .post(
            Uri.parse('https://router.huggingface.co/hf-inference/models/${settings.hfImageModel}'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token', 'Accept': 'image/png'},
            body: jsonEncode({
              'inputs': prompt,
              'parameters': {
                'width': (w * scale / 16).round() * 16,
                'height': (h * scale / 16).round() * 16,
                'seed': seed % 2147483647,
              },
            }),
          )
          .timeout(const Duration(seconds: 150));
      // 503 means the model is waking up; it is ready a few seconds later.
      if (res.statusCode == 503 && attempt < 2) {
        await Future<void>.delayed(const Duration(seconds: 8));
        continue;
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw AiException('رمز Hugging Face غير صحيح أو بدون صلاحية Inference Providers.');
      }
      if (res.statusCode == 402) throw AiException('انتهى رصيد Hugging Face المجاني لهذا الشهر.');
      if (res.statusCode >= 400) {
        throw AiException('Hugging Face (${res.statusCode}): ${res.body.substring(0, min(160, res.body.length))}');
      }
      return res.bodyBytes;
    }
    throw AiException('موديل Hugging Face مشغول الآن. حاول بعد دقيقة.');
  }

  /// Human-readable error for a BytePlus ModelArk response.
  static String arkError(String what, http.Response res) {
    String msg = '';
    try {
      msg = (jsonDecode(res.body)['error']?['message'] as String?) ?? '';
    } catch (_) {}
    if (res.statusCode == 401 || res.statusCode == 403) {
      return '$what: المفتاح غير صحيح، أو لم تفعّل هذا الموديل في BytePlus ModelArk.';
    }
    if (res.statusCode == 404) {
      return '$what: اسم الموديل غير موجود. انسخ Model ID أو Endpoint ID من لوحة ModelArk إلى الإعدادات.';
    }
    if (res.statusCode == 429) return '$what: تجاوزت الحد أو الرصيد. راجع حسابك في BytePlus.';
    return '$what (${res.statusCode}): ${msg.isEmpty ? res.body.substring(0, min(160, res.body.length)) : msg}';
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
