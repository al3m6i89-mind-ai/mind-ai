import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/social/social_service.dart';
import '../../services/social/text_utils.dart';
import 'messages_screen.dart';
import 'report_sheet.dart';
import 'share_sheet.dart';
import 'widgets.dart';

/// The "…" menu on any reel, photo or post.
Future<void> showPostMenu(BuildContext context, SocialPost post) {
  final social = context.read<SocialService>();
  final mine = post.authorId == social.meId;
  final author = social.user(post.authorId);
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      void close(VoidCallback f) {
        Navigator.pop(ctx);
        f();
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (author != null)
              ListTile(
                leading: SocialAvatar(author, size: 36),
                title: Text(author.name),
                subtitle: Text(author.id, textDirection: TextDirection.ltr, textAlign: TextAlign.end),
                trailing: const Icon(Icons.copy_rounded, size: 18),
                onTap: () => close(() => copyId(context, author.id)),
              ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('نسخ الرابط'),
              onTap: () => close(() => copyText(context, postLink(post), done: 'تم نسخ الرابط')),
            ),
            if (mine) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(post.kind == PostKind.post ? 'تعديل المنشور' : 'تعديل الوصف'),
                onTap: () => close(() => _edit(context, post)),
              ),
              if (post.kind != PostKind.post)
                ListTile(
                  leading: Icon(post.commentsOff ? Icons.comment_outlined : Icons.comments_disabled_outlined),
                  title: Text(post.commentsOff ? 'تشغيل التعليقات' : 'إيقاف التعليقات'),
                  onTap: () => close(() => social.setCommentsOff(post, !post.commentsOff)),
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
                onTap: () => close(() => _confirmDelete(context, post)),
              ),
            ] else if (author != null) ...[
              ListTile(
                leading: Icon(social.isFollowing(author.id) ? Icons.person_remove_outlined : Icons.person_add_alt),
                title: Text(social.isFollowing(author.id) ? 'إلغاء متابعة @${author.handle}' : 'متابعة @${author.handle}'),
                onTap: () => close(() => social.toggleFollow(author.id)),
              ),
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: const Text('مراسلة'),
                onTap: () => close(() => openChat(context, author.id)),
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.redAccent),
                title: Text('إبلاغ عن ${post.kind.single}', style: const TextStyle(color: Colors.redAccent)),
                onTap: () => close(
                  () => showReportSheet(context, target: ReportTarget.post, targetId: post.id, authorId: post.authorId),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.redAccent),
                title: Text('حظر @${author.handle}', style: const TextStyle(color: Colors.redAccent)),
                onTap: () => close(() => social.toggleBlock(author.id)),
              ),
            ],
          ],
        ),
      );
    },
  );
}

Future<void> _confirmDelete(BuildContext context, SocialPost post) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('حذف ${post.kind.single}؟'),
      content: const Text('لا يمكن التراجع عن الحذف.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.redAccent))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await context.read<SocialService>().deletePost(post);
  } catch (e) {
    if (context.mounted) toast(context, e);
  }
}

Future<void> _edit(BuildContext context, SocialPost post) async {
  final ctrl = TextEditingController(text: post.text);
  final limit = post.kind == PostKind.post ? SocialText.postLimit : SocialText.captionLimit;
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تعديل'),
      content: TextField(controller: ctrl, maxLines: 6, minLines: 2, maxLength: limit, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('حفظ')),
      ],
    ),
  );
  if (text == null || !context.mounted) return;
  try {
    await context.read<SocialService>().editText(post, text);
  } catch (e) {
    if (context.mounted) toast(context, e);
  }
}
