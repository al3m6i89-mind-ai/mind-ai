import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/code_service.dart';

/// Live preview for web projects: writes the files to a temp folder and loads
/// index.html so relative CSS/JS links work exactly as in the built APK.
class PreviewTab extends StatefulWidget {
  const PreviewTab({super.key, required this.project});
  final CodeProject project;

  @override
  State<PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends State<PreviewTab> {
  final _web = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted);
  DateTime? _loaded;
  final _console = <String>[];

  @override
  void initState() {
    super.initState();
    _web.setOnConsoleMessage((m) => setState(() {
          _console.add('[${m.level.name}] ${m.message}');
          if (_console.length > 50) _console.removeAt(0);
        }));
    _reload();
  }

  Future<void> _reload() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/preview/${widget.project.id}');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    widget.project.files.forEach((path, content) {
      File('${dir.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    });
    _console.clear();
    await _web.loadFile('${dir.path}/index.html');
    _loaded = widget.project.updated;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    context.watch<CodeService>();
    if (_loaded != null && widget.project.updated.isAfter(_loaded!)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }
    final errors = _console.where((l) => l.startsWith('[error]')).length;
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(10),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.black12, width: 6),
            ),
            child: WebViewWidget(controller: _web),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              FilledButton.tonalIcon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => Directionality(
                    textDirection: TextDirection.ltr,
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        if (_console.isEmpty) const Text('No console output'),
                        for (final l in _console)
                          Text(l, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: l.startsWith('[error]') ? Colors.red : null)),
                      ],
                    ),
                  ),
                ),
                icon: Icon(Icons.terminal, color: errors > 0 ? Colors.red : null),
                label: Text(errors > 0 ? 'الكونسول ($errors خطأ)' : 'الكونسول'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
