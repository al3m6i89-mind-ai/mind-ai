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
      expect(img.decodeGif(gif)!.numFrames, 16, reason: m.name);
    }
    final kb = await MediaTools.kenBurns(img.encodeJpg(src));
    expect(img.decodeGif(kb)!.numFrames, 30);
  });

  test('web project is wrapped in a Flutter shell for APK builds', () {
    final p = CodeProject(id: 'abcdef123', name: 'Todo App', type: ProjectType.web, files: {'index.html': '<h1>hi</h1>'});
    final tree = BuildService.buildTree(p);
    expect(tree['assets/www/index.html'], '<h1>hi</h1>');
    expect(tree['pubspec.yaml'], contains('name: todo_app'));
    expect(tree['pubspec.yaml'], contains('webview_flutter'));
    expect(tree.keys, contains('.github/workflows/mindai-build.yml'));
    expect(tree['lib/main.dart'], contains('loadFlutterAsset'));
  });
}
