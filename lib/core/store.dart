import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'adblock.dart';
import 'ai.dart';
import 'auth.dart';
import 'extract.dart';
import 'billing.dart';
import 'updates.dart';
import 'models.dart';
import 'plan.dart';

const _uuid = Uuid();

/// Thrown when a picked file is refused; [key] is a string key, [name] the file.
class AttachRejected implements Exception {
  AttachRejected(this.key, this.name);
  final String key;
  final String name;
}

/// All app state. Conversations live as one JSON file each in the app's private
/// folder; attached files are copied next to them.
class AppStore extends ChangeNotifier {
  AppStore(this._prefs, this._root, {Auth? auth, this.adBlockCheck = detectAdBlocker, Updater? updates})
      : auth = auth ?? Auth.disabled(),
        updates = updates ?? Updater();

  /// New releases: checked here and in the background, installed from inside the app.
  final Updater updates;

  /// Google or phone sign-in (disabled until Firebase is set up for the build).
  final Auth auth;

  /// Whether the phone blocks ad servers; replaced in tests.
  final Future<bool> Function() adBlockCheck;

  final SharedPreferences _prefs;
  final Directory _root;

  final List<Conversation> conversations = [];
  String? currentId;

  /// Files picked for the next message, not sent yet.
  final List<Attachment> pending = [];
  int processing = 0;

  StreamSubscription<AiEvent>? _stream;
  Completer<void>? _done;
  bool get streaming => _stream != null;

  static Future<AppStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    final root = Directory('${(await getApplicationDocumentsDirectory()).path}/file_chat');
    final store = AppStore(prefs, root, auth: await Auth.start());
    await store._load();
    unawaited(store.billing.start());
    return store;
  }

  // ---------- plan ----------
  late final billing = Billing(_setPremium);

  /// Set only from what Google Play reports (see [Billing]).
  bool get premium => _prefs.getBool('premium') ?? false;
  void _setPremium(bool v) {
    if (v == premium) return;
    _prefs.setBool('premium', v);
    notifyListeners();
  }

  int get maxFileBytes => premium ? Plan.premiumMaxFileBytes : Plan.freeMaxFileBytes;

  String get _today {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  int get questionsToday => _prefs.getString('qDay') == _today ? (_prefs.getInt('qCount') ?? 0) : 0;
  int get questionsLeft => premium ? -1 : (Plan.freeDailyQuestions - questionsToday).clamp(0, Plan.freeDailyQuestions);
  bool get canAsk => premium || questionsLeft > 0;

  @visibleForTesting
  void debugCountQuestion() => _countQuestion();

  void _countQuestion() {
    _prefs.setString('qDay', _today);
    _prefs.setInt('qCount', questionsToday + 1);
  }

  // ---------- settings ----------
  String get lang => _prefs.getString('lang') ?? 'ar';
  Future<void> setLang(String v) async {
    await _prefs.setString('lang', v);
    notifyListeners();
  }

  ThemeMode get themeMode => ThemeMode.values.asNameMap()[_prefs.getString('theme')] ?? ThemeMode.system;
  Future<void> setThemeMode(ThemeMode m) async {
    await _prefs.setString('theme', m.name);
    notifyListeners();
  }

  // ---------- persistence ----------
  Directory get _chatsDir => Directory('${_root.path}/chats');
  Directory _filesDir(String convId) => Directory('${_root.path}/files/$convId');

  Future<void> _load() async {
    await _chatsDir.create(recursive: true);
    for (final f in _chatsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      try {
        final c = Conversation.decode(await f.readAsString());
        // A reply cut off by closing the app is kept as stopped, not left spinning.
        for (final m in c.messages) {
          if (m.status == MsgStatus.streaming) m.status = MsgStatus.stopped;
        }
        conversations.add(c);
      } catch (_) {
        // A damaged file is skipped rather than blocking the whole app.
      }
    }
    _sort();
  }

  Future<void> _save(Conversation c) async {
    await _chatsDir.create(recursive: true);
    final f = File('${_chatsDir.path}/${c.id}.json');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(c.encode(), flush: true);
    await tmp.rename(f.path);
  }

  void _sort() => conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Conversation? get current {
    for (final c in conversations) {
      if (c.id == currentId) return c;
    }
    return null;
  }

  List<Conversation> search(String q) =>
      q.trim().isEmpty ? conversations : conversations.where((c) => c.matches(q.trim())).toList();

  // ---------- conversations ----------
  void select(String? id) {
    stop();
    _discardPending();
    currentId = id;
    notifyListeners();
  }

  Future<Conversation> _ensureConversation(String defaultTitle) async {
    final c = current;
    if (c != null) return c;
    final conv = Conversation(id: _uuid.v4(), title: defaultTitle);
    conversations.insert(0, conv);
    currentId = conv.id;
    await _save(conv);
    return conv;
  }

  Future<void> rename(Conversation c, String title) async {
    c.title = title.trim();
    await _save(c);
    notifyListeners();
  }

  /// Removes the chats from the list at once, then deletes their files.
  Future<void> deleteConversations(Iterable<Conversation> list) async {
    final chosen = list.toList();
    if (chosen.any((c) => c.id == currentId)) select(null);
    conversations.removeWhere(chosen.contains);
    notifyListeners();
    for (final c in chosen) {
      final f = File('${_chatsDir.path}/${c.id}.json');
      if (await f.exists()) await f.delete();
      final dir = _filesDir(c.id);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }

  Future<void> deleteConversation(Conversation c) async {
    if (c.id == currentId) select(null);
    conversations.remove(c);
    final f = File('${_chatsDir.path}/${c.id}.json');
    if (await f.exists()) await f.delete();
    final dir = _filesDir(c.id);
    if (await dir.exists()) await dir.delete(recursive: true);
    notifyListeners();
  }

  Future<void> deleteAttachment(Conversation c, Attachment a) async {
    for (final m in c.messages) {
      m.attachments.removeWhere((x) => x.id == a.id);
    }
    final f = File(a.path);
    if (await f.exists()) await f.delete();
    await _save(c);
    notifyListeners();
  }

  // ---------- attachments ----------
  /// Validates, copies and reads one picked file. Throws [AttachRejected].
  Future<void> addAttachment(String name, Uint8List bytes, String defaultTitle) async {
    final ext = extensionOf(name);
    if (legacyOffice.contains(ext)) throw AttachRejected('legacy', name);
    if (!supportedExtensions.contains(ext)) throw AttachRejected('unsupported', name);
    if (bytes.length > maxFileBytes) throw AttachRejected('tooLarge', name);
    final bad = validateBytes(ext, bytes);
    if (bad != null) throw AttachRejected(bad, name);

    processing++;
    notifyListeners();
    try {
      final conv = await _ensureConversation(defaultTitle);
      final id = _uuid.v4();
      final dir = _filesDir(conv.id);
      await dir.create(recursive: true);
      final file = File('${dir.path}/$id.$ext');
      await file.writeAsBytes(bytes, flush: true);
      // Office text extraction can take a moment on big files; keep the UI responsive.
      final result = await Isolate.run(() => extractText(ext, bytes));
      pending.add(Attachment(
        id: id,
        name: name,
        ext: ext,
        size: bytes.length,
        path: file.path,
        extractedText: result.text,
        note: result.note,
      ));
    } finally {
      processing--;
      notifyListeners();
    }
  }

  Future<void> removePending(Attachment a) async {
    pending.remove(a);
    final f = File(a.path);
    if (await f.exists()) await f.delete();
    notifyListeners();
  }

  void _discardPending() {
    for (final a in pending) {
      final f = File(a.path);
      if (f.existsSync()) f.deleteSync();
    }
    pending.clear();
  }

  // ---------- messaging ----------
  /// Returns false when the free plan's daily questions are used up.
  Future<bool> send(String text, String defaultTitle) async {
    final t = text.trim();
    if (streaming || processing > 0 || (t.isEmpty && pending.isEmpty)) return true;
    if (!canAsk) return false;
    _countQuestion();
    final conv = await _ensureConversation(defaultTitle);
    final userMsg = Message(id: _uuid.v4(), role: Role.user, text: t, attachments: List.of(pending));
    pending.clear();
    conv.messages.add(userMsg);
    if (conv.title == defaultTitle) {
      final source = t.isNotEmpty ? t : userMsg.attachments.first.name;
      final oneLine = source.replaceAll(RegExp(r'\s+'), ' ');
      conv.title = oneLine.length > 50 ? '${oneLine.substring(0, 50)}…' : oneLine;
    }
    await _answer(conv);
    return true;
  }

  /// A retry costs a question too; returns false when none are left.
  Future<bool> retry() async {
    final conv = current;
    if (conv == null || streaming || conv.messages.isEmpty) return true;
    // Retrying a failed answer is free; asking again for a good one counts.
    final failed = conv.messages.last.role == Role.assistant && conv.messages.last.status == MsgStatus.error;
    if (!failed) {
      if (!canAsk) return false;
      _countQuestion();
    }
    if (conv.messages.last.role == Role.assistant) conv.messages.removeLast();
    await _answer(conv);
    return true;
  }

  Future<void> _answer(Conversation conv) async {
    final reply = Message(id: _uuid.v4(), role: Role.assistant, text: '', status: MsgStatus.streaming);
    conv.updatedAt = DateTime.now();
    _sort();
    final client = AiClient(
      preferPro: premium,
      geminiModel: _prefs.getString('geminiModel') ?? AiClient.defaultGeminiModel,
      onModelChanged: (m) => _prefs.setString('geminiModel', m),
    );
    final stream = client.reply(conv);
    conv.messages.add(reply);
    notifyListeners();

    final done = _done = Completer<void>();
    _stream = stream.listen(
      (event) {
        switch (event) {
          case AiText(:final text):
            reply
              ..text += text
              ..note = null;
          case AiReset():
            reply.text = '';
          case AiVia():
            break;
          case AiTrace(:final line):
            // Kept with the message for diagnosis, never shown.
            reply.trace.add(line);
          case AiStatus(:final code):
            reply.note = code;
        }
        notifyListeners();
      },
      onError: (Object e) {
        reply.note = null;
        reply
          ..status = MsgStatus.error
          ..error = e is AiException ? e.message : e.toString();
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        reply.note = null;
        if (reply.status == MsgStatus.streaming) reply.status = MsgStatus.complete;
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    await done.future;
    _stream = null;
    _done = null;
    conv.updatedAt = DateTime.now();
    await _save(conv);
    notifyListeners();
  }

  void stop() {
    final s = _stream;
    if (s == null) return;
    s.cancel();
    _stream = null;
    final conv = current;
    final last = conv?.messages.lastOrNull;
    if (conv != null && last != null && last.status == MsgStatus.streaming) {
      last.status = MsgStatus.stopped;
    }
    // Lets _answer finish: it saves the partial reply.
    final d = _done;
    if (d != null && !d.isCompleted) d.complete();
    notifyListeners();
  }
}
