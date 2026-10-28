import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

import '../../app/theme.dart';
import '../../services/code_service.dart';

class FilesTab extends StatelessWidget {
  const FilesTab({super.key, required this.project});
  final CodeProject project;

  Future<void> _newFile(BuildContext context) async {
    final c = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ملف جديد'),
        content: TextField(
          controller: c,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: 'lib/screens/home.dart'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('إنشاء')),
        ],
      ),
    );
    if (path == null || path.isEmpty || !context.mounted) return;
    project.files[path] = '';
    context.read<CodeService>().save(project);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(project: project, path: path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<CodeService>();
    final paths = project.files.keys.toList()..sort();
    return Scaffold(
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => _newFile(context),
        child: const Icon(Icons.note_add_outlined),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: paths.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final path = paths[i];
          final lines = '\n'.allMatches(project.files[path]!).length + 1;
          return ListTile(
            tileColor: Theme.of(context).cardTheme.color,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: Text(_icon(path), style: const TextStyle(fontSize: 20)),
            title: Text(
              path,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
            subtitle: Text('$lines سطر'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () {
                project.files.remove(path);
                context.read<CodeService>().save(project);
              },
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EditorScreen(project: project, path: path),
              ),
            ),
          );
        },
      ),
    );
  }

  static String _icon(String p) {
    if (p.endsWith('.dart')) return '🎯';
    if (p.endsWith('.html')) return '🌐';
    if (p.endsWith('.css')) return '🎨';
    if (p.endsWith('.js')) return '⚡';
    if (p.endsWith('.yaml') || p.endsWith('.json')) return '⚙️';
    return '📄';
  }
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.project, required this.path});
  final CodeProject project;
  final String path;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final _controller = CodeLineEditingController.fromText(widget.project.files[widget.path] ?? '');
  bool _dirty = false;

  Mode get _lang {
    final p = widget.path;
    if (p.endsWith('.dart')) return langDart;
    if (p.endsWith('.css')) return langCss;
    if (p.endsWith('.js')) return langJavascript;
    if (p.endsWith('.json')) return langJson;
    if (p.endsWith('.yaml') || p.endsWith('.yml')) return langYaml;
    return langXml;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (!_dirty && _controller.text != widget.project.files[widget.path]) setState(() => _dirty = true);
    });
  }

  void _save() {
    widget.project.files[widget.path] = _controller.text;
    context.read<CodeService>().save(widget.project);
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('تم الحفظ 💾'), duration: Duration(seconds: 1)));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _dirty) {
          widget.project.files[widget.path] = _controller.text;
          context.read<CodeService>().save(widget.project);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1A2E),
        appBar: AppBar(
          foregroundColor: Colors.white,
          title: Text(
            widget.path.split('/').last,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 16),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () => Clipboard.setData(ClipboardData(text: _controller.text)),
            ),
            IconButton(
              icon: Icon(Icons.save_outlined, color: _dirty ? MindColors.orange : Colors.white),
              onPressed: _save,
            ),
          ],
        ),
        body: Directionality(
          textDirection: TextDirection.ltr,
          child: CodeEditor(
            controller: _controller,
            wordWrap: false,
            style: CodeEditorStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              backgroundColor: const Color(0xFF1E1A2E),
              codeTheme: CodeHighlightTheme(
                languages: {'code': CodeHighlightThemeMode(mode: _lang)},
                theme: atomOneDarkTheme,
              ),
            ),
            indicatorBuilder: (context, editingController, chunkController, notifier) => Row(
              children: [DefaultCodeLineNumber(controller: editingController, notifier: notifier)],
            ),
          ),
        ),
      ),
    );
  }
}
