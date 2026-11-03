import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/social/social_service.dart';
import 'widgets.dart';

/// Asks why, then sends one report about a post, comment, story or account.
Future<void> showReportSheet(
  BuildContext context, {
  required ReportTarget target,
  required String targetId,
  required String authorId,
}) {
  final social = context.read<SocialService>();
  if (social.reported(target, targetId)) {
    toast(context, 'سبق أن أبلغت عن هذا، وهو قيد المراجعة');
    return Future.value();
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ReportSheet(target: target, targetId: targetId, authorId: authorId),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.target, required this.targetId, required this.authorId});
  final ReportTarget target;
  final String targetId;
  final String authorId;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;
  final _note = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await context.read<SocialService>().report(
        widget.target,
        widget.targetId,
        authorId: widget.authorId,
        reason: reason,
        note: _note.text,
      );
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final social = context.read<SocialService>();
    final author = social.user(widget.authorId);
    if (_sent) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_user_rounded, size: 56, color: MindColors.mint),
              const SizedBox(height: 12),
              const Text('شكراً، وصلنا بلاغك', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 8),
              const Text(
                'سيراجعه فريق الإشراف. لن يعرف صاحب المحتوى من أبلغ عنه.',
                textAlign: TextAlign.center,
                style: TextStyle(color: MindColors.muted, height: 1.5),
              ),
              const SizedBox(height: 16),
              if (author != null && widget.target != ReportTarget.user && !social.isBlocked(author.id))
                OutlinedButton.icon(
                  onPressed: () {
                    social.toggleBlock(author.id);
                    Navigator.pop(context);
                    toast(context, 'حظرت @${author.handle}');
                  },
                  icon: const Icon(Icons.block, color: Colors.redAccent),
                  label: Text('حظر @${author.handle} أيضاً'),
                ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('تم')),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الإبلاغ عن ${widget.target.label}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 4),
            const Text('لماذا تبلغ عنه؟ بلاغك سرّي.', style: TextStyle(color: MindColors.muted)),
            const SizedBox(height: 8),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final r in ReportReason.values)
                    RadioListTile<ReportReason>(
                      value: r,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.label),
                    ),
                ],
              ),
            ),
            TextField(
              controller: _note,
              maxLength: 500,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(hintText: 'تفاصيل تساعد المشرف (اختياري)'),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: _reason == null || _busy ? null : _send,
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('إرسال البلاغ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
