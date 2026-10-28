import 'dart:async';
import 'dart:convert';

import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../services/settings_service.dart';
import 'ai_models.dart';
import 'image_gen.dart';

/// Text-to-video. Kept behind one method so a paid backend can be dropped in
/// for subscribers without touching the UI.
class VideoProvider {
  VideoProvider(this.settings);

  final SettingsService settings;

  /// True when a real text-to-video backend is configured. Otherwise the app
  /// makes a free cinematic clip from a generated image on the phone.
  bool get hasRealProvider => isReady(settings.videoBackend);

  bool isReady(VideoBackend b) => switch (b) {
    VideoBackend.pollinations => settings.pollinationsToken.isNotEmpty,
    VideoBackend.huggingface => settings.hfToken.isNotEmpty,
    VideoBackend.seedance => settings.arkKey.isNotEmpty,
    VideoBackend.replicate => settings.replicateKey.isNotEmpty,
    VideoBackend.custom => settings.customVideoUrl.isNotEmpty,
  };

  Future<GeneratedVideo> generate(String prompt, {int seconds = 5, Uint8List? image, VideoBackend? backend}) async {
    try {
      return switch (backend ?? settings.videoBackend) {
        VideoBackend.huggingface => await _huggingFace(prompt, image),
        VideoBackend.pollinations => await _pollinations(prompt, seconds),
        VideoBackend.seedance => await _seedance(prompt, seconds, image),
        VideoBackend.replicate => await _replicate(prompt),
        VideoBackend.custom => await _custom(prompt, seconds),
      };
    } on TimeoutException {
      throw AiException('توليد الفيديو أخذ وقتاً أطول من المتوقع. حاول لاحقاً.');
    }
  }

  Future<GeneratedVideo> _pollinations(String prompt, int seconds) async {
    final token = settings.pollinationsToken;
    if (token.isEmpty) {
      throw AiException('فيديو Pollinations يحتاج رمزاً مجانياً من enter.pollinations.ai. أضفه من الإعدادات.');
    }
    final uri = Uri.https('gen.pollinations.ai', '/image/${Uri.encodeComponent(prompt)}', {
      'model': 'seedance',
      'duration': '$seconds',
    });
    final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(minutes: 5));
    if (res.statusCode >= 400) {
      throw AiException('تعذّر إنشاء الفيديو (${res.statusCode}).');
    }
    return GeneratedVideo(bytes: res.bodyBytes);
  }

  /// Hugging Face Inference Providers, routed to fal-ai video models.
  Future<GeneratedVideo> _huggingFace(String prompt, Uint8List? image) async {
    final token = settings.hfToken;
    if (token.isEmpty) throw AiException('أضف رمز Hugging Face من الإعدادات.');
    final res = await http
        .post(
          Uri.parse('https://router.huggingface.co/fal-ai/${settings.hfVideoModel}'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: jsonEncode({
            'prompt': prompt,
            if (image != null) 'image_url': 'data:image/jpeg;base64,${base64Encode(image)}',
          }),
        )
        .timeout(const Duration(minutes: 6));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw AiException('رمز Hugging Face غير صحيح أو بدون صلاحية Inference Providers.');
    }
    if (res.statusCode == 402) throw AiException('الفيديو في Hugging Face يحتاج رصيد. اشحن حسابك أو اختر أداة أخرى.');
    if (res.statusCode >= 400) throw AiException('Hugging Face (${res.statusCode}): ${_short(res.body)}');
    if ((res.headers['content-type'] ?? '').startsWith('video/')) return GeneratedVideo(bytes: res.bodyBytes);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final url = j['video']?['url'] ?? j['url'];
    if (url is! String) throw AiException('لم يرجع Hugging Face فيديو.');
    return GeneratedVideo(url: url);
  }

  static String _short(String s) => s.length > 160 ? s.substring(0, 160) : s;

  /// Seedance on BytePlus ModelArk: create a task, then poll until the clip is ready.
  Future<GeneratedVideo> _seedance(String prompt, int seconds, Uint8List? image) async {
    final key = settings.arkKey;
    if (key.isEmpty) throw AiException('أضف مفتاح BytePlus ModelArk من الإعدادات لاستخدام Seedance.');
    final base = settings.arkBaseUrl;
    final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $key'};
    final dur = seconds <= 5 ? 5 : 10;
    var res = await http
        .post(
          Uri.parse('$base/contents/generations/tasks'),
          headers: headers,
          body: jsonEncode({
            'model': settings.seedanceModel,
            'content': [
              {
                'type': 'text',
                'text': '$prompt --duration $dur ${image == null ? '--ratio 16:9 ' : ''}--watermark false',
              },
              if (image != null)
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(image)}'},
                },
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode >= 400) throw AiException(ImageGen.arkError('Seedance', res));
    final id = (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    while (true) {
      await Future<void>.delayed(const Duration(seconds: 5));
      if (DateTime.now().isAfter(deadline)) throw TimeoutException('video');
      res = await http.get(Uri.parse('$base/contents/generations/tasks/$id'), headers: headers);
      if (res.statusCode >= 400) throw AiException(ImageGen.arkError('Seedance', res));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      switch (j['status']) {
        case 'succeeded':
          final url = j['content']?['video_url'] as String?;
          if (url == null) throw AiException('Seedance لم يرجع رابط الفيديو.');
          return GeneratedVideo(url: url);
        case 'failed' || 'cancelled' || 'canceled':
          throw AiException('فشل توليد الفيديو: ${j['error']?['message'] ?? ''}');
      }
    }
  }

  Future<GeneratedVideo> _replicate(String prompt) async {
    final key = settings.replicateKey;
    if (key.isEmpty) throw AiException('أضف مفتاح Replicate من الإعدادات.');
    final headers = {'Authorization': 'Bearer $key', 'Content-Type': 'application/json', 'Prefer': 'wait=60'};
    final model = settings.replicateVideoModel;
    var res = await http
        .post(
          Uri.parse('https://api.replicate.com/v1/models/$model/predictions'),
          headers: headers,
          body: jsonEncode({
            'input': {'prompt': prompt},
          }),
        )
        .timeout(const Duration(seconds: 90));
    if (res.statusCode >= 400) throw AiException('Replicate: ${res.statusCode} ${res.body}');
    var j = jsonDecode(res.body) as Map<String, dynamic>;
    final deadline = DateTime.now().add(const Duration(minutes: 8));
    while (j['status'] != 'succeeded') {
      if (j['status'] == 'failed' || j['status'] == 'canceled') {
        throw AiException('فشل توليد الفيديو: ${j['error'] ?? ''}');
      }
      if (DateTime.now().isAfter(deadline)) throw TimeoutException('video');
      await Future<void>.delayed(const Duration(seconds: 4));
      res = await http.get(Uri.parse(j['urls']['get'] as String), headers: headers);
      j = jsonDecode(res.body) as Map<String, dynamic>;
    }
    final out = j['output'];
    final url = out is List ? out.first as String : out as String;
    return GeneratedVideo(url: url);
  }

  Future<GeneratedVideo> _custom(String prompt, int seconds) async {
    final tpl = settings.customVideoUrl;
    if (tpl.isEmpty) throw AiException('أضف رابط مزوّد الفيديو من الإعدادات.');
    final url = tpl.replaceAll('{prompt}', Uri.encodeComponent(prompt)).replaceAll('{seconds}', '$seconds');
    final res = await http.get(Uri.parse(url)).timeout(const Duration(minutes: 5));
    if (res.statusCode >= 400) throw AiException('تعذّر إنشاء الفيديو (${res.statusCode}).');
    if ((res.headers['content-type'] ?? '').contains('json')) {
      final j = jsonDecode(res.body);
      return GeneratedVideo(url: (j['url'] ?? j['output']) as String?);
    }
    return GeneratedVideo(bytes: res.bodyBytes);
  }
}
