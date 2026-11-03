import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Reels helpers backed by Android (VideoTools.kt): a cover thumbnail from the
/// video, and compression to 720p H.264 before upload.
class VideoTools {
  static const _channel = MethodChannel('mindai/video');

  /// 0..1 while a compression runs, null otherwise.
  static final progress = ValueNotifier<double?>(null);

  static bool _listening = false;
  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress') progress.value = ((call.arguments as num) / 100).clamp(0, 1).toDouble();
    });
  }

  static Future<String> _temp(String ext) async =>
      '${(await getTemporaryDirectory()).path}/${const Uuid().v4()}.$ext';

  /// A JPEG cover taken about 1 s into the video, or null if none could be made.
  static Future<String?> thumbnail(String videoPath) async {
    try {
      final out = await _temp('jpg');
      final ok = await _channel.invokeMethod<bool>('thumbnail', {'path': videoPath, 'out': out});
      return ok == true && File(out).existsSync() ? out : null;
    } catch (_) {
      return null;
    }
  }

  /// A lighter copy for upload (short side 720, ~2.5 Mbps). Returns the
  /// original path when it's already light or the phone can't compress it.
  static Future<String> compress(String videoPath) async {
    _listen();
    progress.value = 0;
    try {
      final out = await _temp('mp4');
      final done = await _channel.invokeMethod<bool>('compress', {'path': videoPath, 'out': out});
      if (done != true || !File(out).existsSync()) return videoPath;
      // Keep the smaller file (a short, already efficient clip may not shrink).
      return File(out).lengthSync() < File(videoPath).lengthSync() ? out : videoPath;
    } catch (_) {
      return videoPath;
    } finally {
      progress.value = null;
    }
  }

  /// "12.4 MB" style size, for showing before / after.
  static String size(String path) {
    try {
      final b = File(path).lengthSync();
      return b >= 1 << 20 ? '${(b / (1 << 20)).toStringAsFixed(1)} MB' : '${(b / 1024).round()} KB';
    } catch (_) {
      return '';
    }
  }
}
