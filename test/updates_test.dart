import 'dart:convert';
import 'dart:io';

import 'package:file_chat/core/updates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Paths extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _Paths(this.dir);
  final String dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const manifest = {
    'version': '1.5.0',
    'build': 30,
    'url': 'https://example.com/app.apk',
    'notes_ar': 'تحسينات',
    'notes_en': 'Improvements',
  };

  http.Client server({int status = 200, Map<String, Object?> json = manifest, List<int>? apk}) =>
      MockClient.streaming((req, _) async {
        if (req.url.path.endsWith('.json')) {
          return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(json))), status);
        }
        final body = apk ?? List.filled(1000, 7);
        return http.StreamedResponse(Stream.fromIterable([body.sublist(0, 500), body.sublist(500)]), 200,
            contentLength: body.length);
      });

  test('a newer build is offered, the same build is not', () async {
    final newer = Updater(client: server(), currentBuild: () async => 22);
    await newer.check();
    expect(newer.state, UpdateState.available);
    expect(newer.hasUpdate, isTrue);
    expect(newer.latest!.version, '1.5.0');
    expect(newer.latest!.notesAr, 'تحسينات');

    final same = Updater(client: server(), currentBuild: () async => 30);
    await same.check();
    expect(same.state, UpdateState.upToDate);
    expect(same.hasUpdate, isFalse);
  });

  test('a failed check says so, a quiet one stays silent', () async {
    final loud = Updater(client: server(status: 500), currentBuild: () async => 22);
    await loud.check();
    expect(loud.state, UpdateState.failed);
    expect(loud.error, 'network');

    final quiet = Updater(client: server(status: 500), currentBuild: () async => 22);
    await quiet.check(quiet: true);
    expect(quiet.state, UpdateState.idle);
    expect(quiet.error, isNull);
  });

  test('the APK downloads with progress before installing', () async {
    final dir = await Directory.systemTemp.createTemp('upd');
    PathProviderPlatform.instance = _Paths(dir.path);
    final u = Updater(client: server(), currentBuild: () async => 22);
    await u.check();
    final seen = <double>[];
    u.addListener(() => seen.add(u.progress));
    await u.install();
    expect(seen, contains(0.5));
    expect(u.progress, 1);
    expect(File('${dir.path}/file-chat-30.apk').lengthSync(), 1000);
  });
}
