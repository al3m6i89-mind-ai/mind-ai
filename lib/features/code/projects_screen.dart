import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/code_service.dart';
import '../../widgets/common.dart';
import 'workspace_screen.dart';

/// What the agent is asked to make. Everything except [app] is a web project.
enum BuildKind { app, slides, website, game }

extension BuildKindInfo on BuildKind {
  String get label => switch (this) {
    BuildKind.app => '📱 تطبيق',
    BuildKind.slides => '📊 عرض شرائح',
    BuildKind.website => '🌐 موقع',
    BuildKind.game => '🎮 لعبة',
  };

  String get hint => switch (this) {
    BuildKind.app => 'اكتب فكرتك وبس ✨\nمثلاً: تطبيق يدمج ملفات PDF ويصغّر حجمها، بتصميم بنفسجي أنيق',
    BuildKind.slides => 'موضوع العرض وعدد الشرائح ✨\nمثلاً: عرض من ١٠ شرائح عن الذكاء الاصطناعي في التعليم',
    BuildKind.website => 'وش الموقع؟ ✨\nمثلاً: موقع لمطعم برجر فيه قائمة الطعام والأسعار وحجز طاولة وواتساب',
    BuildKind.game => 'وش اللعبة؟ ✨\nمثلاً: لعبة سيارات تتفادى العوائق وتجمع نقاط، بمراحل تصعب تدريجياً',
  };

  /// Added to the request so the agent builds the right kind of thing.
  String get brief => switch (this) {
    BuildKind.app => '',
    BuildKind.slides =>
      'المطلوب: عرض شرائح تقديمي (Presentation) بملء الشاشة، كل شريحة بتصميم مختلف وجذاب، '
          'تنقّل بالسحب والأزرار والأسهم، رقم الشريحة وشريط تقدم، ووضع ملء الشاشة.',
    BuildKind.website =>
      'المطلوب: موقع إلكتروني كامل متجاوب (جوال وكمبيوتر) بأقسام: رئيسية جذابة، '
          'خدمات/منتجات، من نحن، آراء العملاء، تواصل؛ مع قائمة علوية ورسوم حركية عند التمرير.',
    BuildKind.game =>
      'المطلوب: لعبة كاملة تلعب باللمس على الجوال (Canvas + requestAnimationFrame)، '
          'شاشة بداية، نقاط وأعلى نتيجة محفوظة، مستويات تصعب، أصوات بسيطة WebAudio، وزر إعادة.',
  };
}

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  /// Opens the "new project" sheet, optionally preset to slides, a website or a game.
  static Future<void> newProject(BuildContext context, {BuildKind kind = BuildKind.app}) async {
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
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final k in BuildKind.values)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: kind == k,
                      onSelected: (_) => set(() {
                        kind = k;
                        if (k != BuildKind.app) type = ProjectType.web;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: idea,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(hintText: kind.hint),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: name,
                decoration: const InputDecoration(hintText: 'اسم التطبيق (اختياري)'),
              ),
              const SizedBox(height: 12),
              if (kind == BuildKind.app)
                for (final t in ProjectType.values)
                  RadioListTile<ProjectType>(
                    value: t,
                    groupValue: type,
                    onChanged: (v) => set(() => type = v!),
                    title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      t == ProjectType.web
                          ? 'ننصح فيه: يجهز بسرعة، تجربه فوراً، ويتحول لـ APK'
                          : 'تطبيق أندرويد أصلي، يحتاج بناء سحابي لتجربته',
                    ),
                  ),
              const SizedBox(height: 8),
              GradientButton(
                label: kind == BuildKind.app ? 'ابنِ تطبيقي 🚀' : 'ابدأ 🚀',
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final code = context.read<CodeService>();
    final p = code.create(name.text.trim().isEmpty ? 'MyApp' : name.text.trim(), type);
    final text = idea.text.trim();
    final request = text.isEmpty ? null : (kind.brief.isEmpty ? text : '$text\n\n${kind.brief}');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkspaceScreen(project: p, initialRequest: request),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = context.watch<CodeService>();
    return Scaffold(
      appBar: AppBar(
        title: const GradientText('استوديو الأكواد', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => newProject(context),
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
                Text(
                  '👨‍💻 ابنِ تطبيقك بدون كمبيوتر',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                ),
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
              child: Center(
                child: Text('لا توجد مشاريع بعد', style: TextStyle(color: MindColors.muted)),
              ),
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
