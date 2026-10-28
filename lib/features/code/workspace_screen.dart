import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../providers/ai_models.dart';
import '../../services/code_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/common.dart';
import '../chat/chat_input.dart';
import 'build_panel.dart';
import 'editor_screen.dart';
import 'preview_screen.dart';

/// The phone-sized IDE: Agent chat, file tree + editor, live preview, cloud build.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.project, this.initialRequest});
  final CodeProject project;
  final String? initialRequest;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: widget.project.type == ProjectType.web ? 4 : 3, vsync: this);

  @override
  void initState() {
    super.initState();
    if (widget.initialRequest != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask(widget.initialRequest!));
    }
  }

  Future<void> _ask(String text, {String? log}) async {
    try {
      final changes = await context.read<CodeService>().runAgent(widget.project, text, errorLog: log);
      if (!mounted || changes.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم تحديث ${changes.length} ملف'),
          action: widget.project.type == ProjectType.web
              ? SnackBarAction(label: 'معاينة', onPressed: () => _tabs.animateTo(2))
              : null,
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final web = p.type == ProjectType.web;
    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        bottom: TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800),
          indicatorColor: MindColors.pink,
          tabs: [
            const Tab(icon: Icon(Icons.smart_toy_outlined), text: 'الوكيل'),
            const Tab(icon: Icon(Icons.folder_open), text: 'الملفات'),
            if (web) const Tab(icon: Icon(Icons.play_circle_outline), text: 'معاينة'),
            const Tab(icon: Icon(Icons.android), text: 'بناء APK'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _AgentTab(project: p, onAsk: _ask),
          FilesTab(project: p),
          if (web) PreviewTab(project: p),
          BuildPanel(
            project: p,
            onFixWithAgent: (log) {
              _tabs.animateTo(0);
              _ask('البناء فشل. أصلح الأخطاء التالية:', log: log);
            },
          ),
        ],
      ),
    );
  }
}

class _AgentTab extends StatelessWidget {
  const _AgentTab({required this.project, required this.onAsk});
  final CodeProject project;
  final void Function(String) onAsk;

  static const _quick = ['أضف وضع ليلي', 'حسّن التصميم وخلّه أجمل', 'أضف صفحة إعدادات', 'اشرح لي الكود'];

  @override
  Widget build(BuildContext context) {
    final code = context.watch<CodeService>();
    final chat = project.chat;
    return Column(
      children: [
        Expanded(
          child: chat.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🤖', style: TextStyle(fontSize: 56)),
                        const Text('وكيل الأكواد جاهز', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        const Text(
                          'قل له وش تبي يبني أو يعدّل، وهو يكتب الملفات كاملة.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: MindColors.muted),
                        ),
                        const SizedBox(height: 12),
                        const QuotaPill(Usage.codeAgent),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: chat.length,
                  itemBuilder: (context, i) {
                    final m = chat[chat.length - 1 - i];
                    final me = m.role == Role.user;
                    return Align(
                      alignment: me ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
                        decoration: BoxDecoration(
                          gradient: me ? MindColors.cool : null,
                          color: me ? null : Theme.of(context).cardTheme.color,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: me
                            ? Text(
                                m.text.length > 400 ? '${m.text.substring(0, 400)}…' : m.text,
                                style: const TextStyle(color: Colors.white),
                              )
                            : m.text.isEmpty
                            ? const Text('⏳ الوكيل يفكر ويكتب الكود…')
                            : MarkdownBody(data: _livePreview(m.text)),
                      ),
                    );
                  },
                ),
        ),
        if (!code.busy)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final q in _quick)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ActionChip(label: Text(q), onPressed: () => onAsk(q)),
                  ),
              ],
            ),
          ),
        ChatInput(busy: code.busy, hint: 'اطلب ميزة أو تعديل…', onSend: (text, _) => onAsk(text)),
      ],
    );
  }

  /// While streaming, collapse file bodies so the chat doesn't fill with code.
  String _livePreview(String t) {
    final open = RegExp(r'<file path="([^"]+)">[\s\S]*?(</file>|$)');
    return t.replaceAllMapped(open, (m) => m.group(2) == '</file>' ? '📄 `${m.group(1)}`' : '✍️ يكتب `${m.group(1)}`…');
  }
}
