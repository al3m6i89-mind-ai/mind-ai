import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/strings.dart';
import 'attachment_card.dart';
import 'message_view.dart';
import 'settings.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _scaffold = GlobalKey<ScaffoldState>();
  int _lastCount = 0;
  int _lastLen = 0;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  S get s => S(context.read<AppStore>().lang);

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? context.danger : null,
        duration: Duration(seconds: error ? 6 : 3),
      ));
  }

  Future<void> _pick({required bool images}) async {
    final store = context.read<AppStore>();
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(type: images ? FileType.image : FileType.any);
    } catch (e) {
      if (mounted) _toast(e.toString(), error: true);
      return;
    }
    if (!mounted) return;
    for (final f in files) {
      // Size is checked before reading so a huge file is never loaded into memory.
      final len = await f.length();
      if (len != null && len > maxFileBytes) {
        if (mounted) _toast(s.t('tooLarge', {'name': f.name}), error: true);
        continue;
      }
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      try {
        await store.addAttachment(f.name, bytes, s.t('newChat'));
      } on AttachRejected catch (e) {
        if (mounted) _toast(s.t(e.key, {'name': e.name}), error: true);
      }
    }
  }

  Future<void> _send() async {
    final store = context.read<AppStore>();
    if (store.streaming) {
      store.stop();
      return;
    }
    final text = _input.text;
    if (text.trim().isEmpty && store.pending.isEmpty) return;
    _input.clear();
    HapticFeedback.lightImpact();
    await store.send(text, s.t('newChat'));
  }

  void _autoScroll(Conversation? c) {
    final count = c?.messages.length ?? 0;
    final len = c?.messages.lastOrNull?.text.length ?? 0;
    if (count == _lastCount && len == _lastLen) return;
    final jump = count != _lastCount;
    _lastCount = count;
    _lastLen = len;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      final nearBottom = pos.maxScrollExtent - pos.pixels < 220;
      if (jump || nearBottom) {
        _scroll.animateTo(pos.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<String?> _askText(String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, maxLength: 200),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(s.t('save'))),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.t('delete')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> renameConv(Conversation c) async {
    final title = await _askText(s.t('rename'), c.title);
    if (title != null && title.isNotEmpty && mounted) await context.read<AppStore>().rename(c, title);
  }

  Future<void> deleteConv(Conversation c) async {
    if (await _confirm(s.t('deleteChatQ'), s.t('deleteChatText')) && mounted) {
      await context.read<AppStore>().deleteConversation(c);
    }
  }

  Future<void> deleteFile(Conversation c, Attachment a) async {
    if (await _confirm(s.t('deleteFileQ'), s.t('deleteFileText')) && mounted) {
      await context.read<AppStore>().deleteAttachment(c, a);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final s = S(store.lang);
    final conv = store.current;
    _autoScroll(conv);

    return Scaffold(
      key: _scaffold,
      drawer: _ChatsDrawer(home: this),
      appBar: AppBar(
        title: Text(conv?.title ?? s.t('newChat'), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          if (conv != null)
            IconButton(tooltip: s.t('rename'), icon: const Icon(Icons.edit_outlined), onPressed: () => renameConv(conv)),
          IconButton(
            tooltip: s.t('newChat'),
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () => store.select(null),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: conv == null || conv.messages.isEmpty
                    ? _EmptyState(key: const ValueKey('empty'), s: s, onSuggestion: (t) => _input.text = t)
                    : ListView.builder(
                        key: ValueKey(conv.id),
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                        itemCount: conv.messages.length,
                        itemBuilder: (_, i) => MessageView(
                          message: conv.messages[i],
                          s: s,
                          isLast: i == conv.messages.length - 1,
                          onRetry: store.retry,
                          onDeleteFile: (a) => deleteFile(conv, a),
                        ),
                      ),
              ),
            ),
            _Composer(home: this, s: s),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.s, required this.onSuggestion});
  final S s;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(18)),
            child: Icon(Icons.find_in_page_outlined, color: Theme.of(context).colorScheme.onPrimary, size: 34),
          ),
        ),
        const SizedBox(height: 18),
        Text(s.t('emptyTitle'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(s.t('emptyText'), textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
        const SizedBox(height: 24),
        for (final k in ['sug1', 'sug2', 'sug3'])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                alignment: AlignmentDirectional.centerStart,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: BorderSide(color: context.border),
              ),
              onPressed: () => onSuggestion(s.t(k)),
              child: Text(s.t(k), style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
            ),
          ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.home, required this.s});
  final _HomeScreenState home;
  final S s;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final scheme = Theme.of(context).colorScheme;
    final canSend = store.streaming ||
        (store.processing == 0 && (home._input.text.trim().isNotEmpty || store.pending.isNotEmpty));
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: store.pending.isEmpty && store.processing == 0
                ? const SizedBox(width: double.infinity)
                : SizedBox(
                    height: 76,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        for (final a in store.pending)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: AttachmentCard(attachment: a, s: s, onRemove: () => store.removePending(a), compact: true),
                          ),
                        if (store.processing > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(children: [
                              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: 8),
                              Text(s.t('analyzing'), style: TextStyle(color: context.muted)),
                            ]),
                          ),
                      ],
                    ),
                  ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // The input box, with the attach buttons inside it.
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: context.border),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 3))],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: s.t('attachFile'),
                        icon: Icon(Icons.attach_file, color: context.muted),
                        onPressed: () => home._pick(images: false),
                      ),
                      IconButton(
                        tooltip: s.t('attachImage'),
                        icon: Icon(Icons.image_outlined, color: context.muted),
                        onPressed: () => home._pick(images: true),
                      ),
                      Expanded(
                        child: TextField(
                          controller: home._input,
                          minLines: 1,
                          maxLines: 6,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: s.t('placeholder'),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Send button, outside the box (on the left in Arabic).
              AnimatedScale(
                scale: canSend ? 1 : 0.92,
                duration: const Duration(milliseconds: 150),
                child: Material(
                  color: canSend ? scheme.primary : scheme.primary.withValues(alpha: 0.35),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: canSend ? home._send : null,
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                        child: Icon(
                          store.streaming ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                          key: ValueKey(store.streaming),
                          color: scheme.onPrimary,
                          semanticLabel: store.streaming ? s.t('stop') : s.t('send'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChatsDrawer extends StatefulWidget {
  const _ChatsDrawer({required this.home});
  final _HomeScreenState home;

  @override
  State<_ChatsDrawer> createState() => _ChatsDrawerState();
}

class _ChatsDrawerState extends State<_ChatsDrawer> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final s = S(store.lang);
    final list = store.search(_q);
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(9)),
                  child: Icon(Icons.find_in_page_outlined, color: scheme.onPrimary, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(s.t('appName'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              ]),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add),
                label: Text(s.t('newChat')),
                onPressed: () {
                  store.select(null);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: s.t('search'),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: context.surface2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(_q.isEmpty ? s.t('noChats') : s.t('noResults'), style: TextStyle(color: context.muted)),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final c = list[i];
                          final active = c.id == store.currentId;
                          return ListTile(
                            dense: true,
                            selected: active,
                            selectedTileColor: context.surface2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                            onTap: () {
                              store.select(c.id);
                              Navigator.pop(context);
                            },
                            trailing: PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, color: context.muted, size: 20),
                              onSelected: (v) {
                                if (v == 'rename') widget.home.renameConv(c);
                                if (v == 'delete') widget.home.deleteConv(c);
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'rename', child: Text(s.t('rename'))),
                                PopupMenuItem(value: 'delete', child: Text(s.t('delete'))),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(s.t('settings')),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
