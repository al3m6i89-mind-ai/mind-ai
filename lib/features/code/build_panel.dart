import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../services/build_service.dart';
import '../../services/code_service.dart';
import '../../services/library_service.dart';
import '../../services/settings_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/common.dart';
import '../settings/settings_screen.dart';

class BuildPanel extends StatelessWidget {
  const BuildPanel({super.key, required this.project, required this.onFixWithAgent});
  final CodeProject project;
  final void Function(String log) onFixWithAgent;

  Future<void> _build(BuildContext context) async {
    final subs = context.read<SubscriptionService>();
    final builder = context.read<BuildService>();
    try {
      subs.ensure(Usage.apkBuild);
      await subs.consume(Usage.apkBuild);
      await builder.build(project);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final b = context.watch<BuildService>();
    final mine = b.projectId == project.id;
    final stage = mine ? b.stage : BuildStage.idle;
    final running = const [
      BuildStage.uploading,
      BuildStage.queued,
      BuildStage.building,
      BuildStage.downloading,
    ].contains(stage);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: MindColors.fresh, borderRadius: BorderRadius.circular(24)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '☁️ بديل Android Studio',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 6),
              Text(
                'نرفع مشروعك لمستودعك على GitHub، ويُبنى مجاناً على خوادم GitHub Actions، ثم ينزل ملف APK على جوالك جاهز للتثبيت.',
                style: TextStyle(color: Colors.white, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!settings.githubReady) ...[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'لتفعيل البناء: أضف رمز GitHub (Fine-grained token) واسم المستودع من الإعدادات ← البناء السحابي.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.link),
            label: const Text('ربط GitHub'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(child: Text('المستودع: ${settings.githubRepo}', textDirection: TextDirection.ltr)),
              const QuotaPill(Usage.apkBuild),
            ],
          ),
          const SizedBox(height: 12),
          GradientButton(
            label: running ? stage.label : 'ابنِ APK الآن',
            icon: Icons.rocket_launch_outlined,
            gradient: MindColors.fresh,
            loading: running,
            onPressed: () => _build(context),
          ),
        ],
        const SizedBox(height: 20),
        if (mine && stage != BuildStage.idle) _Steps(stage: stage),
        if (mine && b.runUrl != null)
          TextButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text('فتح سجل البناء على GitHub'),
            onPressed: () => launchUrl(Uri.parse(b.runUrl!), mode: LaunchMode.externalApplication),
          ),
        if (mine && stage == BuildStage.done && b.apkPath != null) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.install_mobile),
            label: const Text('ثبّت التطبيق'),
            onPressed: () => OpenFilex.open(b.apkPath!, type: 'application/vnd.android.package-archive'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('مشاركة ملف APK'),
            onPressed: () => LibraryService.share(b.apkPath!),
          ),
        ],
        if (mine && stage == BuildStage.failed && b.errorLog != null) ...[
          Card(
            color: Colors.red.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  b.errorLog!.length > 1500 ? b.errorLog!.substring(0, 1500) : b.errorLog!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          GradientButton(label: 'خلّ الوكيل يصلح الخطأ 🛠️', onPressed: () => onFixWithAgent(b.errorLog!)),
        ],
      ],
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.stage});
  final BuildStage stage;

  @override
  Widget build(BuildContext context) {
    const steps = [
      BuildStage.uploading,
      BuildStage.queued,
      BuildStage.building,
      BuildStage.downloading,
      BuildStage.done,
    ];
    final current = stage == BuildStage.failed ? -1 : steps.indexOf(stage);
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          ListTile(
            dense: true,
            leading: Icon(
              stage == BuildStage.failed
                  ? Icons.error_outline
                  : i < current || stage == BuildStage.done
                  ? Icons.check_circle
                  : i == current
                  ? Icons.autorenew
                  : Icons.radio_button_unchecked,
              color: stage == BuildStage.failed
                  ? Colors.red
                  : i <= current
                  ? MindColors.mint
                  : MindColors.muted,
            ),
            title: Text(steps[i].label),
          ),
      ],
    );
  }
}
