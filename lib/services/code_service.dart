import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../providers/ai_models.dart';
import '../providers/text_provider.dart';
import 'settings_service.dart';
import 'subscription_service.dart';

/// web: HTML/CSS/JS with instant in-app preview, wrapped in a WebView shell for APK.
/// flutter: a real Flutter app, compiled to APK in the cloud.
enum ProjectType { web, flutter }

extension ProjectTypeInfo on ProjectType {
  String get label => switch (this) {
    ProjectType.web => 'تطبيق ويب (معاينة فورية)',
    ProjectType.flutter => 'تطبيق Flutter أصلي',
  };
}

class CodeProject {
  CodeProject({
    required this.id,
    required this.name,
    required this.type,
    Map<String, String>? files,
    List<ChatMessage>? chat,
    DateTime? updated,
  }) : files = files ?? {},
       chat = chat ?? [],
       updated = updated ?? DateTime.now();

  final String id;
  String name;
  final ProjectType type;
  final Map<String, String> files;
  final List<ChatMessage> chat;
  DateTime updated;

  /// Lowercase package-safe identifier derived from the name.
  String get slug {
    final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty || RegExp(r'^[0-9]').hasMatch(s) ? 'app_${id.substring(0, 6)}' : s;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'files': files,
    'chat': chat.map((m) => m.toJson()).toList(),
    'updated': updated.toIso8601String(),
  };

  factory CodeProject.fromJson(Map<String, dynamic> j) => CodeProject(
    id: j['id'] as String,
    name: j['name'] as String,
    type: ProjectType.values.byName(j['type'] as String),
    files: Map<String, String>.from(j['files'] as Map),
    chat: (j['chat'] as List? ?? []).map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList(),
    updated: DateTime.tryParse(j['updated'] as String? ?? ''),
  );
}

/// A change the agent made, shown to the user as a list after each turn.
class FileChange {
  FileChange(this.path, {this.deleted = false});
  final String path;
  final bool deleted;
}

class CodeService extends ChangeNotifier {
  CodeService(this._text, this._subs, this._settings);

  final TextProvider _text;
  final SubscriptionService _subs;
  final SettingsService _settings;
  final List<CodeProject> projects = [];
  late Directory _dir;
  bool busy = false;

  Future<void> init({Directory? dir}) async {
    _dir = dir ?? Directory('${(await getApplicationDocumentsDirectory()).path}/projects');
    _dir.createSync(recursive: true);
    for (final f in _dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      try {
        projects.add(CodeProject.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>));
      } catch (_) {}
    }
    projects.sort((a, b) => b.updated.compareTo(a.updated));
  }

  CodeProject create(String name, ProjectType type) {
    final p = CodeProject(id: const Uuid().v4(), name: name, type: type, files: _starter(name, type));
    projects.insert(0, p);
    save(p);
    return p;
  }

  void save(CodeProject p) {
    p.updated = DateTime.now();
    File('${_dir.path}/${p.id}.json').writeAsStringSync(jsonEncode(p.toJson()));
    notifyListeners();
  }

  void delete(CodeProject p) {
    projects.remove(p);
    final f = File('${_dir.path}/${p.id}.json');
    if (f.existsSync()) f.deleteSync();
    notifyListeners();
  }

  // ---------------------------------------------------------------- agent

  static String _designGuide(ProjectType t) => t == ProjectType.web
      ? '''
Design bar: it must look like a top-rated, premium mobile app, never like a tutorial page.
- CSS variables for colors; a vibrant brand gradient (violet #7B5CFF -> pink #FF4FA3 -> orange #FF9F43) unless the idea calls for its own palette.
- System font stack, 16px base, bold headings, rounded 20px cards, soft layered shadows, generous spacing, 44px+ touch targets.
- Multi-screen apps get a sticky top bar and a bottom navigation bar; switch screens with smooth CSS transitions.
- Friendly empty states with an emoji, toasts for feedback, loading states, subtle micro-animations.
- Dark mode with prefers-color-scheme. RTL (dir="rtl", lang="ar") when the app is Arabic.
- Real, working logic end to end: localStorage persistence, validation, no placeholders, no TODO, no lorem ipsum (realistic Arabic sample content).
- You may load well-known libraries from cdnjs.cloudflare.com or cdn.jsdelivr.net (e.g. pdf-lib, Chart.js, jsPDF, mammoth) when they make a feature work for real.
- Presentation / slides: a full-screen deck in index.html, one <section> per slide with real content (titles, short points, stats, charts with Chart.js or CSS), a distinct layout per slide, swipe + arrow keys + buttons, slide counter, progress bar, smooth transitions, and an "export PDF" button using window.print with print CSS (one slide per page).
- Website: a polished responsive landing site (mobile and desktop) with hero, sections, cards, testimonials, contact form/WhatsApp link, sticky nav with smooth scroll and reveal-on-scroll animations.
- Game: a complete canvas game with touch controls sized for phones, start screen, score + best score in localStorage, increasing difficulty, pause, game-over and restart, juicy effects (particles, screen shake), sounds via WebAudio, and 60fps requestAnimationFrame loop that handles devicePixelRatio.'''
      : '''
Design bar: it must look like a top-rated, premium Play Store app.
- Material 3, ColorScheme.fromSeed with a vibrant seed (#7B5CFF unless the idea suggests another), light and dark themes.
- NavigationBar for multi-screen apps, rounded Cards, gradient headers, FloatingActionButton where natural, AnimatedSwitcher/Hero animations, friendly empty states.
- Directionality RTL and Arabic labels when the app is Arabic.
- Real, working logic: shared_preferences persistence, validation, no placeholders, no TODO.
- Compile-ready Dart 3 null-safety: every import resolves, every referenced class/function exists in the project, lib/main.dart has main().
- Only well-known, actively maintained pub.dev packages; list every one in pubspec.yaml. No network fonts.''';

  static String _systemPrompt(CodeProject p) {
    final kind = p.type == ProjectType.web
        ? 'a mobile-first web app (plain HTML/CSS/JS, no build step) that runs inside an Android WebView.'
        : 'a Flutter (Dart 3, Material 3) Android app. Platform folders are generated in the cloud, so write only pubspec.yaml, lib/** and assets.';
    return '''
You are Mind Ai Code Agent, a world-class senior engineer and product designer building $kind
The user may write in Arabic; reply to them in Arabic, but write code, identifiers and comments in English.
${_designGuide(p.type)}

Respond with:
1. A short explanation in Arabic (2-5 lines) of what you did.
2. Every file you create or change, complete (never partial, never "..."), using exactly this format:
<file path="relative/path.ext">
FULL FILE CONTENT
</file>
To delete a file: <delete path="relative/path.ext"/>
Do not wrap files in markdown code fences.''';
  }

  static final _fileRe = RegExp(r'<file path="([^"]+)">\n?([\s\S]*?)\n?</file>');
  static final _deleteRe = RegExp(r'<delete path="([^"]+)"\s*/>');
  static final _importRe = RegExp('import\\s+[\'"]package:([a-z0-9_]+)/');

  /// The agent uses the strongest model that has a key (Claude, then ChatGPT,
  /// then Gemini) because those write far better code than the keyless default.
  TextBackend get _backend => _settings.bestTextBackend;

  /// Asks the model and survives dropped connections: retries, and when an
  /// answer was cut off part-way, asks it to continue from where it stopped.
  Future<String> _ask(
    List<ChatMessage> history,
    String system, {
    void Function(String soFar)? onDelta,
    bool Function(String soFar)? isCut,
  }) async {
    final out = StringBuffer();
    for (var attempt = 0; attempt < 5; attempt++) {
      final msgs = out.isEmpty
          ? history
          : [
              ...history,
              ChatMessage(role: Role.assistant, text: out.toString()),
              ChatMessage(
                role: Role.user,
                text:
                    'Your previous answer was cut off. Continue EXACTLY from the last character. '
                    'Do not repeat anything and do not add any preface.',
              ),
            ];
      try {
        await for (final t in _text.chat(msgs, system: system, backend: _backend)) {
          out.write(t);
          onDelta?.call(out.toString());
        }
        if (isCut == null || !isCut(out.toString())) return out.toString();
      } on QuotaExceeded {
        rethrow;
      } catch (e) {
        if (attempt == 4) {
          if (out.isEmpty) rethrow;
          return out.toString();
        }
        await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    return out.toString();
  }

  static bool _openFileTag(String s) => '<file path='.allMatches(s).length > '</file>'.allMatches(s).length;

  /// Builds or changes the project. A new project goes through plan → write
  /// each file → review; later requests edit the existing files in one pass.
  Future<List<FileChange>> runAgent(CodeProject p, String request, {String? errorLog}) async {
    if (busy) return [];
    _subs.ensure(Usage.codeAgent);
    final fresh = !p.chat.any((m) => m.role == Role.user);
    busy = true;
    final userText = errorLog == null ? request : '$request\n\nBuild log:\n$errorLog';
    p.chat.add(ChatMessage(role: Role.user, text: userText));
    final reply = ChatMessage(role: Role.assistant, text: '');
    p.chat.add(reply);
    notifyListeners();

    var changes = <FileChange>[];
    try {
      changes = fresh && errorLog == null ? await _buildFromIdea(p, request, reply) : await _edit(p, reply);
      if (p.type == ProjectType.flutter) _fixPubspec(p);
      await _subs.consume(Usage.codeAgent);
    } catch (e) {
      reply.text = '${reply.text}\n\n⚠️ $e'.trim();
    } finally {
      busy = false;
      save(p);
    }
    return changes;
  }

  Future<List<FileChange>> _edit(CodeProject p, ChatMessage reply) async {
    final context = StringBuffer('Current project files:\n');
    p.files.forEach((path, content) => context.writeln('<file path="$path">\n$content\n</file>'));
    final history = <ChatMessage>[
      ChatMessage(role: Role.user, text: context.toString()),
      ChatMessage(role: Role.assistant, text: 'Got it. What should I build or change?'),
      // Only the last few turns: the files above already carry the project state.
      ...p.chat.where((m) => m != reply).toList().reversed.take(6).toList().reversed,
    ];
    final text = await _ask(
      history,
      _systemPrompt(p),
      onDelta: (s) {
        reply.text = s;
        notifyListeners();
      },
      isCut: _openFileTag,
    );
    final changes = _apply(p, text);
    reply.text = _summarize(text);
    return changes;
  }

  List<FileChange> _apply(CodeProject p, String text) {
    final changes = <FileChange>[];
    for (final m in _fileRe.allMatches(text)) {
      final path = _clean(m.group(1)!);
      if (path == null) continue;
      p.files[path] = m.group(2)!;
      changes.add(FileChange(path));
    }
    for (final m in _deleteRe.allMatches(text)) {
      final path = _clean(m.group(1)!);
      if (path != null && p.files.remove(path) != null) changes.add(FileChange(path, deleted: true));
    }
    return changes;
  }

  /// Keeps the chat readable: replaces file bodies with a short marker.
  String _summarize(String text) => text
      .replaceAllMapped(_fileRe, (m) => '📄 `${m.group(1)}`')
      .replaceAllMapped(_deleteRe, (m) => '🗑️ `${m.group(1)}`')
      .trim();

  Future<List<FileChange>> _buildFromIdea(CodeProject p, String idea, ChatMessage reply) async {
    void show(String s) {
      reply.text = s;
      notifyListeners();
    }

    // 1. Plan
    show('🧭 أخطط لتطبيقك…');
    final web = p.type == ProjectType.web;
    final planText = await _ask(
      [ChatMessage(role: Role.user, text: 'App idea from the user:\n$idea')],
      '''
You are a senior product designer and architect. Plan a complete, polished ${web ? 'mobile web app (HTML/CSS/JS)' : 'Flutter Android app'} for this idea.
Reply with ONLY one JSON object, no markdown:
{"title_ar": "...", "summary_ar": "one or two Arabic sentences", "features_ar": ["..."], "screens_ar": ["..."],
 "palette": "short description of colors and style", "files": [{"path": "...", "purpose": "what this file contains"}]}
Rules: 3 to ${web ? 6 : 10} files. ${web ? 'Must include index.html, style.css and app.js.' : 'Must include pubspec.yaml and lib/main.dart; split screens and models into lib/screens, lib/models, lib/widgets.'}
Every feature the user asked for must be in features_ar and actually implemented by some file.''',
    );
    final plan = _parseJson(planText);
    if (p.name == 'MyApp' && '${plan['title_ar'] ?? ''}'.isNotEmpty) p.name = '${plan['title_ar']}';
    final files = <Map<String, String>>[
      for (final f in (plan['files'] as List? ?? const []))
        if (f is Map && _clean('${f['path']}') != null)
          {'path': _clean('${f['path']}')!, 'purpose': '${f['purpose'] ?? ''}'},
    ];
    for (final must in web ? ['index.html', 'style.css', 'app.js'] : ['pubspec.yaml', 'lib/main.dart']) {
      if (!files.any((f) => f['path'] == must)) files.insert(0, {'path': must, 'purpose': 'required entry file'});
    }
    if (!web) {
      // pubspec last: it can then list exactly the packages the code imports.
      final pub = files.firstWhere((f) => f['path'] == 'pubspec.yaml');
      files
        ..remove(pub)
        ..add(pub);
    }

    final features = (plan['features_ar'] as List? ?? const []).map((e) => '- $e').join('\n');
    final header = StringBuffer()
      ..writeln('## ${plan['title_ar'] ?? p.name}')
      ..writeln(plan['summary_ar'] ?? '')
      ..writeln()
      ..writeln(features)
      ..writeln();
    final progress = <String, String>{for (final f in files) f['path']!: '⏳'};
    String board() => '$header\n${progress.entries.map((e) => '${e.value} `${e.key}`').join('\n')}';
    show(board());

    // 2. Write every file on its own: short answers rarely drop and stay complete.
    final planJson = jsonEncode(plan);
    final written = <String, String>{};
    p.files.clear();
    for (final f in files) {
      final path = f['path']!;
      progress[path] = '✍️';
      show(board());
      final ctx = StringBuffer()
        ..writeln('User idea:\n$idea\n')
        ..writeln('Plan:\n$planJson\n')
        ..writeln('All files in the project:')
        ..writeln(files.map((e) => '- ${e['path']}: ${e['purpose']}').join('\n'))
        ..writeln();
      var budget = 45000;
      for (final e in written.entries) {
        if (budget <= 0) break;
        final body = e.value.length <= budget ? e.value : '${e.value.substring(0, budget)}\n…';
        budget -= body.length;
        ctx.writeln('<file path="${e.key}">\n$body\n</file>');
      }
      ctx.writeln(
        '\nNow write the COMPLETE content of `$path` (${f['purpose']}). '
        'It must work with the files above and the ones still to be written. '
        'Output ONLY the raw file content: no explanation, no markdown fences.',
      );
      final raw = await _ask([
        ChatMessage(role: Role.user, text: ctx.toString()),
      ], 'You are a world-class engineer and UI designer.\n${_designGuide(p.type)}');
      final content = _stripFences(raw);
      written[path] = content;
      p.files[path] = content;
      progress[path] = '✅';
      show(board());
    }

    // 3. Review: one pass to catch broken references between files.
    progress['مراجعة الكود'] = '🔍';
    show(board());
    final all = StringBuffer();
    written.forEach((k, v) => all.writeln('<file path="$k">\n$v\n</file>'));
    if (all.length < 120000) {
      try {
        final review = await _ask(
          [ChatMessage(role: Role.user, text: 'User idea:\n$idea\n\nProject:\n$all')],
          '''
You are a meticulous code reviewer. Find real bugs that would break the app: missing imports or packages, undefined or misspelled names,
mismatched IDs between HTML/CSS/JS, wrong file references, features from the idea that are missing, syntax errors.
If everything is correct reply exactly: OK
Otherwise output only the corrected files, complete, in this format:
<file path="relative/path.ext">
FULL FILE CONTENT
</file>''',
          isCut: _openFileTag,
        );
        _apply(p, review);
      } catch (_) {
        // The app is already complete; a failed review just skips the extra polish.
      }
    }
    progress['مراجعة الكود'] = '✅';
    reply.text =
        '${board()}\n\n🎉 **تطبيقك جاهز!** '
        '${web ? 'افتح تبويب **معاينة** لتجربته، ثم' : 'اذهب إلى'} **بناء APK** لتثبيته على جوالك. واطلب أي تعديل هنا.';
    notifyListeners();
    return [for (final path in p.files.keys) FileChange(path)];
  }

  static Map<String, dynamic> _parseJson(String s) {
    final a = s.indexOf('{'), b = s.lastIndexOf('}');
    if (a < 0 || b <= a) throw Exception('تعذّر فهم خطة التطبيق، حاول مرة ثانية.');
    return jsonDecode(s.substring(a, b + 1)) as Map<String, dynamic>;
  }

  static String _stripFences(String s) {
    var t = s.trim();
    final m = RegExp(r'^```[a-zA-Z0-9_+-]*\n([\s\S]*?)\n?```$').firstMatch(t);
    if (m != null) t = m.group(1)!;
    t = t.replaceFirst(RegExp(r'^<file path="[^"]+">\n?'), '').replaceFirst(RegExp(r'\n?</file>$'), '');
    return '$t\n';
  }

  /// Adds any package the Dart code imports but pubspec.yaml forgot, the most
  /// common reason a generated Flutter app fails to build.
  void _fixPubspec(CodeProject p) {
    var pub = p.files['pubspec.yaml'];
    if (pub == null || !pub.contains('dependencies:')) pub = flutterPubspec(p.slug, p.name);
    final name = RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pub)?.group(1) ?? p.slug;
    final used = <String>{};
    for (final e in p.files.entries.where((e) => e.key.endsWith('.dart'))) {
      for (final m in _importRe.allMatches(e.value)) {
        used.add(m.group(1)!);
      }
    }
    used.removeAll({'flutter', 'flutter_test', name});
    final current = pub;
    final missing = used.where((pkg) => !RegExp('^\\s+$pkg:', multiLine: true).hasMatch(current)).toList();
    if (missing.isNotEmpty) {
      pub = pub.replaceFirstMapped(
        RegExp(r'dependencies:\s*\n\s+flutter:\s*\n\s+sdk: flutter\n'),
        (m) => '${m.group(0)}${missing.map((pkg) => '  $pkg: any\n').join()}',
      );
    }
    p.files['pubspec.yaml'] = pub;
  }

  /// Rejects absolute paths and `..` so the agent can't write outside the project.
  String? _clean(String path) {
    final p = path.trim().replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '');
    if (p.isEmpty || p.startsWith('/') || p.split('/').contains('..')) return null;
    if (p.startsWith('.github/')) return null;
    return p;
  }

  // ---------------------------------------------------------------- starters

  Map<String, String> _starter(String name, ProjectType type) => switch (type) {
    ProjectType.web => {
      'index.html':
          '''<!doctype html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$name</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <main class="card">
    <h1>$name</h1>
    <p>اطلب من وكيل Mind Ai أن يبني تطبيقك هنا ✨</p>
    <button id="btn">اضغطني</button>
  </main>
  <script src="app.js"></script>
</body>
</html>
''',
      'style.css': '''body{margin:0;min-height:100vh;display:grid;place-items:center;font-family:system-ui,sans-serif;
background:linear-gradient(135deg,#7B5CFF,#FF4FA3,#FF9F43)}
.card{background:#fff;border-radius:24px;padding:32px;text-align:center;box-shadow:0 20px 60px #0003;width:min(88vw,380px)}
h1{margin:0 0 8px;color:#1B1530}
button{border:0;border-radius:14px;padding:12px 24px;font-size:16px;color:#fff;background:#7B5CFF}
''',
      'app.js': '''document.getElementById('btn').addEventListener('click', () => {
  alert('مرحباً من Mind Ai 👋');
});
''',
    },
    ProjectType.flutter => {
      'pubspec.yaml': flutterPubspec(_slugOf(name), name),
      'lib/main.dart':
          '''import 'package:flutter/material.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$name',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF7B5CFF), useMaterial3: true),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: Text('$name', style: TextStyle(fontSize: 28)))),
      ),
    );
  }
}
''',
    },
  };

  static String _slugOf(String name) {
    final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty || RegExp(r'^[0-9]').hasMatch(s) ? 'my_app' : s;
  }

  static String flutterPubspec(
    String slug,
    String name, {
    List<String> deps = const [],
    List<String> assets = const [],
  }) =>
      '''
name: $slug
description: "$name — built with Mind Ai"
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter
${deps.map((d) => '  $d').join('\n')}

flutter:
  uses-material-design: true
${assets.isEmpty ? '' : '  assets:\n${assets.map((a) => '    - $a').join('\n')}'}
''';
}
