import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mind_ai/providers/tools.dart';
import 'package:mind_ai/providers/voice_gen.dart';
import 'package:mind_ai/services/media_tools.dart';
import 'package:mind_ai/services/settings_service.dart';
import 'package:mind_ai/services/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('points are charged per tool and run out', () async {
    SharedPreferences.setMockInitialValues({});
    final subs = SubscriptionService(await SharedPreferences.getInstance());
    expect(subs.pointsLeft, 0);
    expect(await subs.grantWelcome(), isTrue);
    expect(await subs.grantWelcome(), isFalse); // only once
    expect(subs.pointsLeft, SubscriptionService.welcomePoints);
    subs.ensure(Usage.video, points: 40);
    await subs.consume(Usage.video, points: 40);
    expect(subs.pointsLeft, SubscriptionService.welcomePoints - 40);
    expect(() => subs.ensure(Usage.image, points: 1000), throwsA(isA<NotEnoughPoints>()));
  });

  test('keyless tools are unlocked, keyed tools need a key', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsService(await SharedPreferences.getInstance());
    expect(ImageTool.byId('flux').available(s), isTrue);
    expect(ImageTool.byId('seedream').available(s), isFalse);
    expect(VideoTool.byId('free').available(s), isTrue);
    expect(VideoTool.byId('hf').available(s), isFalse);
    await s.setHfToken('hf_x');
    expect(VideoTool.byId('hf').available(s), isTrue);
    await s.setTextKey(TextBackend.gemini, 'k');
    expect(s.textBackend, TextBackend.gemini);
    expect(s.bestTextBackend, TextBackend.gemini);
    await s.setTextKey(TextBackend.anthropic, 'k');
    expect(s.bestTextBackend, TextBackend.anthropic);
  });

  test('PCM from Gemini TTS becomes a valid WAV', () {
    final wav = VoiceGen.pcmToWav(Uint8List(4800));
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(wav.length, 44 + 4800);
  });

  test('pose animation keeps a transparent background', () async {
    Uint8List pose(int x) {
      final im = img.Image(width: 512, height: 512, numChannels: 4);
      img.fillRect(im, x1: x, y1: 150, x2: x + 150, y2: 350, color: img.ColorRgba8(30, 120, 220, 255));
      return Uint8List.fromList(img.encodePng(im));
    }

    final gif = await MediaTools.animatePoses([pose(100), pose(180), pose(260)]);
    final anim = img.decodeGif(gif)!;
    expect(anim.numFrames, greaterThan(4));
    expect(anim.frames.first.getPixel(2, 2).a, 0);
  });
}
