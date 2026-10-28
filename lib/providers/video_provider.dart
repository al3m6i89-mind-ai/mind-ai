import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/settings_service.dart';
import 'ai_models.dart';

/// Text-to-video. Kept behind one method so a paid backend can be dropped in
/// for subscribers without touching the UI.
class VideoProvider {
  VideoProvider(this.settings);

  final SettingsService settings;

  /// True when a real text-to-video backend is configured. Otherwise the app
  /// makes a free cinematic clip from a generated image on the phone.
  bool get hasRealProvider => switch (settings.videoBackend) {
        VideoBackend.pollinations => settings.pollinationsToken.isNotEmpty,
        VideoBackend.replicate => settings.replicateKey.isNotEmpty,
        VideoBackend.custom => settings.customVideoUrl.isNotEmpty,
      };

  Future<GeneratedVideo> generate(String prompt, {int seconds = 5}) async {
    try {
      return switch (settings.videoBackend) {
        VideoBackend.pollinations => await _pollinations(prompt, seconds),
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
      throw AiException(
        'فيديو Pollinations يحتاج رمزاً مجانياً من enter.pollinations.ai. أضفه من الإعدادات.',
      );
    }
    final uri = Uri.https('gen.pollinations.ai', '/image/${Uri.encodeComponent(prompt)}', {
      'model': 'seedance',
      'duration': '$seconds',
    });
    final res = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(minutes: 5));
    if (res.statusCode >= 400) {
      throw AiException('تعذّر إنشاء الفيديو (${res.statusCode}).');
    }
    return GeneratedVideo(bytes: res.bodyBytes);
  }

  Future<GeneratedVideo> _replicate(String prompt) async {
    final key = settings.replicateKey;
    if (key.isEmpty) throw AiException('أضف مفتاح Replicate من الإعدادات.');
    final headers = {
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
      'Prefer': 'wait=60',
    };
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
    final url = tpl
        .replaceAll('{prompt}', Uri.encodeComponent(prompt))
        .replaceAll('{seconds}', '$seconds');
    final res = await http.get(Uri.parse(url)).timeout(const Duration(minutes: 5));
    if (res.statusCode >= 400) throw AiException('تعذّر إنشاء الفيديو (${res.statusCode}).');
    if ((res.headers['content-type'] ?? '').contains('json')) {
      final j = jsonDecode(res.body);
      return GeneratedVideo(url: (j['url'] ?? j['output']) as String?);
    }
    return GeneratedVideo(bytes: res.bodyBytes);
  }
}
