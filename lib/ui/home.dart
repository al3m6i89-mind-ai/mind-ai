import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart' hide Provider;

import '../core/ai.dart';
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

  /// Paperclip: the phone's file manager (any document).
  Future<void> pickFiles() async {
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(type: FileType.any);
    } catch (e) {
      if (mounted) _toast(e.toString(), error: true);
      return;
    }
    for (final f in files) {
      if (!mounted) return;
      await _add(f.name, await f.length(), f.readAsBytes);
    }
  }

  /// Image button: the phone's gallery (Android photo picker).
  Future<void> pickImages() async {
    final List<XFile> images;
    try {
      // Re-encoding keeps photos small enough to send and turns odd formats into JPEG.
      images = await ImagePicker().pickMultiImage(maxWidth: 2560, maxHeight: 2560, imageQuality: 88, requestFullMetadata: false);
    } catch (e) {
      if (mounted) _toast(e.toString(), error: true);
      return;
    }
    for (final x in images) {
      if (!mounted) return;
      await _add(x.name, await x.length(), x.readAsBytes);
    }
  }

  Future<void> _add(String name, int? length, Future<Uint8List> Function() read) async {
    // Size is checked before reading so a huge file is never loaded into memory.
    if (length != null && length > maxFileBytes) {
      _toast(s.t('tooLarge', {'name': name}), error: true);
      return;
    }
    final bytes = await read();
    if (!mounted) return;
    try {
      await context.read<AppStore>().addAttachment(name, bytes, s.t('newChat'));
    } on AttachRejected catch (e) {
      if (mounted) _toast(s.t(e.key, {'name': e.name}), error: true);
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
    final gemini = store.provider == Provider.gemini;

    return Scaffold(
      key: _scaffold,
      drawer: _ChatsDrawer(home: this),
      appBar: AppBar(
        leading: IconButton(
          tooltip: s.t('chats'),
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffold.currentState?.openDrawer(),
        ),
        title: GestureDetector(
          onTap: conv == null ? null : () => renameConv(conv),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(conv?.title ?? s.t('appName'), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 1),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: gemini && store.geminiKey.isEmpty ? context.warn : Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 5),
                Text(gemini ? 'Gemini' : s.t('freeMode'),
                    style: TextStyle(fontSize: 11.5, color: context.muted, fontWeight: FontWeight.w500)),
              ]),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: s.t('newChat'),
            icon: const Icon(Icons.edit_square),
            onPressed: conv == null ? null : () => store.select(null),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                child: conv == null || conv.messages.isEmpty
                    ? _EmptyState(key: const ValueKey('empty'), s: s, home: this)
                    : ListView.builder(
                        key: ValueKey(conv.id),
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
  const _EmptyState({super.key, required this.s, required this.home});
  final S s;
  final _HomeScreenState home;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final store = context.watch<AppStore>();
    final needsKey = store.provider == Provider.gemini && store.geminiKey.isEmpty;
    final actions = [
      (Icons.folder_open_rounded, s.t('pickFile'), s.t('pickFileHint'), home.pickFiles),
      (Icons.photo_library_rounded, s.t('pickImage'), s.t('pickImageHint'), home.pickImages),
    ];
    final suggestions = [
      (Icons.summarize_outlined, 'sug1'),
      (Icons.insights_outlined, 'sug2'),
      (Icons.receipt_long_outlined, 'sug3'),
      (Icons.translate_rounded, 'sug4'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      children: [
        _FadeIn(
          child: Column(children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.28), blurRadius: 28, offset: const Offset(0, 10))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset('assets/logo.png', width: 78, height: 78),
              ),
            ),
            const SizedBox(height: 20),
            Text(s.t('emptyTitle'), textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.3)),
            const SizedBox(height: 8),
            Text(s.t('emptyText'), textAlign: TextAlign.center, style: TextStyle(color: context.muted, height: 1.55)),
          ]),
        ),
        if (needsKey) ...[
          const SizedBox(height: 18),
          _FadeIn(
            delay: 60,
            child: Material(
              color: context.warn.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Icon(Icons.key_rounded, color: context.warn),
                    const SizedBox(width: 12),
                    Expanded(child: Text(s.t('err_missingKey'), style: const TextStyle(height: 1.45))),
                    Icon(Icons.chevron_right_rounded, color: context.muted),
                  ]),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _FadeIn(
          delay: 90,
          child: Row(children: [
            for (final (i, (icon, title, hint, onTap)) in actions.indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: _ActionCard(icon: icon, title: title, hint: hint, onTap: onTap)),
            ],
          ]),
        ),
        const SizedBox(height: 24),
        _FadeIn(
          delay: 140,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 10),
            child: Text(s.t('tryAsking'), style: TextStyle(color: context.muted, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ),
        for (final (i, (icon, key)) in suggestions.indexed)
          _FadeIn(
            delay: 170 + i * 40,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    home._input.text = s.t(key);
                    home._input.selection = TextSelection.collapsed(offset: home._input.text.length);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.border),
                    ),
                    child: Row(children: [
                      Icon(icon, size: 20, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(child: Text(s.t(key), style: const TextStyle(fontWeight: FontWeight.w500))),
                      Icon(Icons.north_west_rounded, size: 16, color: context.muted),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 14),
        _FadeIn(
          delay: 330,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in const ['PDF', 'Word', 'Excel', 'PowerPoint', 'TXT', 'CSV', 'Markdown', 'JPG', 'PNG'])
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: context.surface2, borderRadius: BorderRadius.circular(20)),
                  child: Text(f, style: TextStyle(fontSize: 11.5, color: context.muted, fontWeight: FontWeight.w500)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.hint, required this.onTap});
  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: context.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.primary, size: 22),
              ),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(hint, maxLines: 2, style: TextStyle(color: context.muted, fontSize: 12, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades and lifts its child in once, after [delay] milliseconds.
class _FadeIn extends StatefulWidget {
  const _FadeIn({required this.child, this.delay = 0});
  final Widget child;
  final int delay;

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (_, child) => Opacity(
          opacity: _a.value,
          child: Transform.translate(offset: Offset(0, (1 - _a.value) * 14), child: child),
        ),
        child: widget.child,
      );
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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: store.pending.isEmpty && store.processing == 0
                ? const SizedBox(width: double.infinity)
                : SizedBox(
                    height: 66,
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
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: context.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: home._input,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: s.t('placeholder'),
                    hintStyle: TextStyle(color: context.muted),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  ),
                ),
                Row(
                  children: [
                    _ToolButton(icon: Icons.attach_file_rounded, label: s.t('attachFile'), onTap: home.pickFiles),
                    const SizedBox(width: 6),
                    _ToolButton(icon: Icons.photo_outlined, label: s.t('attachImage'), onTap: home.pickImages),
                    const Spacer(),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: canSend ? scheme.primary : context.surface2,
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: canSend ? home._send : null,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                            child: Icon(
                              store.streaming ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                              key: ValueKey(store.streaming),
                              size: 22,
                              color: canSend ? scheme.onPrimary : context.muted,
                              semanticLabel: store.streaming ? s.t('stop') : s.t('send'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: context.surface2,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: context.muted),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12.5, color: context.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
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

  String _group(DateTime d, S s) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return s.t('today');
    if (diff == 1) return s.t('yesterday');
    if (diff < 7) return s.t('thisWeek');
    return s.t('earlier');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final s = S(store.lang);
    final list = store.search(_q);
    final scheme = Theme.of(context).colorScheme;

    final rows = <Widget>[];
    String? lastGroup;
    for (final c in list) {
      final g = _group(c.updatedAt, s);
      if (g != lastGroup) {
        lastGroup = g;
        rows.add(Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 14, 12, 6),
          child: Text(g, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.muted)),
        ));
      }
      final active = c.id == store.currentId;
      final files = c.attachments.length;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: ListTile(
          dense: true,
          selected: active,
          selectedTileColor: scheme.primary.withValues(alpha: 0.10),
          selectedColor: scheme.onSurface,
          contentPadding: const EdgeInsetsDirectional.only(start: 12, end: 0),
          title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: active ? FontWeight.w600 : FontWeight.w500, fontSize: 14)),
          subtitle: files == 0
              ? null
              : Text(s.filesCount(files), style: TextStyle(fontSize: 11.5, color: context.muted)),
          onTap: () {
            store.select(c.id);
            Navigator.pop(context);
          },
          trailing: PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz_rounded, color: context.muted, size: 20),
            onSelected: (v) {
              if (v == 'rename') widget.home.renameConv(c);
              if (v == 'delete') widget.home.deleteConv(c);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'rename',
                child: Row(children: [const Icon(Icons.edit_outlined, size: 18), const SizedBox(width: 10), Text(s.t('rename'))]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline_rounded, size: 18, color: context.danger),
                  const SizedBox(width: 10),
                  Text(s.t('delete'), style: TextStyle(color: context.danger)),
                ]),
              ),
            ],
          ),
        ),
      ));
    }

    return Drawer(
      width: 310,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset('assets/logo.png', width: 36, height: 36),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(s.t('appName'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5))),
              ]),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded),
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
                  prefixIcon: Icon(Icons.search_rounded, color: context.muted),
                  isDense: true,
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_q.isEmpty ? Icons.forum_outlined : Icons.search_off_rounded, size: 40, color: context.border),
                          const SizedBox(height: 10),
                          Text(_q.isEmpty ? s.t('noChats') : s.t('noResults'), style: TextStyle(color: context.muted)),
                        ]),
                      )
                    : ListView(padding: const EdgeInsets.only(top: 4), children: rows),
              ),
              const Divider(),
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: Text(s.t('settings'), style: const TextStyle(fontWeight: FontWeight.w500)),
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
