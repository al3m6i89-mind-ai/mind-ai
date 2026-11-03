import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/social/social_service.dart';
import '../../services/social/text_utils.dart';
import 'posts_view.dart';
import 'widgets.dart';

/// Moderators' dashboard: reports grouped by item, most-reported first, with
/// the item itself and one-tap actions.
class ModerationScreen extends StatelessWidget {
  const ModerationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    if (!social.isAdmin) {
      return Scaffold(appBar: AppBar(), body: const EmptyState('🔒', 'هذه الصفحة للمشرفين فقط'));
    }
    final open = social.reportCases();
    final done = social.reportCases(open: false);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة الإشراف'),
          bottom: TabBar(tabs: [Tab(text: 'بانتظار المراجعة (${open.length})'), Tab(text: 'تمت (${done.length})')]),
        ),
        body: TabBarView(
          children: [
            open.isEmpty
                ? const EmptyState('✅', 'لا توجد بلاغات مفتوحة')
                : ListView.builder(itemCount: open.length, itemBuilder: (_, i) => _CaseCard(c: open[i])),
            done.isEmpty
                ? const EmptyState('🗂️', 'لا شيء بعد')
                : ListView.builder(itemCount: done.length, itemBuilder: (_, i) => _CaseCard(c: done[i])),
          ],
        ),
      ),
    );
  }
}

class _CaseCard extends StatelessWidget {
  const _CaseCard({required this.c});
  final ReportCase c;

  Future<void> _run(BuildContext context, Future<void> Function() action, String done) async {
    try {
      await action();
      if (context.mounted) toast(context, done);
    } catch (e) {
      if (context.mounted) toast(context, e);
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final author = social.user(c.authorId);
    final status = c.reports.first.status;
    final post = c.target == ReportTarget.post ? social.post(c.targetId) : null;
    final comment = c.target == ReportTarget.comment ? social.comment(c.targetId) : null;
    final story = c.target == ReportTarget.story ? social.story(c.targetId) : null;
    final gone = switch (c.target) {
      ReportTarget.post => post == null,
      ReportTarget.comment => comment == null,
      ReportTarget.story => story == null,
      ReportTarget.user => author == null,
    };
    final hidden = post?.hidden ?? comment?.hidden ?? false;

    Widget preview;
    if (gone) {
      preview = const Text('المحتوى محذوف أو خارج النافذة الحالية', style: TextStyle(color: MindColors.muted));
    } else if (post != null) {
      preview = QuotedPost(id: post.id);
    } else if (comment != null) {
      preview = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: MindColors.violet.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
        child: Text('💬 ${comment.text}'),
      );
    } else if (story != null) {
      preview = ClipRRect(borderRadius: BorderRadius.circular(12), child: MediaImage(story.media.src, height: 160, width: double.infinity));
    } else {
      preview = ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SocialAvatar(author, size: 40),
        title: NameLine(author, showHandle: false),
        subtitle: Text(author?.bio ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: () => openProfile(context, c.targetId),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '🚩 ${c.reports.length} ${c.reports.length == 1 ? 'بلاغ' : 'بلاغات'} · ${c.target.label}',
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
                if (hidden) ...[
                  const SizedBox(width: 6),
                  const Chip(label: Text('مخفي', style: TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
                ],
                const Spacer(),
                Text(SocialText.ago(c.latest), style: const TextStyle(color: MindColors.muted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            if (author != null && c.target != ReportTarget.user)
              InkWell(
                onTap: () => openProfile(context, author.id),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SocialAvatar(author, size: 24),
                      const SizedBox(width: 6),
                      Expanded(child: NameLine(author)),
                      if (author.suspended) const Text('موقوف', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            preview,
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final (reason, n) in c.reasons)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${reason.label}${n > 1 ? ' ×$n' : ''}', style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            for (final r in c.reports.where((r) => r.note.isNotEmpty).take(3))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('«${r.note}»', style: const TextStyle(color: MindColors.muted, fontSize: 13)),
              ),
            const Divider(height: 20),
            if (status != ReportStatus.open)
              Text(
                status == ReportStatus.removed ? '🗑️ أُزيل' : '↩️ رُفض البلاغ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (c.target != ReportTarget.user && !gone)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, visualDensity: VisualDensity.compact),
                      onPressed: () async {
                        if (await _confirm(context, 'حذف ${c.target.label}؟', 'يُحذف للجميع ولا يمكن التراجع.') && context.mounted) {
                          await _run(context, () => social.removeReported(c), 'حُذف');
                        }
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('حذف'),
                    ),
                  if ((c.target == ReportTarget.post || c.target == ReportTarget.comment) && !gone)
                    OutlinedButton(
                      onPressed: () => _run(context, () => social.setHidden(c, !hidden), hidden ? 'أصبح ظاهراً' : 'أُخفي'),
                      child: Text(hidden ? 'إظهار' : 'إخفاء'),
                    ),
                  OutlinedButton(
                    onPressed: () => _run(context, () => social.dismissReports(c), 'رُفض البلاغ'),
                    child: const Text('رفض البلاغ'),
                  ),
                  if (author != null && author.id != social.meId)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                      onPressed: () async {
                        final stop = !author.suspended;
                        if (stop &&
                            !(await _confirm(
                              context,
                              'إيقاف @${author.handle}؟',
                              'يختفي كل محتواه عن الجميع ولا يستطيع النشر أو التفاعل حتى ترفع الإيقاف.',
                            ))) {
                          return;
                        }
                        if (!context.mounted) return;
                        await _run(context, () => social.setSuspended(author.id, stop), stop ? 'أُوقف الحساب' : 'رُفع الإيقاف');
                        if (stop && c.target == ReportTarget.user && context.mounted) {
                          await _run(context, () => social.removeReported(c), 'أُغلق البلاغ');
                        }
                      },
                      child: Text(author.suspended ? 'رفع الإيقاف' : 'إيقاف الحساب'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
