import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// A published release, read from dist/version.json next to the signed APK.
class Release {
  const Release({required this.version, required this.build, required this.url, this.notesAr = '', this.notesEn = ''});

  final String version;
  final int build;
  final String url;
  final String notesAr;
  final String notesEn;

  factory Release.fromJson(Map<String, dynamic> j) => Release(
        version: '${j['version'] ?? ''}',
        build: (j['build'] as num?)?.toInt() ?? 0,
        url: '${j['url'] ?? ''}',
        notesAr: '${j['notes_ar'] ?? ''}',
        notesEn: '${j['notes_en'] ?? ''}',
      );
}

enum UpdateState { idle, checking, upToDate, available, downloading, ready, failed }

/// Finds, downloads and installs new releases from inside the app.
class Updater extends ChangeNotifier {
  Updater({
    http.Client? client,
    this.manifestUrl = defaultManifest,
    Future<int> Function()? currentBuild,
    MethodChannel? channel,
  })  : _client = client ?? http.Client(),
        _currentBuild = currentBuild ?? _platformBuild,
        _ch = channel ?? const MethodChannel('file_chat/updates');

  static const defaultManifest =
      'https://raw.githubusercontent.com/al3m6i89-mind-ai/mind-ai/file-chat-app/dist/version.json';
  static const playPackage = 'com.zuhair.file_chat';

  final http.Client _client;
  final String manifestUrl;
  final Future<int> Function() _currentBuild;
  final MethodChannel _ch;

  UpdateState state = UpdateState.idle;
  Release? latest;
  double progress = 0;
  String? error;
  String? _apk;
  DateTime? _lastCheck;

  /// Fires when the user taps the phone notification.
  final openRequests = StreamController<void>.broadcast();

  bool get hasUpdate =>
      latest != null && (state == UpdateState.available || state == UpdateState.downloading || state == UpdateState.ready || state == UpdateState.failed);

  static Future<int> _platformBuild() async => int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  static Future<bool> _fromPlay() async {
    try {
      return (await PackageInfo.fromPlatform()).installerStore == 'com.android.vending';
    } catch (_) {
      return false;
    }
  }

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } catch (_) {
      return null; // Not on Android (tests) or the native side is missing.
    }
  }

  /// Called once at start: background checks, notification permission, and
  /// listening for taps on the update notification.
  Future<void> start({required bool arabic}) async {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'openUpdate') openRequests.add(null);
    });
    unawaited(() async {
      await _call('askNotifications');
      await _call('schedule', {'url': manifestUrl, 'ar': arabic});
      if (await _call<bool>('takeOpenUpdate') == true) openRequests.add(null);
    }());
    await check(quiet: true, arabic: arabic);
  }

  /// [quiet] checks skip if one ran in the last hour and never show errors.
  Future<void> check({bool quiet = false, bool arabic = true}) async {
    if (state == UpdateState.checking || state == UpdateState.downloading) return;
    if (quiet && _lastCheck != null && DateTime.now().difference(_lastCheck!) < const Duration(hours: 1)) return;
    final before = state;
    state = UpdateState.checking;
    error = null;
    notifyListeners();
    try {
      final res = await _client
          .get(Uri.parse('$manifestUrl?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw HttpException('${res.statusCode}');
      final r = Release.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
      _lastCheck = DateTime.now();
      if (r.build > await _currentBuild() && r.url.isNotEmpty) {
        final same = latest?.build == r.build;
        latest = r;
        state = same && before == UpdateState.ready ? UpdateState.ready : UpdateState.available;
        unawaited(_call('notify', {'version': r.version, 'build': r.build, 'ar': arabic}));
      } else {
        latest = null;
        state = UpdateState.upToDate;
      }
    } catch (e) {
      debugPrint('update check: $e');
      state = quiet ? before : UpdateState.failed;
      error = quiet ? null : 'network';
    }
    notifyListeners();
  }

  /// Downloads the APK (with progress) and opens Android's installer.
  Future<void> install() async {
    final r = latest;
    if (r == null) return;
    if (await _fromPlay()) {
      await launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=$playPackage'),
          mode: LaunchMode.externalApplication);
      return;
    }
    if (state != UpdateState.ready || _apk == null || !File(_apk!).existsSync()) {
      final ok = await _download(r);
      if (!ok) return;
    }
    await _openInstaller();
  }

  Future<bool> _download(Release r) async {
    state = UpdateState.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    IOSink? sink;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/file-chat-${r.build}.apk');
      final res = await _client.send(http.Request('GET', Uri.parse(r.url)));
      if (res.statusCode != 200) throw HttpException('${res.statusCode}');
      final total = res.contentLength ?? 0;
      var got = 0;
      sink = file.openWrite();
      await for (final chunk in res.stream.timeout(const Duration(seconds: 45))) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) {
          final p = got / total;
          if (p - progress >= 0.01 || p == 1) {
            progress = p;
            notifyListeners();
          }
        }
      }
      await sink.close();
      sink = null;
      if (total > 0 && got != total) throw const HttpException('incomplete');
      _apk = file.path;
      progress = 1;
      state = UpdateState.ready;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('update download: $e');
      await sink?.close();
      state = UpdateState.failed;
      error = 'download';
      notifyListeners();
      return false;
    }
  }

  Future<void> _openInstaller() async {
    final path = _apk;
    if (path == null) return;
    if (await _call<bool>('canInstall') == false) {
      error = 'permission';
      notifyListeners();
      await _call('openInstallSettings');
      return;
    }
    error = null;
    notifyListeners();
    try {
      final res = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
      if (res.type == ResultType.done) return;
    } catch (e) {
      debugPrint('update install: $e');
    }
    error = 'install';
    notifyListeners();
  }

  @override
  void dispose() {
    openRequests.close();
    super.dispose();
  }
}
