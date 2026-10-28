import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../providers/ai_models.dart';
import '../providers/text_provider.dart';
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
  })  : files = files ?? {},
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
  CodeService(this._text, this._subs);

  final TextProvider _text;
  final SubscriptionService _subs;
  final List<CodeProject> projects = [];
  late Directory _dir;
  bool busy = false;

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/projects')..createSync(recursive: true);
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

  static String _systemPrompt(CodeProject p) {
    final kind = p.type == ProjectType.web
        ? 'a mobile-first web app made of index.html, style.css and app.js (plain HTML/CSS/JS, no build step, no CDN that needs a key). It runs inside an Android WebView, so make it touch-friendly, responsive and beautiful.'
        : 'a Flutter (Dart 3, Material 3) Android app. Keep pubspec.yaml valid; only use well-known pub.dev packages. Platform folders are generated in the cloud, so write only pubspec.yaml, lib/** and assets.';
    return '''
You are Mind Ai Code Agent, an expert senior engineer building $kind
The user may write in Arabic; reply to them in Arabic, but write code, identifiers and comments in English.
Support RTL Arabic text in the UI when the app has Arabic content.

Respond with:
1. A short explanation (2-5 lines) of what you did.
2. Every file you create or change, complete (never partial, never "..."), using exactly this format:
<file path="relative/path.ext">
FULL FILE CONTENT
</file>
To delete a file: <delete path="relative/path.ext"/>
Do not wrap files in markdown code fences.''';
  }

  static final _fileRe = RegExp(r'<file path="([^"]+)">\n?([\s\S]*?)\n?</file>');
  static final _deleteRe = RegExp(r'<delete path="([^"]+)"\s*/>');

  /// Sends the request plus the current files to the model and applies the
  /// returned edits. Streams the reply text into the last chat message.
  Future<List<FileChange>> runAgent(CodeProject p, String request, {String? errorLog}) async {
    if (busy) return [];
    _subs.ensure(Usage.codeAgent);
    busy = true;
    final userText = errorLog == null ? request : '$request\n\nBuild log:\n$errorLog';
    p.chat.add(ChatMessage(role: Role.user, text: userText));
    final reply = ChatMessage(role: Role.assistant, text: '');
    p.chat.add(reply);
    notifyListeners();

    final context = StringBuffer('Current project files:\n');
    p.files.forEach((path, content) => context.writeln('<file path="$path">\n$content\n</file>'));

    final history = <ChatMessage>[
      ChatMessage(role: Role.user, text: context.toString()),
      ChatMessage(role: Role.assistant, text: 'Got it. What should I build or change?'),
      // Only the last few turns: the files above already carry the project state.
      ...p.chat.where((m) => m != reply).toList().reversed.take(6).toList().reversed,
    ];

    final changes = <FileChange>[];
    try {
      await for (final t in _text.chat(history, system: _systemPrompt(p))) {
        reply.text += t;
        notifyListeners();
      }
      for (final m in _fileRe.allMatches(reply.text)) {
        final path = _clean(m.group(1)!);
        if (path == null) continue;
        p.files[path] = m.group(2)!;
        changes.add(FileChange(path));
      }
      for (final m in _deleteRe.allMatches(reply.text)) {
        final path = _clean(m.group(1)!);
        if (path != null && p.files.remove(path) != null) changes.add(FileChange(path, deleted: true));
      }
      // Keep the chat readable: replace file bodies with a short marker.
      reply.text = reply.text
          .replaceAllMapped(_fileRe, (m) => '📄 `${m.group(1)}`')
          .replaceAllMapped(_deleteRe, (m) => '🗑️ `${m.group(1)}`')
          .trim();
      await _subs.consume(Usage.codeAgent);
    } catch (e) {
      reply.text = '⚠️ $e';
    } finally {
      busy = false;
      save(p);
    }
    return changes;
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
            'index.html': '''<!doctype html>
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
            'lib/main.dart': '''import 'package:flutter/material.dart';

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

  static String flutterPubspec(String slug, String name, {List<String> deps = const [], List<String> assets = const []}) => '''
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
