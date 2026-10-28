import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mind_ai/services/gift_maker.dart';

void main() {
  final art = img.Image(width: 512, height: 512, numChannels: 4);
  img.fill(art, color: img.ColorRgba8(0, 0, 0, 0));
  img.fillCircle(art, x: 256, y: 256, radius: 150, color: img.ColorRgba8(230, 40, 80, 255));
  final png = img.encodePng(art);

  for (final e in GiftEffect.values) {
    test('gift ${e.name} renders a transparent GIF and a valid Lottie', () async {
      final gif = await GiftMaker.gif(png, e);
      final anim = img.decodeGif(gif)!;
      expect(anim.numFrames, 42);
      expect(anim.frames[20].getPixel(2, 2).a, 0);
      final dump = Platform.environment['GIFT_DUMP'];
      if (dump != null) {
        for (final f in [6, 14, 24, 34]) {
          File('$dump/${e.name}_$f.png').writeAsBytesSync(img.encodePng(anim.frames[f]));
        }
      }

      final j = jsonDecode(await GiftMaker.lottie(png, e)) as Map<String, dynamic>;
      expect(j['w'], 512);
      expect((j['assets'] as List).single['p'], startsWith('data:image/png;base64,'));
      expect((j['layers'] as List).last['ty'], 2);
    });
  }

  test('green screen frames are keyed to a transparent GIF and PNG zip', () async {
    final frames = [
      for (var i = 0; i < 6; i++)
        () {
          final f = img.Image(width: 400, height: 300);
          img.fill(f, color: img.ColorRgb8(10, 240, 20));
          img.fillCircle(f, x: 150 + i * 10, y: 150, radius: 70, color: img.ColorRgb8(240, 190, 40));
          return img.encodePng(f);
        }(),
    ];
    final (gif, zip) = await GiftMaker.keyFrames(frames, effect: GiftEffect.royal);
    final anim = img.decodeGif(gif)!;
    expect(anim.numFrames, 6);
    expect(anim.frames.first.getPixel(1, 1).a, 0);
    expect(anim.frames.first.getPixel(256, 256).a, 255);
    expect(zip.sublist(0, 2), [0x50, 0x4B]); // "PK"
  });
}
