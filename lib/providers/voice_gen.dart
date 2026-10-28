import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import '../services/settings_service.dart';
import 'ai_models.dart';

/// A voice the user can pick. [gemini] is the Gemini TTS voice name.
class VoiceOption {
  const VoiceOption(this.gemini, this.label);
  final String gemini;
  final String label;

  static const all = [
    VoiceOption('Kore', 'كورا · أنثى واضحة'),
    VoiceOption('Aoede', 'إيدا · أنثى ناعمة'),
    VoiceOption('Leda', 'ليدا · أنثى شابة'),
    VoiceOption('Charon', 'شارون · رجل رخيم'),
    VoiceOption('Puck', 'باك · رجل مرح'),
    VoiceOption('Fenrir', 'فنرير · رجل حماسي'),
    VoiceOption('Orus', 'أوروس · رجل هادئ'),
  ];
}

/// Text to speech. With a Gemini key it makes a natural AI voice as a WAV file;
/// without one it speaks with the phone's own free voice.
class VoiceGen {
  VoiceGen(this.settings);

  final SettingsService settings;
  final FlutterTts _tts = FlutterTts();

  bool get hasAiVoice => settings.textKey(TextBackend.gemini).isNotEmpty;

  /// [style] is a plain-language direction such as "بحماس" or "كراوي قصص".
  Future<Uint8List> synthesize(String text, VoiceOption voice, {String style = ''}) async {
    final key = settings.textKey(TextBackend.gemini);
    if (key.isEmpty) throw AiException('الصوت الذكي يحتاج مفتاح Gemini المجاني من الإعدادات.');
    final prompt = style.isEmpty ? text : 'Say $style: $text';
    final res = await http
        .post(
          Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent',
          ),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': key},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
            'generationConfig': {
              'responseModalities': ['AUDIO'],
              'speechConfig': {
                'voiceConfig': {
                  'prebuiltVoiceConfig': {'voiceName': voice.gemini},
                },
              },
            },
          }),
        )
        .timeout(const Duration(seconds: 120));
    if (res.statusCode == 429) throw AiException('الحد المجاني لـ Gemini ممتلئ مؤقتاً. انتظر دقيقة.');
    if (res.statusCode >= 400) throw AiException('تعذّر إنشاء الصوت (${res.statusCode}).');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    for (final c in (j['candidates'] as List? ?? const [])) {
      for (final p in (c['content']?['parts'] as List? ?? const [])) {
        final data = (p['inlineData'] ?? p['inline_data'])?['data'];
        if (data is String) return pcmToWav(base64Decode(data));
      }
    }
    throw AiException('لم يرجع Gemini صوتاً. جرّب نصاً آخر.');
  }

  /// Free on-device voice. Only plays; it does not make a file.
  Future<void> speakOnDevice(String text, {double rate = 0.5, double pitch = 1.0}) async {
    final arabic = RegExp(r'[؀-ۿ]').hasMatch(text);
    await _tts.setLanguage(arabic ? 'ar' : 'en-US');
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(pitch);
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();

  /// Gemini returns raw 16-bit mono PCM at 24 kHz; players need a WAV header.
  static Uint8List pcmToWav(Uint8List pcm, {int sampleRate = 24000}) {
    final h = ByteData(44);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        h.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    h.setUint32(4, 36 + pcm.length, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little);
    h.setUint16(22, 1, Endian.little);
    h.setUint32(24, sampleRate, Endian.little);
    h.setUint32(28, sampleRate * 2, Endian.little);
    h.setUint16(32, 2, Endian.little);
    h.setUint16(34, 16, Endian.little);
    str(36, 'data');
    h.setUint32(40, pcm.length, Endian.little);
    return Uint8List.fromList([...h.buffer.asUint8List(), ...pcm]);
  }
}
