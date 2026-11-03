import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../services/social/social_service.dart';
import '../../services/social/text_utils.dart';
import 'widgets.dart';

/// Comments for a reel or a photo: top comments with one level of answers,
/// like a comment, answer it, delete your own (or any on your post).
Future<void> showComments(BuildContext context, SocialPost post) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => FractionallySizedBox(heightFactor: 0.78, child: CommentsSheet(post: post)),
);

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.post});
  final SocialPost post;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  Comment? _answering;
  final _expanded = <String>{};

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final social = context.read<SocialService>();
    try {
      final c = await social.addComment(widget.post.id, _text.text, parentId: _answering?.id);
      _text.clear();
      if (c.parentId != null) _expanded.add(c.parentId!);
      setState(() => _answering = null);
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  void _answer(Comment c, SocialUser? author) {
    setState(() => _answering = c);
    if (author != null) {
      _text.text = '@${author.handle} ';
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    }
    _focus.requestFocus();
  }

  Future<void> _more(Comment c) async {
    final social = context.read<SocialService>();
    final canDelete = c.authorId == social.meId || widget.post.authorId == social.meId;
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('نسخ النص'),
              onTap: () {
                Navigator.pop(ctx);
                copyText(context, c.text);
              },
            ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('حذف التعليق', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  social.deleteComment(c);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _tile(SocialService social, Comment c, {bool child = false}) {
    final u = social.user(c.authorId);
    final liked = c.likes.contains(social.meId);
    final isAuthor = c.authorId == widget.post.authorId;
    return InkWell(
      onLongPress: () => _more(c),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(child ? 56 : 16, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SocialAvatar(u, size: child ? 28 : 36, onTap: () => openProfile(context, c.authorId)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          u?.handle ?? 'حساب محذوف',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                      if (u?.verified ?? false) const VerifiedBadge(size: 13),
                      if (isAuthor)
                        const Text(' · صاحب المنشور', style: TextStyle(color: MindColors.pink, fontSize: 12, fontWeight: FontWeight.w700)),
                      Text(' · ${SocialText.ago(c.createdAt)}', style: const TextStyle(color: MindColors.muted, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  RichPostText(c.text),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => _answer(c, u),
                    child: const Text('رد', style: TextStyle(color: MindColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(liked ? Icons.favorite : Icons.favorite_border, size: 18, color: liked ? Colors.red : MindColors.muted),
                  onPressed: () => social.toggleCommentLike(c),
                ),
                if (c.likes.isNotEmpty)
                  Text(SocialText.count(c.likes.length), style: const TextStyle(fontSize: 11, color: MindColors.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialService>();
    final list = social.comments(widget.post.id);
    final total = social.commentCount(widget.post);
    return Column(
      children: [
        Text('التعليقات ${total > 0 ? '($total)' : ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const Divider(),
        Expanded(
          child: widget.post.commentsOff
              ? const EmptyState('🔒', 'أوقف صاحب المنشور التعليقات')
              : list.isEmpty
              ? const EmptyState('💬', 'لا توجد تعليقات بعد\nكن أول من يعلّق!')
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final answers = social.answers(c.id);
                    final open = _expanded.contains(c.id);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _tile(social, c),
                        if (answers.isNotEmpty && !open)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 62, bottom: 6),
                            child: GestureDetector(
                              onTap: () => setState(() => _expanded.add(c.id)),
                              child: Text(
                                '—— عرض ${answers.length} ${answers.length == 1 ? 'رد' : 'ردود'}',
                                style: const TextStyle(color: MindColors.muted, fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ),
                          ),
                        if (open) ...answers.map((a) => _tile(social, a, child: true)),
                      ],
                    );
                  },
                ),
        ),
        if (!widget.post.commentsOff && social.hasAccount) ...[
          if (_answering != null)
            Container(
              color: MindColors.violet.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'الرد على @${social.user(_answering!.authorId)?.handle ?? ''}',
                      style: const TextStyle(color: MindColors.muted, fontSize: 13),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _answering = null;
                      _text.clear();
                    }),
                    child: const Icon(Icons.close, size: 18, color: MindColors.muted),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 6, 12, 8 + MediaQuery.of(context).viewInsets.bottom),
              child: Row(
                children: [
                  SocialAvatar(social.me, size: 34),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: 'أضف تعليقاً…', counterText: '', isDense: true),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: _text,
                    builder: (_, _) => IconButton(
                      icon: const Icon(Icons.send_rounded),
                      color: MindColors.violet,
                      onPressed: _text.text.trim().isEmpty ? null : _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
