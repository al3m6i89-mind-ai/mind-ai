import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_ai/providers/ai_models.dart';
import 'package:mind_ai/providers/text_provider.dart';
import 'package:mind_ai/services/code_service.dart';
import 'package:mind_ai/services/settings_service.dart';
import 'package:mind_ai/services/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Replies from a script, and drops the connection once mid-answer.
class ScriptedText extends TextProvider {
  ScriptedText(super.settings, this.replies);
  final List<String> replies;
  final prompts = <String>[];
  bool dropped = false;

  @override
  Stream<String> chat(List<ChatMessage> history, {String? system, TextBackend? backend}) async* {
    prompts.add(history.last.text);
    final r = replies.removeAt(0);
    if (!dropped && r.contains('DROP')) {
      dropped = true;
      final cut = r.indexOf('DROP');
      yield r.substring(0, cut);
      replies.insert(0, r.substring(cut + 4));
      throw Exception('Connection closed while receiving data');
    }
    yield r;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('new idea goes plan -> each file -> review, surviving a dropped connection', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService.load();
    final subs = SubscriptionService(settings.prefs);
    await subs.grantWelcome();
    final text = ScriptedText(settings, [
      '{"title_ar":"محول PDF","summary_ar":"تطبيق","features_ar":["دمج"],"files":[{"path":"index.html","purpose":"ui"},{"path":"style.css","purpose":"style"},{"path":"app.js","purpose":"logic"}]}',
      '<!doctype html><html dir="rtl"><body><main id="app">DROP</main></body></html>',
      '```css\nbody{color:red}\n```',
      'document.getElementById("app").textContent = "hi";',
      'OK',
    ]);
    final code = CodeService(text, subs, settings);
    await code.init(dir: Directory.systemTemp.createTempSync('mindai'));
    final p = code.create('PdfTools', ProjectType.web);

    final changes = await code.runAgent(p, 'اريد تطبيق يدمج pdf');

    expect(changes.map((c) => c.path), containsAll(['index.html', 'style.css', 'app.js']));
    expect(p.files['index.html'], contains('<main id="app"></main>'));
    expect(text.prompts.where((t) => t.contains('cut off')), hasLength(1));
    expect(p.files['style.css'], 'body{color:red}\n');
    expect(p.chat.last.text, contains('تطبيقك جاهز'));
  });

  test('missing packages are added to pubspec for Flutter projects', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService.load();
    final subs = SubscriptionService(settings.prefs);
    await subs.grantWelcome();
    final text = ScriptedText(settings, [
      '{"title_ar":"مهام","files":[{"path":"lib/main.dart","purpose":"app"},{"path":"pubspec.yaml","purpose":"deps"}]}',
      "import 'package:flutter/material.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\nvoid main() {}",
      CodeService.flutterPubspec('todo_app', 'Todo'),
      'OK',
    ]);
    final code = CodeService(text, subs, settings);
    await code.init(dir: Directory.systemTemp.createTempSync('mindai'));
    final p = code.create('Todo App', ProjectType.flutter);
    await code.runAgent(p, 'تطبيق مهام');
    expect(p.files['pubspec.yaml'], contains('  shared_preferences: any'));
  });
}
