import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

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
  /// Turns a generated picture into a sticker: background removed, white
  /// die-cut outline, centered on a transparent 512×512 canvas (PNG).
  static Future<Uint8List> makeSticker(Uint8List source, {bool outline = true}) =>
      compute(_makeSticker, _StickerJob(source, outline));

  /// Cuts the subject out of a photo with a plain background (transparent PNG).
  static Future<Uint8List> cutout(Uint8List source) => compute(_cutout, source);

  /// Renders an animated GIF sticker from a still sticker.
  static Future<Uint8List> animateSticker(Uint8List sticker, StickerMotion motion) =>
      compute(_animate, _AnimJob(sticker, motion));

  /// A free "image to video" fallback: slow zoom-and-pan (Ken Burns) as GIF.
  static Future<Uint8List> kenBurns(Uint8List source) => compute(_kenBurns, source);
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

Uint8List _makeSticker(_StickerJob job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) throw Exception('bad image');
  var src = decoded.convert(numChannels: 4);
  src = img.copyResize(src, width: 440, height: (440 * src.height / src.width).round());

  _floodRemoveBackground(src);

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
    const r = 7;
    for (var a = 0; a < 360; a += 20) {
      final ox = (cos(a * pi / 180) * r).round();
      final oy = (sin(a * pi / 180) * r).round();
      img.compositeImage(canvas, mask, dstX: dx + ox, dstY: dy + oy);
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
  bool close(img.Pixel p) =>
      (p.r - br).abs() < tol && (p.g - bg).abs() < tol && (p.b - bb).abs() < tol;

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
  final anim = img.Image(width: size, height: size, numChannels: 4);

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
    canvas.frameDuration = 60;
    if (f == 0) {
      anim
        ..frameDuration = 60
        ..loopCount = 0;
      img.compositeImage(anim, canvas);
    } else {
      anim.addFrame(canvas);
    }
  }
  return Uint8List.fromList(img.encodeGif(anim, samplingFactor: 4));
}

Uint8List _kenBurns(Uint8List bytes) {
  final src = img.decodeImage(bytes)!;
  final base = img.copyResize(src, width: 720, height: (720 * src.height / src.width).round());
  const frames = 30;
  const outW = 480;
  final outH = (outW * base.height / base.width).round();
  img.Image? anim;
  for (var f = 0; f < frames; f++) {
    final t = f / (frames - 1);
    final zoom = 1 + 0.25 * t;
    final cw = (base.width / zoom).round();
    final ch = (base.height / zoom).round();
    final cx = ((base.width - cw) * t).round();
    final cy = ((base.height - ch) * 0.5).round();
    final frame = img.copyResize(
      img.copyCrop(base, x: cx, y: cy, width: cw, height: ch),
      width: outW,
      height: outH,
    )..frameDuration = 80;
    if (anim == null) {
      anim = frame..loopCount = 0;
    } else {
      anim.addFrame(frame);
    }
  }
  return Uint8List.fromList(img.encodeGif(anim!, samplingFactor: 6));
}
