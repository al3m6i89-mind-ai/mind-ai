import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mind_ai/services/build_service.dart';
import 'package:mind_ai/services/code_service.dart';
import 'package:mind_ai/services/media_tools.dart';

void main() {
  test('sticker removes white background and animates to GIF', () async {
    final src = img.Image(width: 300, height: 300);
    img.fill(src, color: img.ColorRgb8(255, 255, 255));
    img.fillCircle(src, x: 150, y: 150, radius: 80, color: img.ColorRgb8(255, 80, 160));
    final sticker = await MediaTools.makeSticker(img.encodeJpg(src));
    final decoded = img.decodePng(sticker)!;
    expect(decoded.width, 512);
    expect(decoded.getPixel(2, 2).a, 0); // corner is transparent
    expect(decoded.getPixel(256, 256).a, 255); // subject is kept

    for (final m in StickerMotion.values) {
      final gif = await MediaTools.animateSticker(sticker, m);
      final decoded = img.decodeGif(gif)!;
      expect(decoded.numFrames, 16, reason: m.name);
      // Corners stay see-through instead of turning black.
      expect(decoded.frames.first.getPixel(1, 1).a, 0, reason: m.name);
    }
    final kb = await MediaTools.kenBurns(img.encodeJpg(src));
    expect(img.decodeGif(kb)!.numFrames, 30);
    final kb5 = await MediaTools.kenBurns(img.encodeJpg(src), seconds: 5);
    expect(img.decodeGif(kb5)!.numFrames, 50);
  });

  test('cutout keeps size and clears a flat background', () async {
    final src = img.Image(width: 400, height: 300);
    img.fill(src, color: img.ColorRgb8(250, 250, 250));
    img.fillRect(src, x1: 120, y1: 80, x2: 280, y2: 220, color: img.ColorRgb8(220, 30, 30));
    final out = img.decodePng(await MediaTools.cutout(img.encodePng(src)))!;
    expect(out.width, 400);
    expect(out.getPixel(5, 5).a, 0);
    expect(out.getPixel(200, 150).a, 255);
  });

  test('web project is wrapped in a Flutter shell for APK builds', () {
    final p = CodeProject(
      id: 'abcdef123',
      name: 'Todo App',
      type: ProjectType.web,
      files: {'index.html': '<h1>hi</h1>'},
    );
    final tree = BuildService.buildTree(p);
    expect(tree['assets/www/index.html'], '<h1>hi</h1>');
    expect(tree['pubspec.yaml'], contains('name: todo_app'));
    expect(tree['pubspec.yaml'], contains('webview_flutter'));
    expect(tree.keys, contains('.github/workflows/mindai-build.yml'));
    expect(tree['lib/main.dart'], contains('loadFlutterAsset'));
  });
}
