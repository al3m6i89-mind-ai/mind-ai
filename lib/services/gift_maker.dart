import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'media_tools.dart';

/// Entrance and loop styles for a live-stream style gift.
enum GiftEffect { spin3d, royal, flyIn, hearts, fireworks, shine }

extension GiftEffectInfo on GiftEffect {
  String get label => switch (this) {
    GiftEffect.spin3d => 'دوران 3D',
    GiftEffect.royal => 'دخول ملكي',
    GiftEffect.flyIn => 'طيران',
    GiftEffect.hearts => 'مطر قلوب',
    GiftEffect.fireworks => 'ألعاب نارية',
    GiftEffect.shine => 'لمعة ذهبية',
  };

  String get emoji => switch (this) {
    GiftEffect.spin3d => '🧊',
    GiftEffect.royal => '👑',
    GiftEffect.flyIn => '🚀',
    GiftEffect.hearts => '💖',
    GiftEffect.fireworks => '🎆',
    GiftEffect.shine => '✨',
  };
}

/// Where a gift or particle is at one moment. Coordinates are canvas pixels.
class _Pose {
  const _Pose(this.x, this.y, this.scale, this.rot, this.opacity, [this.sx = 1, this.light = 0]);
  final double x, y, scale, rot, opacity;

  /// Horizontal squash for a turn around the vertical axis (-1..1, negative = mirrored).
  final double sx;

  /// -1 darker .. 1 brighter, the light changing as the object turns.
  final double light;
}

class _Particle {
  _Particle(this.star, this.color, this.size, this.pose);
  final bool star;
  final List<int> color;
  final double size;

  /// Pose at time t in [0, 1]; null while hidden.
  final _Pose? Function(double t) pose;
}

/// Builds the gift animation once as a timeline, then renders it two ways:
/// a transparent GIF to share, and a Lottie JSON that apps can play.
class GiftMaker {
  static const size = 512;
  static const giftBox = 300.0;
  static const seconds = 3.0;

  static double _easeOutBack(double x) {
    const c1 = 1.70158, c3 = c1 + 1;
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2);
  }

  static double _easeOut(double x) => 1 - pow(1 - x, 3).toDouble();

  static _Pose gift(GiftEffect e, double t) {
    const c = size / 2;
    final pulse = 1 + sin(t * 2 * pi * 2) * 0.035;
    switch (e) {
      case GiftEffect.spin3d:
        // Pops in, then makes one full turn around its vertical axis while bobbing.
        final s = t < 0.2 ? _easeOutBack(t / 0.2) : 1.0;
        final turn = t < 0.2 ? 0.0 : (t - 0.2) / 0.8 * 2 * pi;
        final sx = cos(turn);
        final squash = sx.abs() < 0.12 ? (sx.isNegative ? -0.12 : 0.12) : sx;
        return _Pose(c, c + sin(t * 2 * pi) * 8, max(0, s), 0, 1, squash, sin(turn) * 0.6);
      case GiftEffect.royal:
        final s = t < 0.25 ? _easeOutBack(t / 0.25) : pulse;
        return _Pose(c, c, max(0, s), 0, t > 0.9 ? (1 - t) / 0.1 : 1);
      case GiftEffect.flyIn:
        if (t < 0.3) {
          final k = _easeOut(t / 0.3);
          return _Pose(c + (1 - k) * 420, c + (1 - k) * 120, 0.6 + 0.4 * k, -18 * (1 - k), 1);
        }
        if (t > 0.82) {
          final k = (t - 0.82) / 0.18;
          return _Pose(c, c - k * k * 420, 1 - 0.3 * k, 0, 1 - k);
        }
        return _Pose(c, c + sin((t - 0.3) * 2 * pi * 2) * 10, 1, sin(t * 2 * pi * 2) * 3, 1);
      case GiftEffect.hearts || GiftEffect.fireworks:
        final s = t < 0.2 ? _easeOutBack(t / 0.2) : pulse;
        return _Pose(c, c + 20, max(0, s) * 0.85, 0, t > 0.9 ? (1 - t) / 0.1 : 1);
      case GiftEffect.shine:
        final k = _easeOut(min(1, t / 0.25));
        return _Pose(c, c, 0.85 + 0.15 * k, 0, t > 0.9 ? (1 - t) / 0.1 : k);
    }
  }

  static List<_Particle> particles(GiftEffect e) {
    final rnd = Random(e.index * 31 + 7);
    const c = size / 2;
    const gold = [255, 210, 70], white = [255, 255, 255], pink = [255, 79, 163];
    final palette = [
      gold,
      white,
      pink,
      [123, 92, 255],
      [0, 210, 255],
    ];
    final out = <_Particle>[];
    switch (e) {
      case GiftEffect.royal || GiftEffect.shine || GiftEffect.flyIn || GiftEffect.spin3d:
        // Twinkling stars around the gift.
        for (var i = 0; i < 16; i++) {
          final a = rnd.nextDouble() * 2 * pi, r = 150 + rnd.nextDouble() * 90;
          final phase = rnd.nextDouble(), x = c + cos(a) * r, y = c + sin(a) * r;
          out.add(
            _Particle(
              true,
              e == GiftEffect.flyIn ? palette[i % 5] : (i.isEven ? gold : white),
              20 + rnd.nextDouble() * 18,
              (t) {
                if (t < 0.22) return null;
                final tw = sin((t * 3 + phase) * 2 * pi);
                if (tw < 0) return null;
                return _Pose(x, y, tw, t * 180, tw);
              },
            ),
          );
        }
      case GiftEffect.hearts:
        for (var i = 0; i < 18; i++) {
          final start = rnd.nextDouble() * 0.7, x0 = 60 + rnd.nextDouble() * (size - 120);
          final speed = 0.25 + rnd.nextDouble() * 0.2, sway = rnd.nextDouble() * 2 * pi;
          out.add(
            _Particle(false, i % 3 == 0 ? white : pink, 22 + rnd.nextDouble() * 16, (t) {
              final k = (t - start) / speed;
              if (k < 0 || k > 1) return null;
              return _Pose(x0 + sin(k * 2 * pi + sway) * 20, size - 20 - k * (size - 40), 1, 0, 1 - k * 0.6);
            }),
          );
        }
      case GiftEffect.fireworks:
        for (final (b, at) in const [(0, 0.25), (1, 0.45), (2, 0.65)]) {
          final cx = c + (b - 1) * 150, cy = 120.0 + (b == 1 ? -30 : 20);
          for (var i = 0; i < 14; i++) {
            final a = i / 14 * 2 * pi, col = palette[(b + i) % 5];
            out.add(
              _Particle(true, col, 16 + rnd.nextDouble() * 10, (t) {
                final k = (t - at) / 0.3;
                if (k < 0 || k > 1) return null;
                final r = _easeOut(k) * 150;
                return _Pose(cx + cos(a) * r, cy + sin(a) * r + k * k * 30, 1 - k * 0.4, 0, 1 - k);
              }),
            );
          }
        }
    }
    return out;
  }

  // ---------------------------------------------------------------- GIF

  static Future<Uint8List> gif(Uint8List giftPng, GiftEffect e) => compute(_renderGif, (giftPng, e));

  static Uint8List _renderGif((Uint8List, GiftEffect) job) {
    final (png, e) = job;
    final art = _fit(img.decodePng(png) ?? img.decodeImage(png)!);
    final parts = particles(e);
    const frames = 42;
    final out = <img.Image>[];
    for (var f = 0; f < frames; f++) {
      final t = f / frames;
      final canvas = img.Image(width: size, height: size, numChannels: 4);
      img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
      if (e == GiftEffect.shine || e == GiftEffect.royal) _rays(canvas, t, e == GiftEffect.shine);
      final p = gift(e, t);
      if (p.scale > 0.02 && p.opacity > 0.05) {
        var g = img.copyResize(
          art,
          width: max(1, (art.width * p.scale * p.sx.abs()).round()),
          height: max(1, (art.height * p.scale).round()),
        );
        if (p.sx < 0) g = img.flipHorizontal(g);
        if (p.light.abs() > 0.02) _shade(g, p.light);
        if (p.rot.abs() > 0.5) g = img.copyRotate(g, angle: p.rot);
        if (e == GiftEffect.shine) _sweep(g, t);
        if (p.opacity < 0.98) _fade(g, p.opacity);
        _place(canvas, g, (p.x - g.width / 2).round(), (p.y - g.height / 2).round());
      }
      for (final q in parts) {
        final pp = q.pose(t);
        if (pp == null || pp.opacity < 0.35) continue;
        _drawParticle(canvas, q, pp);
      }
      out.add(canvas);
    }
    return encodeTransparentGif(out, delayCs: 7, sample: [out[frames ~/ 2], out[frames ~/ 3]]);
  }

  /// Draws [src] at (dx, dy), clipping it when it hangs off the canvas
  /// (compositeImage drops images placed at negative offsets).
  static void _place(img.Image canvas, img.Image src, int dx, int dy) {
    final int srcX = max(0, -dx), srcY = max(0, -dy);
    final int w = min(src.width - srcX, canvas.width - max(0, dx));
    final int h = min(src.height - srcY, canvas.height - max(0, dy));
    if (w <= 0 || h <= 0) return;
    img.compositeImage(
      canvas,
      src,
      dstX: dx < 0 ? 0 : dx,
      dstY: dy < 0 ? 0 : dy,
      srcX: srcX,
      srcY: srcY,
      srcW: w,
      srcH: h,
      dstW: w,
      dstH: h,
    );
  }

  static img.Image _fit(img.Image src) {
    var s = src.convert(numChannels: 4);
    var minX = s.width, minY = s.height, maxX = -1, maxY = -1;
    for (final p in s) {
      if (p.a > 24) {
        minX = min(minX, p.x);
        minY = min(minY, p.y);
        maxX = max(maxX, p.x);
        maxY = max(maxY, p.y);
      }
    }
    if (maxX > minX) s = img.copyCrop(s, x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
    return s.width >= s.height
        ? img.copyResize(s, width: giftBox.round(), interpolation: img.Interpolation.cubic)
        : img.copyResize(s, height: giftBox.round(), interpolation: img.Interpolation.cubic);
  }

  /// Golden light rays turning slowly behind the gift.
  static void _rays(img.Image c, double t, bool gold) {
    const n = 16, cx = size / 2, cy = size / 2;
    final col = gold ? img.ColorRgba8(255, 214, 90, 255) : img.ColorRgba8(255, 236, 170, 255);
    final appear = min(1.0, t / 0.25);
    for (var i = 0; i < n; i++) {
      // Long and short rays alternate so the burst looks lighter.
      final r = (i.isEven ? 240 : 185) * appear;
      final a = i / n * 2 * pi + t * pi / 2;
      img.fillPolygon(
        c,
        vertices: [
          img.Point(cx, cy),
          img.Point(cx + cos(a - 0.035) * r, cy + sin(a - 0.035) * r),
          img.Point(cx + cos(a + 0.035) * r, cy + sin(a + 0.035) * r),
        ],
        color: col,
      );
    }
  }

  /// A bright diagonal band crossing the gift, like light on gold.
  static void _sweep(img.Image g, double t) {
    final k = ((t - 0.3) / 0.4);
    if (k < 0 || k > 1) return;
    final band = -g.height + k * (g.width + 2 * g.height);
    for (final p in g) {
      if (p.a < 30) continue;
      final d = (p.x + p.y - band).abs();
      if (d < 28) {
        final w = 1 - d / 28;
        p
          ..r = p.r + (255 - p.r) * w * 0.8
          ..g = p.g + (255 - p.g) * w * 0.8
          ..b = p.b + (255 - p.b) * w * 0.8;
      }
    }
  }

  /// Brightens or darkens the object, with a soft highlight on the lit side.
  static void _shade(img.Image g, double light) {
    for (final p in g) {
      if (p.a < 10) continue;
      final side = light > 0 ? p.x / g.width : 1 - p.x / g.width;
      final k = light.abs() * (0.35 + 0.65 * side);
      if (light > 0) {
        p
          ..r = p.r + (255 - p.r) * k * 0.45
          ..g = p.g + (255 - p.g) * k * 0.45
          ..b = p.b + (255 - p.b) * k * 0.45;
      } else {
        p
          ..r = p.r * (1 - k * 0.5)
          ..g = p.g * (1 - k * 0.5)
          ..b = p.b * (1 - k * 0.5);
      }
    }
  }

  static void _fade(img.Image g, double o) {
    for (final p in g) {
      p.a = p.a * o;
    }
  }

  static void _drawParticle(img.Image c, _Particle q, _Pose p) {
    final col = img.ColorRgba8(q.color[0], q.color[1], q.color[2], 255);
    final r = q.size * p.scale / 2;
    if (r < 1) return;
    if (q.star) {
      final pts = <img.Point>[];
      for (var i = 0; i < 8; i++) {
        final a = i / 8 * 2 * pi + p.rot * pi / 180;
        final rr = i.isEven ? r : r * 0.38;
        pts.add(img.Point(p.x + cos(a) * rr, p.y + sin(a) * rr));
      }
      img.fillPolygon(c, vertices: pts, color: col);
    } else {
      // A small heart: two circles and a triangle.
      img.fillCircle(c, x: (p.x - r * 0.5).round(), y: p.y.round(), radius: (r * 0.55).round(), color: col);
      img.fillCircle(c, x: (p.x + r * 0.5).round(), y: p.y.round(), radius: (r * 0.55).round(), color: col);
      img.fillPolygon(
        c,
        vertices: [
          img.Point(p.x - r * 1.02, p.y + r * 0.15),
          img.Point(p.x + r * 1.02, p.y + r * 0.15),
          img.Point(p.x, p.y + r * 1.25),
        ],
        color: col,
      );
    }
  }

  // ---------------------------------------------------------------- Lottie

  /// A Lottie (Bodymovin) JSON with the gift image embedded, ready for
  /// lottie-android, lottie-ios, lottie-web or Flutter's lottie package.
  static Future<String> lottie(Uint8List giftPng, GiftEffect e) => compute(_lottie, (giftPng, e));

  static String _lottie((Uint8List, GiftEffect) job) {
    final (png, e) = job;
    final art = _fit(img.decodePng(png) ?? img.decodeImage(png)!);
    const fr = 30, total = 90;
    List<Map<String, Object>> track(List<double> Function(double t) v) => [
      for (var f = 0; f <= total; f += 2)
        {
          't': f,
          's': v(f / total),
          if (f < total)
            'i': {
              'x': [1],
              'y': [1],
            },
          if (f < total)
            'o': {
              'x': [0],
              'y': [0],
            },
        },
    ];
    Map<String, Object> anim(List<double> Function(double t) v) => {'a': 1, 'k': track(v)};
    Map<String, Object> still(Object v) => {'a': 0, 'k': v};

    final layers = <Map<String, Object>>[];
    var ind = 1;
    for (final q in particles(e)) {
      final shape = q.star
          ? {
              'ty': 'sr',
              'sy': 1,
              'd': 1,
              'pt': still(4),
              'p': still([0, 0]),
              'r': still(0),
              'ir': still(q.size * 0.19),
              'is': still(0),
              'or': still(q.size / 2),
              'os': still(0),
            }
          : {
              'ty': 'el',
              'd': 1,
              'p': still([0, 0]),
              's': still([q.size, q.size]),
            };
      layers.add({
        'ddd': 0,
        'ind': ind++,
        'ty': 4,
        'nm': 'p$ind',
        'sr': 1,
        'ao': 0,
        'ip': 0,
        'op': total,
        'st': 0,
        'bm': 0,
        'ks': {
          'o': anim((t) => [((q.pose(t)?.opacity ?? 0) * 100).clamp(0, 100).toDouble()]),
          'r': anim((t) => [q.pose(t)?.rot ?? 0]),
          'p': anim((t) {
            final p = q.pose(t);
            return [p?.x ?? -50, p?.y ?? -50, 0];
          }),
          'a': still([0, 0, 0]),
          's': anim((t) {
            final s = (q.pose(t)?.scale ?? 0) * 100;
            return [s, s, 100];
          }),
        },
        'shapes': [
          {
            'ty': 'gr',
            'it': [
              shape,
              {
                'ty': 'fl',
                'c': still([q.color[0] / 255, q.color[1] / 255, q.color[2] / 255, 1]),
                'o': still(100),
                'r': 1,
              },
              {
                'ty': 'tr',
                'p': still([0, 0]),
                'a': still([0, 0]),
                's': still([100, 100]),
                'r': still(0),
                'o': still(100),
              },
            ],
          },
        ],
      });
    }
    layers.add({
      'ddd': 0,
      'ind': ind,
      'ty': 2,
      'nm': 'gift',
      'refId': 'gift',
      'sr': 1,
      'ao': 0,
      'ip': 0,
      'op': total,
      'st': 0,
      'bm': 0,
      'ks': {
        'o': anim((t) => [gift(e, t).opacity.clamp(0, 1) * 100]),
        'r': anim((t) => [gift(e, t).rot]),
        'p': anim((t) => [gift(e, t).x, gift(e, t).y, 0]),
        'a': still([art.width / 2, art.height / 2, 0]),
        's': anim((t) {
          final p = gift(e, t);
          return [p.scale * p.sx * 100, p.scale * 100, 100];
        }),
      },
    });
    return jsonEncode({
      'v': '5.7.4', 'fr': fr, 'ip': 0, 'op': total, 'w': size, 'h': size, 'nm': 'Mind Ai gift', 'ddd': 0,
      'assets': [
        {
          'id': 'gift',
          'w': art.width,
          'h': art.height,
          'u': '',
          'e': 1,
          'p': 'data:image/png;base64,${base64Encode(img.encodePng(art))}',
        },
      ],
      // Lottie draws the first layer on top, so the gift goes last (behind the sparkles).
      'layers': layers,
    });
  }

  // ---------------------------------------------------------------- AI video gifts

  static const _frames = MethodChannel('mindai/frames');

  /// Pulls [count] evenly spaced frames (PNG) from a video file on the phone.
  static Future<List<Uint8List>> extractFrames(String path, {int count = 36, int maxSize = 512}) async {
    final list = await _frames.invokeListMethod<Uint8List>('extract', {
      'path': path,
      'count': count,
      'maxSize': maxSize,
    });
    if (list == null || list.isEmpty) throw Exception('تعذّر قراءة لقطات الفيديو');
    return list;
  }

  /// Puts a cut-out gift on a solid green screen, for the video model to animate.
  static Uint8List onGreen(Uint8List giftPng) {
    final art = _fit(img.decodePng(giftPng) ?? img.decodeImage(giftPng)!);
    final bg = img.Image(width: 1024, height: 1024);
    img.fill(bg, color: img.ColorRgb8(0, 255, 0));
    final big = img.copyResize(art, width: (art.width * 1.9).round(), interpolation: img.Interpolation.cubic);
    img.compositeImage(bg, big, dstX: (1024 - big.width) ~/ 2, dstY: (1024 - big.height) ~/ 2);
    return Uint8List.fromList(img.encodeJpg(bg, quality: 95));
  }

  /// Keys the green screen out of every frame. Returns a transparent GIF and a
  /// ZIP of transparent PNG frames (for SVGA/VAP/After Effects workflows).
  /// With an [effect], the engine's rays and particles are layered around the
  /// AI-animated gift, so both tools make one gift.
  static Future<(Uint8List, Uint8List)> keyFrames(List<Uint8List> frames, {GiftEffect? effect}) =>
      compute(_keyFrames, (frames, effect));

  static (Uint8List, Uint8List) _keyFrames((List<Uint8List>, GiftEffect?) job) {
    final (raw, effect) = job;
    final parts = effect == null ? const <_Particle>[] : particles(effect);
    final keyed = <img.Image>[];
    for (final b in raw) {
      final f = (img.decodePng(b) ?? img.decodeImage(b)!).convert(numChannels: 4);
      // The key colour is sampled from the corners, so a slightly off green still works.
      var kr = 0.0, kg = 0.0, kb = 0.0, n = 0;
      for (final (x, y) in [(2, 2), (f.width - 3, 2), (2, f.height - 3), (f.width - 3, f.height - 3)]) {
        final p = f.getPixel(x, y);
        kr += p.r;
        kg += p.g;
        kb += p.b;
        n++;
      }
      kr /= n;
      kg /= n;
      kb /= n;
      for (final p in f) {
        final d = sqrt(pow(p.r - kr, 2) + pow(p.g - kg, 2) + pow(p.b - kb, 2));
        final greenish = p.g - max(p.r, p.b);
        var a = ((d - 60) / 70).clamp(0.0, 1.0);
        if (greenish > 90) a = 0;
        p.a = a * 255;
        // Remove green spill on the edges.
        if (p.g > max(p.r, p.b)) p.g = max(p.r, p.b) + (p.g - max(p.r, p.b)) * 0.25;
      }
      keyed.add(f);
    }
    // Crop every frame to the same box around the moving gift.
    var minX = keyed.first.width, minY = keyed.first.height, maxX = 0, maxY = 0;
    for (final f in keyed) {
      for (final p in f) {
        if (p.a > 120) {
          minX = min(minX, p.x);
          minY = min(minY, p.y);
          maxX = max(maxX, p.x);
          maxY = max(maxY, p.y);
        }
      }
    }
    final side = max(maxX - minX, maxY - minY) + 24;
    final cx = (minX + maxX) ~/ 2, cy = (minY + maxY) ~/ 2;
    final zip = Archive();
    final out = <img.Image>[];
    for (final (i, f) in keyed.indexed) {
      final canvas = img.Image(width: side, height: side, numChannels: 4);
      img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
      _place(canvas, f, side ~/ 2 - cx, side ~/ 2 - cy);
      final gift = img.copyResize(canvas, width: 400, height: 400, interpolation: img.Interpolation.cubic);
      final fit = img.Image(width: size, height: size, numChannels: 4);
      img.fill(fit, color: img.ColorRgba8(0, 0, 0, 0));
      final t = i / keyed.length;
      if (effect == GiftEffect.royal || effect == GiftEffect.shine)
        _rays(fit, max(t, 0.25), effect == GiftEffect.shine);
      _place(fit, gift, (size - 400) ~/ 2, (size - 400) ~/ 2);
      for (final q in parts) {
        // The AI clip already has its own entrance, so particles start right away.
        final pp = q.pose(0.22 + t * 0.78);
        if (pp != null && pp.opacity >= 0.35) _drawParticle(fit, q, pp);
      }
      out.add(fit);
      final png = img.encodePng(fit);
      zip.addFile(ArchiveFile('frame_${i.toString().padLeft(3, '0')}.png', png.length, png));
    }
    final gif = encodeTransparentGif(out, delayCs: 8, sample: [out.first, out[out.length ~/ 2]]);
    return (gif, Uint8List.fromList(ZipEncoder().encode(zip)));
  }
}
