import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Motion presets for animated stickers. Everything is rendered on the phone,
/// so animated stickers cost nothing and work offline once the base image exists.
enum StickerMotion { bounce, wiggle, pulse, spin, float, shake, heartbeat, swing }

extension StickerMotionInfo on StickerMotion {
  String get label => switch (this) {
    StickerMotion.bounce => 'نطّ',
    StickerMotion.wiggle => 'تمايل',
    StickerMotion.pulse => 'نبض',
    StickerMotion.spin => 'دوران',
    StickerMotion.float => 'طفو',
    StickerMotion.shake => 'اهتزاز',
    StickerMotion.heartbeat => 'قلب',
    StickerMotion.swing => 'أرجحة',
  };

  String get emoji => switch (this) {
    StickerMotion.bounce => '🏀',
    StickerMotion.wiggle => '〰️',
    StickerMotion.pulse => '💫',
    StickerMotion.spin => '🌀',
    StickerMotion.float => '🎈',
    StickerMotion.shake => '📳',
    StickerMotion.heartbeat => '💓',
    StickerMotion.swing => '🎐',
  };
}

class MediaTools {
  /// Turns a picture into a sticker: subject cut out, trimmed, white die-cut
  /// outline, centered on a transparent 512×512 canvas (PNG).
  static Future<Uint8List> makeSticker(Uint8List source, {bool outline = true}) async {
    final cut = await removeBackground(source);
    return compute(_makeSticker, _StickerJob(cut, outline));
  }

  /// Cuts the subject out of any photo (transparent PNG, same size).
  ///
  /// Uses Google ML Kit subject segmentation on the phone: accurate on hair, fur
  /// and busy backgrounds, free, and offline once its model is downloaded. Falls
  /// back to a plain-background flood fill if ML Kit is unavailable.
  static Future<Uint8List> removeBackground(Uint8List source) async {
    Object? last;
    // Right after install Google Play may still be fetching the model; give it a moment.
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        return await _mlKitCutout(source);
      } catch (e) {
        last = e;
        final downloading = '$e'.toLowerCase().contains('download') || '$e'.toLowerCase().contains('module');
        if (!downloading) break;
        await Future<void>.delayed(Duration(seconds: 3 * (attempt + 1)));
      }
    }
    debugPrint('ML Kit segmentation unavailable, using flood fill: $last');
    return compute(_cutout, source);
  }

  static Future<Uint8List> cutout(Uint8List source) => removeBackground(source);

  static Future<Uint8List> _mlKitCutout(Uint8List source) async {
    // Large photos are slow to segment; 1280px keeps detail and stays fast.
    final prepared = await compute(_prepareForSegmentation, source);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/seg_${DateTime.now().microsecondsSinceEpoch}.png');
    await file.writeAsBytes(prepared);
    final segmenter = SubjectSegmenter(
      options: SubjectSegmenterOptions(
        enableForegroundBitmap: true,
        enableForegroundConfidenceMask: false,
        enableMultipleSubjects: SubjectResultOptions(enableConfidenceMask: false, enableSubjectBitmap: false),
      ),
    );
    try {
      final result = await segmenter.processImage(InputImage.fromFilePath(file.path));
      final png = result.foregroundBitmap;
      if (png == null || png.isEmpty) throw Exception('no subject found');
      return png;
    } finally {
      await segmenter.close();
      if (file.existsSync()) file.deleteSync();
    }
  }

  /// Renders an animated GIF sticker from a still sticker.
  static Future<Uint8List> animateSticker(Uint8List sticker, StickerMotion motion) =>
      compute(_animate, _AnimJob(sticker, motion));

  /// Real character motion: [poses] are cut-out stickers of the same character in
  /// different poses (made by an AI edit). They play in a loop with a soft bob.
  static Future<Uint8List> animatePoses(List<Uint8List> poses) => compute(_animatePoses, poses);

  /// A free "image to video" fallback: slow zoom-and-pan (Ken Burns) as GIF.
  static Future<Uint8List> kenBurns(Uint8List source, {int seconds = 3}) =>
      compute(_kenBurns, _KenBurnsJob(source, seconds));
}

class _StickerJob {
  _StickerJob(this.bytes, this.outline);
  final Uint8List bytes;
  final bool outline;
}

class _AnimJob {
  _AnimJob(this.bytes, this.motion);
  final Uint8List bytes;
  final StickerMotion motion;
}

Uint8List _prepareForSegmentation(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw Exception('bad image');
  var im = decoded;
  if (im.width > 1280 || im.height > 1280) {
    im = im.width >= im.height ? img.copyResize(im, width: 1280) : img.copyResize(im, height: 1280);
  }
  return Uint8List.fromList(img.encodePng(im));
}

/// Input is an already cut-out PNG. Trims to the subject so it fills the sticker.
Uint8List _makeSticker(_StickerJob job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) throw Exception('bad image');
  var src = decoded.convert(numChannels: 4);

  var minX = src.width, minY = src.height, maxX = -1, maxY = -1;
  for (final p in src) {
    if (p.a > 24) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
  }
  if (maxX > minX && maxY > minY) {
    src = img.copyCrop(src, x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
  }
  const box = 440;
  src = src.width >= src.height
      ? img.copyResize(src, width: box, interpolation: img.Interpolation.cubic)
      : img.copyResize(src, height: box, interpolation: img.Interpolation.cubic);

  final canvas = img.Image(width: 512, height: 512, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  final dx = (512 - src.width) ~/ 2;
  final dy = (512 - src.height) ~/ 2;

  if (job.outline) {
    // Stamp a white silhouette around the subject to get the classic die-cut edge.
    final mask = img.Image(width: src.width, height: src.height, numChannels: 4);
    for (final p in src) {
      if (p.a > 40) mask.setPixelRgba(p.x, p.y, 255, 255, 255, 255);
    }
    // Several rings at fine angles give a smooth, even edge instead of a jagged one.
    for (final r in const [3, 6, 8]) {
      for (var a = 0; a < 360; a += 8) {
        final ox = (cos(a * pi / 180) * r).round();
        final oy = (sin(a * pi / 180) * r).round();
        img.compositeImage(canvas, mask, dstX: dx + ox, dstY: dy + oy);
      }
    }
  }
  img.compositeImage(canvas, src, dstX: dx, dstY: dy);
  return Uint8List.fromList(img.encodePng(canvas));
}

Uint8List _cutout(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw Exception('bad image');
  var im = decoded.convert(numChannels: 4);
  if (im.width > 1024 || im.height > 1024) {
    im = im.width >= im.height ? img.copyResize(im, width: 1024) : img.copyResize(im, height: 1024);
  }
  _floodRemoveBackground(im);
  return Uint8List.fromList(img.encodePng(im));
}

/// Removes the flat background by flood-filling from the borders. Works well
/// because sticker prompts ask the model for a plain white backdrop.
void _floodRemoveBackground(img.Image im) {
  final w = im.width, h = im.height;
  final seed = im.getPixel(0, 0);
  final br = seed.r.toInt(), bg = seed.g.toInt(), bb = seed.b.toInt();
  const tol = 38;
  bool close(img.Pixel p) => (p.r - br).abs() < tol && (p.g - bg).abs() < tol && (p.b - bb).abs() < tol;

  final visited = Uint8List(w * h);
  final q = Queue<int>();
  void push(int x, int y) {
    final i = y * w + x;
    if (visited[i] == 1) return;
    visited[i] = 1;
    if (close(im.getPixel(x, y))) q.add(i);
  }

  for (var x = 0; x < w; x++) {
    push(x, 0);
    push(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    push(0, y);
    push(w - 1, y);
  }
  while (q.isNotEmpty) {
    final i = q.removeFirst();
    final x = i % w, y = i ~/ w;
    im.setPixelRgba(x, y, 0, 0, 0, 0);
    if (x > 0) push(x - 1, y);
    if (x < w - 1) push(x + 1, y);
    if (y > 0) push(x, y - 1);
    if (y < h - 1) push(x, y + 1);
  }
}

Uint8List _animate(_AnimJob job) {
  final base = img.decodePng(job.bytes) ?? img.decodeImage(job.bytes)!;
  final sticker = img.copyResize(base.convert(numChannels: 4), width: 320, height: 320);
  const frames = 16;
  const size = 360;
  final rendered = <img.Image>[];

  for (var f = 0; f < frames; f++) {
    final t = f / frames; // 0..1
    final wave = sin(t * 2 * pi);
    var scale = 1.0, angle = 0.0, ox = 0.0, oy = 0.0;
    switch (job.motion) {
      case StickerMotion.bounce:
        oy = -wave.abs() * 30;
        scale = 1 + (wave.abs() < 0.15 ? -0.06 : 0);
      case StickerMotion.wiggle:
        angle = wave * 12;
      case StickerMotion.pulse:
        scale = 1 + wave * 0.08;
      case StickerMotion.spin:
        angle = t * 360;
      case StickerMotion.float:
        oy = wave * 14;
        angle = wave * 3;
      case StickerMotion.shake:
        ox = (f.isEven ? 1 : -1) * 8.0;
      case StickerMotion.heartbeat:
        final beat = t < 0.15 ? sin(t / 0.15 * pi) : (t > 0.25 && t < 0.4 ? sin((t - 0.25) / 0.15 * pi) : 0.0);
        scale = 1 + beat * 0.14;
      case StickerMotion.swing:
        angle = wave * 20;
        ox = wave * 10;
    }

    var frame = sticker;
    if (scale != 1.0) {
      final s = (320 * scale).round();
      frame = img.copyResize(frame, width: s, height: s);
    }
    if (angle != 0) frame = img.copyRotate(frame, angle: angle);

    final canvas = img.Image(width: size, height: size, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
    img.compositeImage(
      canvas,
      frame,
      dstX: ((size - frame.width) / 2 + ox).round(),
      dstY: ((size - frame.height) / 2 + oy).round(),
    );
    rendered.add(canvas);
  }
  return encodeTransparentGif(rendered, delayCs: 6);
}

Uint8List _animatePoses(List<Uint8List> poses) {
  const size = 360;
  final stickers = [
    for (final b in poses)
      img.copyResize((img.decodePng(b) ?? img.decodeImage(b)!).convert(numChannels: 4), width: 320, height: 320),
  ];
  // Ping-pong through the poses: 0 1 2 1 0 1 2 1 ...
  final order = [for (var i = 0; i < stickers.length; i++) i, for (var i = stickers.length - 2; i > 0; i--) i];
  final rendered = <img.Image>[];
  for (var k = 0; k < order.length * 2; k++) {
    final pose = stickers[order[k % order.length]];
    for (var hold = 0; hold < 2; hold++) {
      final t = (k * 2 + hold) / (order.length * 4);
      final oy = sin(t * 4 * pi) * 6;
      final canvas = img.Image(width: size, height: size, numChannels: 4);
      img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
      img.compositeImage(canvas, pose, dstX: (size - 320) ~/ 2, dstY: ((size - 320) / 2 + oy).round());
      rendered.add(canvas);
    }
  }
  return encodeTransparentGif(rendered, delayCs: 12, sample: stickers);
}

/// GIF encoders drop alpha when they quantize, which is why stickers came out on
/// black. Here one palette is built from the sticker's colors, and index 255 is
/// reserved as the transparent color for every frame.
Uint8List encodeTransparentGif(List<img.Image> frames, {required int delayCs, List<img.Image>? sample}) {
  // The palette is learned from every distinct picture, side by side.
  final pics = sample ?? [frames.first];
  final opaque = img.Image(width: pics.first.width * pics.length, height: pics.first.height);
  img.fill(opaque, color: img.ColorRgb8(255, 255, 255));
  for (var i = 0; i < pics.length; i++) {
    img.compositeImage(opaque, pics[i], dstX: i * pics.first.width);
  }
  final q = img.NeuralQuantizer(opaque, numberOfColors: 255, samplingFactor: 5);
  final palette = img.PaletteUint8(256, 4);
  for (var i = 0; i < 255 && i < q.palette.numColors; i++) {
    palette.setRgba(i, q.palette.getRed(i), q.palette.getGreen(i), q.palette.getBlue(i), 255);
  }
  palette.setRgba(255, 0, 0, 0, 0);

  final enc = img.GifEncoder(repeat: 0);
  for (final f in frames) {
    final out = img.Image(width: f.width, height: f.height, numChannels: 1, palette: palette);
    for (final p in f) {
      out.getPixel(p.x, p.y).index = p.a < 110
          ? 255
          : q.getColorIndexRgb(p.r.toInt(), p.g.toInt(), p.b.toInt()).clamp(0, 254);
    }
    enc.addFrame(out, duration: delayCs);
  }
  return enc.finish()!;
}

class _KenBurnsJob {
  _KenBurnsJob(this.bytes, this.seconds);
  final Uint8List bytes;
  final int seconds;
}

Uint8List _kenBurns(_KenBurnsJob job) {
  final src = img.decodeImage(job.bytes)!;
  final base = img.copyResize(src, width: 720, height: (720 * src.height / src.width).round());
  final frames = (job.seconds * 10).clamp(20, 60);
  const outW = 480;
  final outH = (outW * base.height / base.width).round();
  img.Image? anim;
  for (var f = 0; f < frames; f++) {
    final lin = f / (frames - 1);
    final t = lin * lin * (3 - 2 * lin); // ease in-out for a smooth camera move
    final zoom = 1 + 0.25 * t;
    final cw = (base.width / zoom).round();
    final ch = (base.height / zoom).round();
    final cx = ((base.width - cw) * t).round();
    final cy = ((base.height - ch) * 0.5).round();
    final frame = img.copyResize(
      img.copyCrop(base, x: cx, y: cy, width: cw, height: ch),
      width: outW,
      height: outH,
    )..frameDuration = 100;
    if (anim == null) {
      anim = frame..loopCount = 0;
    } else {
      anim.addFrame(frame);
    }
  }
  return Uint8List.fromList(img.encodeGif(anim!, samplingFactor: 6));
}
