import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/code_service.dart';
import '../../widgets/common.dart';
import 'workspace_screen.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  Future<void> _new(BuildContext context) async {
    final name = TextEditingController();
    final idea = TextEditingController();
    var type = ProjectType.web;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(ctx).bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('مشروع جديد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(hintText: 'اسم التطبيق (بالإنجليزي أفضل) مثلاً: TodoApp')),
              const SizedBox(height: 10),
              TextField(
                controller: idea,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(hintText: 'صف فكرة التطبيق… مثلاً: تطبيق مهام بألوان زاهية مع تذكيرات وتصنيفات'),
              ),
              const SizedBox(height: 12),
              for (final t in ProjectType.values)
                RadioListTile<ProjectType>(
                  value: t,
                  groupValue: type,
                  onChanged: (v) => set(() => type = v!),
                  title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(t == ProjectType.web
                      ? 'الأسرع: تشوفه فوراً داخل التطبيق ويتحول لـ APK'
                      : 'تطبيق أندرويد أصلي بأداء عالي، يُبنى في السحابة'),
                ),
              const SizedBox(height: 8),
              GradientButton(label: 'ابدأ البناء 🚀', onPressed: () => Navigator.pop(ctx, true)),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final code = context.read<CodeService>();
    final p = code.create(name.text.trim().isEmpty ? 'MyApp' : name.text.trim(), type);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkspaceScreen(project: p, initialRequest: idea.text.trim().isEmpty ? null : idea.text.trim()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final code = context.watch<CodeService>();
    return Scaffold(
      appBar: AppBar(
        title: const GradientText('استوديو الأكواد', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _new(context),
        backgroundColor: MindColors.violet,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('مشروع جديد', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: MindColors.cool, borderRadius: BorderRadius.circular(24)),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('👨‍💻 ابنِ تطبيقك بدون كمبيوتر',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text(
                  'صف فكرتك ← الوكيل يكتب الكود ← عدّل في المحرر ← شاهد المعاينة ← ابنِ APK في السحابة وثبّته على جوالك.',
                  style: TextStyle(color: Colors.white, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (code.projects.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: Text('لا توجد مشاريع بعد', style: TextStyle(color: MindColors.muted))),
            ),
          for (final p in code.projects)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: CircleAvatar(
                  backgroundColor: MindColors.violet.withValues(alpha: 0.12),
                  child: Text(p.type == ProjectType.web ? '🌐' : '📱'),
                ),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${p.files.length} ملفات · ${p.type == ProjectType.web ? 'ويب' : 'Flutter'}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'delete') code.delete(p);
                  },
                  itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('حذف'))],
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkspaceScreen(project: p))),
              ),
            ),
        ],
      ),
    );
  }
}
