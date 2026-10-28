import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../providers/voice_gen.dart';
import 'gift_maker.dart';

/// Synthesises a short soundtrack for a gift on the phone: a soft chord, a
/// whoosh on entrance, a pop when it opens, and bell sparkles while it shines.
class GiftSound {
  static const rate = 44100;

  static Future<Uint8List> make(GiftEffect effect, {double seconds = 3, double? openAt}) =>
      compute(_make, (effect, seconds, openAt));

  static Uint8List _make((GiftEffect, double, double?) job) {
    final (effect, seconds, openAt) = job;
    final n = (seconds * rate).round();
    final buf = Float64List(n);
    final rnd = Random(effect.index + 3);

    // A warm major chord that swells in and fades out.
    const chords = {
      GiftEffect.hearts: [261.63, 329.63, 392.0, 493.88], // Cmaj7, romantic
      GiftEffect.fireworks: [293.66, 369.99, 440.0, 587.33], // D major, festive
    };
    final chord = chords[effect] ?? const [261.63, 329.63, 392.0, 523.25];
    for (var i = 0; i < n; i++) {
      final t = i / rate;
      final env = min(1.0, t / 0.6) * min(1.0, (seconds - t) / 0.8);
      var v = 0.0;
      for (final (k, f) in chord.indexed) {
        v += sin(2 * pi * f * t + k) * (0.5 + 0.5 * sin(2 * pi * 0.3 * t + k));
      }
      buf[i] += v / chord.length * 0.16 * env;
    }

    // Entrance whoosh: noise that rises and falls.
    if (effect != GiftEffect.shine) _whoosh(buf, rnd, 0.0, 0.55);

    // Rising arpeggio, like a music box.
    final notes = [for (final f in chord) f * 2];
    for (var k = 0; k < 8; k++) {
      _bell(buf, notes[k % notes.length] * (k >= 4 ? 2 : 1), 0.35 + k * 0.12, 0.9, 0.18);
    }

    // The reveal: a soft pop and a bright chord when the box opens.
    final reveal = openAt ?? seconds * 0.35;
    _pop(buf, reveal);
    for (final f in chord) {
      _bell(buf, f * 4, reveal + 0.02, 1.6, 0.12);
    }

    // Sparkles that twinkle while it shines.
    final sparkles = effect == GiftEffect.fireworks ? 26 : 16;
    for (var k = 0; k < sparkles; k++) {
      final at = reveal + rnd.nextDouble() * (seconds - reveal - 0.3);
      _bell(buf, 1800 + rnd.nextDouble() * 2600, at, 0.35, 0.07);
    }
    if (effect == GiftEffect.fireworks) {
      for (final at in [seconds * 0.25, seconds * 0.45, seconds * 0.65]) {
        _pop(buf, at, big: true);
      }
    }

    // Normalise and convert to 16-bit PCM.
    var peak = 0.0;
    for (final v in buf) {
      peak = max(peak, v.abs());
    }
    final gain = peak > 0 ? 0.9 / peak : 1.0;
    final pcm = ByteData(n * 2);
    for (var i = 0; i < n; i++) {
      pcm.setInt16(i * 2, (buf[i] * gain * 32767).round().clamp(-32768, 32767), Endian.little);
    }
    return VoiceGen.pcmToWav(pcm.buffer.asUint8List(), sampleRate: rate);
  }

  /// A bell: a sine with a little inharmonic overtone and an exponential decay.
  static void _bell(Float64List buf, double f, double at, double len, double amp) {
    final start = (at * rate).round();
    final end = min(buf.length, start + (len * rate).round());
    for (var i = max(0, start); i < end; i++) {
      final t = (i - start) / rate;
      final env = exp(-t * 6 / len) * min(1.0, t / 0.004);
      buf[i] += (sin(2 * pi * f * t) + 0.35 * sin(2 * pi * f * 2.76 * t)) * amp * env;
    }
  }

  static void _whoosh(Float64List buf, Random rnd, double at, double len) {
    final start = (at * rate).round();
    final end = min(buf.length, start + (len * rate).round());
    var lp = 0.0;
    for (var i = start; i < end; i++) {
      final k = (i - start) / (end - start);
      // A low-pass whose cutoff sweeps up then down gives the "air" movement.
      final a = 0.02 + 0.25 * sin(k * pi);
      lp += a * ((rnd.nextDouble() * 2 - 1) - lp);
      buf[i] += lp * sin(k * pi) * 0.9;
    }
  }

  static void _pop(Float64List buf, double at, {bool big = false}) {
    final start = (at * rate).round();
    final len = big ? 0.35 : 0.12;
    final end = min(buf.length, start + (len * rate).round());
    for (var i = max(0, start); i < end; i++) {
      final t = (i - start) / rate;
      final f = (big ? 90 : 220) * exp(-t * 18) + 60;
      buf[i] += sin(2 * pi * f * t) * exp(-t / len * 5) * (big ? 0.8 : 0.5);
    }
  }
}
