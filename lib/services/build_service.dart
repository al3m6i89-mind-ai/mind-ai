import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'code_service.dart';
import 'settings_service.dart';

enum BuildStage { idle, uploading, queued, building, downloading, done, failed }

extension BuildStageInfo on BuildStage {
  String get label => switch (this) {
        BuildStage.idle => 'جاهز',
        BuildStage.uploading => 'رفع المشروع إلى GitHub…',
        BuildStage.queued => 'في الطابور…',
        BuildStage.building => 'جاري البناء في السحابة (3-6 دقائق)…',
        BuildStage.downloading => 'تنزيل الـ APK…',
        BuildStage.done => 'تم! الـ APK جاهز',
        BuildStage.failed => 'فشل البناء',
      };
}

/// The "Android Studio in the cloud": pushes the project to the user's GitHub
/// repo on its own branch, lets GitHub Actions compile it (free for public
/// repos, 2000 min/month for private), then downloads the APK to the phone.
class BuildService extends ChangeNotifier {
  BuildService(this.settings);

  final SettingsService settings;
  BuildStage stage = BuildStage.idle;
  String? apkPath;
  String? runUrl;
  String? errorLog;
  String? projectId;

  static const _api = 'https://api.github.com';

  Map<String, String> get _h => {
        'Authorization': 'Bearer ${settings.githubToken}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  String get _repo => settings.githubRepo;

  void _set(BuildStage s) {
    stage = s;
    notifyListeners();
  }

  Future<void> build(CodeProject p) async {
    if (!settings.githubReady) {
      throw Exception('اربط حساب GitHub من الإعدادات أولاً (رمز الوصول واسم المستودع).');
    }
    projectId = p.id;
    apkPath = null;
    runUrl = null;
    errorLog = null;
    try {
      _set(BuildStage.uploading);
      final branch = 'mindai/${p.slug}';
      final files = buildTree(p);
      final sha = await _pushBranch(branch, files, 'Mind Ai: build ${p.name}');

      _set(BuildStage.queued);
      final run = await _waitForRun(branch, sha);
      runUrl = run['html_url'] as String?;

      _set(BuildStage.building);
      final done = await _waitForCompletion(run['id'] as int);
      if (done['conclusion'] != 'success') {
        errorLog = await _failureLog(done['id'] as int);
        _set(BuildStage.failed);
        return;
      }

      _set(BuildStage.downloading);
      apkPath = await _downloadApk(done['id'] as int, p.slug);
      _set(BuildStage.done);
    } catch (e) {
      errorLog = e.toString();
      _set(BuildStage.failed);
    }
  }

  /// Files that go to GitHub: the project plus the CI workflow, and for web
  /// projects a Flutter WebView shell that packages the HTML as an APK.
  static Map<String, String> buildTree(CodeProject p) {
    final out = <String, String>{'.github/workflows/mindai-build.yml': workflowYaml};
    if (p.type == ProjectType.flutter) {
      out.addAll(p.files);
      return out;
    }
    for (final e in p.files.entries) {
      out['assets/www/${e.key}'] = e.value;
    }
    out['pubspec.yaml'] = CodeService.flutterPubspec(
      p.slug,
      p.name,
      deps: ['webview_flutter: ^4.10.0'],
      assets: ['assets/www/'],
    );
    out['lib/main.dart'] = _webShell(p.name);
    return out;
  }

  static const workflowYaml = r'''
name: Mind Ai Build
on:
  push:
    branches: ['mindai/**']
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - name: Generate Android platform files
        run: |
          NAME=$(grep -m1 '^name:' pubspec.yaml | awk '{print $2}')
          if [ ! -d android ]; then
            flutter create --org com.mindai.apps --project-name "$NAME" --platforms android .
          fi
          sed -i 's/<application/<uses-permission android:name="android.permission.INTERNET"\/>\n    <application/' android/app/src/main/AndroidManifest.xml || true
      - run: flutter pub get
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v4
        with:
          name: app-release
          path: build/app/outputs/flutter-apk/app-release.apk
          retention-days: 7
''';

  static String _webShell(String name) => '''
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(const ShellApp());

class ShellApp extends StatelessWidget {
  const ShellApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: ${jsonEncode(name)},
        debugShowCheckedModeBanner: false,
        home: const WebHome(),
      );
}

class WebHome extends StatefulWidget {
  const WebHome({super.key});

  @override
  State<WebHome> createState() => _WebHomeState();
}

class _WebHomeState extends State<WebHome> {
  late final WebViewController _c = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadFlutterAsset('assets/www/index.html');

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (await _c.canGoBack()) {
            _c.goBack();
          } else if (context.mounted) {
            Navigator.of(context).maybePop();
          }
        },
        child: Scaffold(body: SafeArea(child: WebViewWidget(controller: _c))),
      );
}
''';

  // ---------------------------------------------------------------- GitHub API

  Future<dynamic> _get(String path) async {
    final r = await http.get(Uri.parse('$_api$path'), headers: _h);
    if (r.statusCode == 404) return null;
    _ok(r);
    return jsonDecode(r.body);
  }

  Future<dynamic> _send(String method, String path, Map<String, dynamic> body) async {
    final req = http.Request(method, Uri.parse('$_api$path'))
      ..headers.addAll({..._h, 'Content-Type': 'application/json'})
      ..body = jsonEncode(body);
    final r = await http.Response.fromStream(await req.send());
    _ok(r);
    return jsonDecode(r.body);
  }

  void _ok(http.Response r) {
    if (r.statusCode == 401) throw Exception('رمز GitHub غير صالح أو منتهي.');
    if (r.statusCode == 403) {
      throw Exception('الرمز لا يملك صلاحية كافية. فعّل Contents و Actions (قراءة وكتابة) و Workflows.');
    }
    if (r.statusCode >= 400) throw Exception('GitHub ${r.statusCode}: ${r.body}');
  }

  Future<String> _pushBranch(String branch, Map<String, String> files, String message) async {
    final repo = await _get('/repos/$_repo');
    if (repo == null) throw Exception('المستودع $_repo غير موجود أو لا يمكن الوصول إليه.');

    final defaultBranch = repo['default_branch'] as String? ?? 'main';
    var base = await _get('/repos/$_repo/git/ref/heads/$branch');
    base ??= await _get('/repos/$_repo/git/ref/heads/$defaultBranch');
    if (base == null) {
      // Empty repository: the Git Data API needs one commit to exist first.
      await _send('PUT', '/repos/$_repo/contents/README.md', {
        'message': 'Initialize for Mind Ai',
        'content': base64Encode(utf8.encode('# Mind Ai builds\n\nكل مشروع من Mind Ai يُبنى هنا في فرع خاص به.\n')),
      });
      base = await _get('/repos/$_repo/git/ref/heads/$defaultBranch');
    }
    final parent = base['object']['sha'] as String;

    final tree = await _send('POST', '/repos/$_repo/git/trees', {
      'tree': [
        for (final e in files.entries) {'path': e.key, 'mode': '100644', 'type': 'blob', 'content': e.value},
      ],
    });
    final commit = await _send('POST', '/repos/$_repo/git/commits', {
      'message': message,
      'tree': tree['sha'],
      'parents': [parent],
    });
    final sha = commit['sha'] as String;
    final exists = await _get('/repos/$_repo/git/ref/heads/$branch');
    if (exists == null) {
      await _send('POST', '/repos/$_repo/git/refs', {'ref': 'refs/heads/$branch', 'sha': sha});
    } else {
      await _send('PATCH', '/repos/$_repo/git/refs/heads/$branch', {'sha': sha, 'force': true});
    }
    return sha;
  }

  Future<Map<String, dynamic>> _waitForRun(String branch, String sha) async {
    final until = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(until)) {
      final j = await _get('/repos/$_repo/actions/runs?head_sha=$sha&per_page=5');
      final runs = (j?['workflow_runs'] as List?) ?? const [];
      if (runs.isNotEmpty) return runs.first as Map<String, dynamic>;
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    throw Exception('لم يبدأ البناء. تأكد أن GitHub Actions مفعّل في المستودع.');
  }

  Future<Map<String, dynamic>> _waitForCompletion(int runId) async {
    final until = DateTime.now().add(const Duration(minutes: 35));
    while (DateTime.now().isBefore(until)) {
      final run = await _get('/repos/$_repo/actions/runs/$runId') as Map<String, dynamic>;
      if (run['status'] == 'completed') return run;
      await Future<void>.delayed(const Duration(seconds: 10));
    }
    throw Exception('تجاوز البناء الوقت المسموح.');
  }

  /// Pulls the failing step's log so the code agent can fix the error.
  Future<String> _failureLog(int runId) async {
    try {
      final jobs = await _get('/repos/$_repo/actions/runs/$runId/jobs');
      final job = ((jobs['jobs'] as List).first) as Map<String, dynamic>;
      final failed = (job['steps'] as List).firstWhere((s) => s['conclusion'] == 'failure', orElse: () => null);
      final req = http.Request('GET', Uri.parse('$_api/repos/$_repo/actions/jobs/${job['id']}/logs'))
        ..headers.addAll(_h)
        ..followRedirects = false;
      final res = await req.send();
      final loc = res.headers['location'];
      if (loc == null) return 'فشلت خطوة: ${failed?['name'] ?? 'غير معروفة'}';
      final log = await http.read(Uri.parse(loc));
      final lines = log.split('\n').where((l) => l.contains('Error') || l.contains('error') || l.contains('FAILURE')).toList();
      final tail = log.split('\n');
      final picked = lines.isNotEmpty ? lines.take(40) : tail.skip(tail.length > 60 ? tail.length - 60 : 0);
      return 'Failed step: ${failed?['name']}\n${picked.join('\n')}';
    } catch (e) {
      return 'فشل البناء. افتح السجل على GitHub للتفاصيل.';
    }
  }

  Future<String> _downloadApk(int runId, String slug) async {
    final arts = await _get('/repos/$_repo/actions/runs/$runId/artifacts');
    final list = (arts['artifacts'] as List?) ?? const [];
    if (list.isEmpty) throw Exception('لم يتم العثور على ملف APK.');
    final id = list.first['id'];
    // GitHub answers with a redirect to signed storage that must not get our token.
    final req = http.Request('GET', Uri.parse('$_api/repos/$_repo/actions/artifacts/$id/zip'))
      ..headers.addAll(_h)
      ..followRedirects = false;
    final res = await req.send();
    final loc = res.headers['location'];
    final zipBytes = loc != null ? await http.readBytes(Uri.parse(loc)) : await res.stream.toBytes();
    final zip = ZipDecoder().decodeBytes(zipBytes);
    final apk = zip.files.firstWhere((f) => f.name.endsWith('.apk'));
    final dir = await getApplicationDocumentsDirectory();
    final out = File('${dir.path}/apks/$slug.apk')..createSync(recursive: true);
    await out.writeAsBytes(apk.content as List<int>);
    return out.path;
  }
}
