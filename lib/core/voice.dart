import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'ai.dart';

/// Why a spoken question could not be turned into text.
class VoiceError implements Exception {
  const VoiceError(this.code);

  /// mic (no permission), quota (daily limit), signIn, empty (nothing heard), failed.
  final String code;
  @override
  String toString() => 'VoiceError($code)';
}

/// Records a spoken question and turns it into text through the proxy
/// (Groq's Whisper model), so the user can edit it before sending.
class Voice extends ChangeNotifier {
  Voice({this.proxy = Proxy.build, http.Client? client, AudioRecorder? recorder})
      : _client = client ?? http.Client(),
        _rec = recorder;

  static const model = 'whisper-large-v3-turbo';
  static const maxLength = Duration(minutes: 2);

  final Proxy proxy;
  final http.Client _client;
  AudioRecorder? _rec;
  AudioRecorder get _recorder => _rec ??= AudioRecorder();

  bool recording = false;
  bool transcribing = false;
  DateTime? startedAt;
  String? _path;
  Timer? _limit;

  bool get busy => recording || transcribing;

  /// Starts recording. Throws [VoiceError] 'mic' without microphone permission.
  Future<void> start() async {
    if (busy) return;
    if (!await _recorder.hasPermission()) throw const VoiceError('mic');
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/question-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1, bitRate: 48000),
      path: _path!,
    );
    recording = true;
    startedAt = DateTime.now();
    notifyListeners();
    _limit = Timer(maxLength, () => onLimit?.call());
  }

  /// Called when the recording reaches [maxLength]; the screen then stops it.
  VoidCallback? onLimit;

  /// Throws the recording away.
  Future<void> cancel() async {
    _limit?.cancel();
    if (recording) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    recording = false;
    _delete();
    notifyListeners();
  }

  /// Stops recording and returns the text that was said.
  Future<String> finish(Map<String, String> session) async {
    _limit?.cancel();
    if (!recording) throw const VoiceError('failed');
    final path = await _recorder.stop() ?? _path;
    recording = false;
    transcribing = true;
    notifyListeners();
    try {
      if (path == null || !File(path).existsSync() || File(path).lengthSync() < 1200) throw const VoiceError('empty');
      return await transcribe(File(path), session);
    } finally {
      transcribing = false;
      _delete();
      notifyListeners();
    }
  }

  @visibleForTesting
  Future<String> transcribe(File audio, Map<String, String> session) async {
    if (!proxy.enabled) throw const VoiceError('failed');
    final req = http.MultipartRequest('POST', Uri.parse('${proxy.base}/q/v1/audio/transcriptions'))
      ..headers.addAll({'x-app-token': proxy.token, ...session, 'x-kind': 'voice'})
      ..fields['model'] = model
      ..fields['response_format'] = 'json'
      ..fields['temperature'] = '0'
      ..files.add(await http.MultipartFile.fromPath('file', audio.path, filename: 'question.m4a'));
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 60)));
    } catch (e) {
      debugPrint('voice: $e');
      throw const VoiceError('failed');
    }
    final why = res.headers['x-proxy-error'];
    if (res.statusCode == 429 && why == 'quota') throw const VoiceError('quota');
    if (res.statusCode == 401 && why == 'auth') throw const VoiceError('signIn');
    if (res.statusCode != 200) {
      debugPrint('voice ${res.statusCode}: ${res.body}');
      throw const VoiceError('failed');
    }
    final text = '${(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['text'] ?? ''}'.trim();
    if (text.isEmpty) throw const VoiceError('empty');
    return text;
  }

  void _delete() {
    final p = _path;
    _path = null;
    if (p != null) {
      try {
        File(p).deleteSync();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _limit?.cancel();
    _rec?.dispose();
    super.dispose();
  }
}
