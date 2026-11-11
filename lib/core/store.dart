import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
void _extractWorker((SendPort, String, String) job) {
  final (port, path, ext) = job;
  var last = -1;
  final result = extractText(ext, File(path).readAsBytesSync(), onProgress: (done, total) {
    final pct = total == 0 ? 100 : done * 100 ~/ total;
    if (pct != last) {
      last = pct;
      port.send([done, total]);
    }
  });
  Isolate.exit(port, result);
}

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
    store.auth.languageCode = store.lang;
    await store._load();
    unawaited(store.billing.start());
    return store;
  }

  // ---------- plan ----------
  late final billing = Billing(_setPremium);

  /// Set from what Google Play reports (see [Billing]) and what the proxy
  /// confirmed with Google; the proxy alone decides the paid limits.
  bool get premium => _prefs.getBool('premium') ?? false;
  void _markPremium(bool v) {
    if (v == premium) return;
    _prefs.setBool('premium', v);
    notifyListeners();
  }

  Future<void> _setPremium(bool active, String? token) async {
    // No Play purchase, but the server gives this account the paid plan (the owner's).
    if (!active && _prefs.getBool('premiumFromServer') == true) return;
    if (!active || token == null || token.isEmpty) return _markPremium(active);
    final verified = await verifyPurchase(token);
    // Unknown (offline, or checks not set up on the server yet): show what Play says.
    _markPremium(verified ?? true);
  }

  /// Sends a Play purchase token to the proxy, which checks it with Google.
  /// Returns null when it could not be checked.
  Future<bool?> verifyPurchase(String token) async {
    if (!auth.available || auth.user == null) return null;
    try {
      final p = Proxy.build;
      if (p.base.isEmpty) return null;
      final session = await aiSession()
        ..remove('x-question-id');
      final res = await http
          .post(Uri.parse('${p.base}/purchase'),
              headers: {'x-app-token': p.token, 'content-type': 'application/json', ...session},
              body: jsonEncode({'purchaseToken': token}))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      return (jsonDecode(res.body) as Map<String, dynamic>)['premium'] == true;
    } catch (e) {
      debugPrint('purchase check: $e');
      return null;
    }
  }

  int get maxFileBytes => premium ? Plan.premiumMaxFileBytes : Plan.freeMaxFileBytes;

  // The proxy counts questions per UTC day, so the phone's count follows the same day.
  String get _today {
    final d = DateTime.now().toUtc();
    return '${d.year}-${d.month}-${d.day}';
  }

  /// Takes the proxy's count of questions left today as the truth.
  void _serverLeft(int left) {
    if (premium) return;
    final used = (Plan.freeDailyQuestions - left).clamp(0, Plan.freeDailyQuestions);
    if (used == questionsToday) return;
    _prefs.setString('qDay', _today);
    _prefs.setInt('qCount', used);
    notifyListeners();
  }

  String? _deviceId;
  final Map<String, String> _questionIds = {};

  /// Big files start uploading as soon as they are attached; the question that
  /// follows reuses this id, so the upload and the question count as one.
  String? _nextQuestionId;
  final Map<String, Future<void>> _uploads = {};

  AiClient _client(Map<String, String> session) => AiClient(
        session: session,
        onQuotaLeft: _serverLeft,
        preferPro: premium,
        geminiModel: _prefs.getString('geminiModel') ?? AiClient.defaultGeminiModel,
        onModelChanged: (m) => _prefs.setString('geminiModel', m),
      );

  void _preUpload(Attachment a) {
    if (!AiClient.needsUpload(a) || !canAsk || !Proxy.build.enabled) return;
    final qid = _nextQuestionId ??= _uuid.v4();
    final slot = [...pending, ...?current?.attachments].map((x) => x.geminiSlot).nonNulls.firstOrNull;
    _uploads[a.id] = () async {
      try {
        await _client(await aiSession(questionId: qid)).prepare(a, slot: slot);
      } catch (e) {
        debugPrint('pre-upload ${a.name}: $e');
      } finally {
        _uploads.remove(a.id);
      }
    }();
  }

  /// What the proxy needs to know who is asking (see [AiClient.session]).
  Future<Map<String, String>> aiSession({String kind = 'ask', String? questionId}) async {
    String? token;
    try {
      token = await auth.user?.getIdToken();
    } catch (e) {
      debugPrint('id token: $e');
    }
    _deviceId ??= await deviceId();
    return {
      'x-user-token': ?token,
      if (_deviceId != null && _deviceId!.isNotEmpty) 'x-device-id': _deviceId!,
      'x-question-id': questionId ?? _uuid.v4(),
      'x-kind': kind,
    };
  }

  /// Deletes the Firebase account, then the subscription record the proxy keeps
  /// for it (with the token taken before, which stays valid for up to an hour).
  Future<String?> deleteAccount() async {
    Map<String, String>? session;
    try {
      session = await aiSession()
        ..remove('x-question-id');
    } catch (_) {}
    final err = await auth.deleteAccount();
    if (err != null) return err;
    _markPremium(false);
    try {
      final p = Proxy.build;
      if (p.base.isNotEmpty && session != null) {
        await http
            .delete(Uri.parse('${p.base}/account'), headers: {'x-app-token': p.token, ...session})
            .timeout(const Duration(seconds: 15));
      }
    } catch (e) {
      debugPrint('account forget: $e');
    }
    return null;
  }

  /// Signs out; a paid plan the server gave this account stays with it.
  Future<void> signOut() async {
    await auth.signOut();
    if (_prefs.getBool('premiumFromServer') == true) {
      await _prefs.remove('premiumFromServer');
      _markPremium(false);
    }
    _rechecked = false;
  }

  bool _rechecked = false;

  /// Asks the proxy how many free questions are left today, and which plan it
  /// gives this account.
  Future<void> syncQuota() async {
    if (!auth.available || auth.user == null) return;
    try {
      final p = Proxy.build;
      if (p.base.isEmpty) return;
      final session = await aiSession()
        ..remove('x-question-id');
      final res = await http
          .get(Uri.parse('${p.base}/quota'), headers: {'x-app-token': p.token, ...session})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        if (j['plan'] == 'premium') {
          // Also the owner's accounts, which the server gives the paid plan.
          _prefs.setBool('premiumFromServer', true);
          _markPremium(true);
        } else if (_prefs.getBool('premiumFromServer') == true) {
          // Another account on this phone: the server's paid plan does not carry over.
          _prefs.remove('premiumFromServer');
          _markPremium(false);
          _rechecked = true;
          await billing.refresh();
        } else if (premium && j['verify'] == true && !_rechecked) {
          // The server has no record (new account, or the month renewed): send Play's token again.
          _rechecked = true;
          await billing.refresh();
        } else if (j['verify'] == true && _rechecked) {
          _markPremium(false);
        }
        final left = j['left'];
        if (!premium && left is num && left >= 0) _serverLeft(left.toInt());
      }
    } catch (e) {
      debugPrint('quota sync: $e');
    }
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
    auth.languageCode = v;
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
        if (c.attachments.map((a) => a.moveTextToFile()).toList().contains(true)) await _save(c);
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
    for (final f in [File(a.path), File('${a.path}.txt')]) {
      if (await f.exists()) await f.delete();
    }
    await _save(c);
    notifyListeners();
  }

  // ---------- attachments ----------
  /// The file being added right now, for the progress ring under the composer.
  String? loadName;

  /// 0..1 while the file is copied and read; null while its size is unknown.
  double? loadProgress;

  /// 'prepare' (the phone hands the file over), 'copy', or 'read' (pages).
  String loadStage = '';

  /// Bytes handed over so far while preparing, and pages read so far.
  int loadBytes = 0, loadDone = 0, loadTotal = 0;

  int _shownPercent = -1;
  void _progress(String stage, double? p, {int done = 0, int total = 0}) {
    final pct = p == null ? -1 : (p * 100).floor();
    if (stage == loadStage && pct == _shownPercent && p != null) return;
    loadStage = stage;
    loadProgress = p;
    loadDone = done;
    loadTotal = total;
    _shownPercent = pct;
    notifyListeners();
  }

  /// The phone's file manager is handing a picked file over (it copies it first).
  void preparing(bool on, {int bytes = 0}) {
    if (on) {
      loadName ??= '';
      loadStage = 'prepare';
      loadProgress = null;
      loadBytes = bytes;
    } else if (loadStage == 'prepare') {
      loadName = null;
      loadStage = '';
      loadBytes = 0;
    }
    notifyListeners();
  }

  /// Validates, copies and reads one picked file. Throws [AttachRejected].
  Future<void> addAttachment(String name, Uint8List bytes, String defaultTitle) =>
      addAttachmentFrom(name, bytes.length, () => Stream.value(bytes), defaultTitle);

  /// Like [addAttachment], but streams the file in so a 300 MB book is never
  /// held twice in memory, and reports progress. When [movable] is the path of
  /// a temporary copy the picker already made, it is moved instead of copied.
  Future<void> addAttachmentFrom(String name, int length, Stream<List<int>> Function() open, String defaultTitle,
      {String? movable}) async {
    final ext = extensionOf(name);
    if (legacyOffice.contains(ext)) throw AttachRejected('legacy', name);
    if (!supportedExtensions.contains(ext)) throw AttachRejected('unsupported', name);
    if (length > maxFileBytes) throw AttachRejected('tooLarge', name);

    processing++;
    loadName = name;
    _shownPercent = -1;
    // Reading the pages is most of the work for PDFs and Office files.
    final copyShare = const {'pdf', 'docx', 'pptx', 'xlsx'}.contains(ext) ? 0.15 : 0.9;
    _progress('copy', 0);
    File? file;
    var keep = false;
    try {
      final conv = await _ensureConversation(defaultTitle);
      final id = _uuid.v4();
      final dir = _filesDir(conv.id);
      await dir.create(recursive: true);
      file = File('${dir.path}/$id.$ext');
      var moved = false;
      if (movable != null) {
        try {
          await File(movable).rename(file.path);
          moved = true;
        } catch (_) {}
      }
      if (!moved) {
        final sink = file.openWrite();
        var got = 0;
        try {
          await for (final chunk in open()) {
            sink.add(chunk);
            got += chunk.length;
            if (got > maxFileBytes) throw AttachRejected('tooLarge', name);
            if (length > 0) _progress('copy', copyShare * (got / length).clamp(0, 1));
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      }
      final size = await file.length();
      if (size > maxFileBytes) throw AttachRejected('tooLarge', name);
      final head = await _head(file);
      final bad = validateBytes(ext, head);
      if (bad != null) throw AttachRejected(bad, name);
      _progress('read', copyShare);

      final result = const {'jpg', 'jpeg', 'png', 'webp'}.contains(ext)
          ? ExtractResult(null)
          : await _extract(file.path, ext, (done, total) {
              _progress('read', copyShare + (1 - copyShare) * (total == 0 ? 1 : done / total), done: done, total: total);
            });
      _progress('read', 1);
      // A big book's text gets its own file, read only when it is asked about.
      final text = result.text;
      String? textFile;
      if (text != null && text.length > Attachment.ownFileChars) {
        textFile = '${file.path}.txt';
        await File(textFile).writeAsString(text, flush: true);
      }
      final added = Attachment(
        id: id,
        name: name,
        ext: ext,
        size: size,
        path: file.path,
        extractedText: text,
        textFile: textFile,
        note: result.note,
        pages: result.pages,
        textPages: result.textPages,
      );
      pending.add(added);
      keep = true;
      _preUpload(added);
    } finally {
      if (!keep && file != null) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      processing--;
      if (processing == 0) {
        loadName = null;
        loadProgress = null;
        loadStage = '';
      }
      notifyListeners();
    }
  }

  static Future<Uint8List> _head(File f) async {
    final raf = await f.open();
    try {
      return await raf.read(8192);
    } finally {
      await raf.close();
    }
  }

  /// Reads the text in a background isolate (the file is opened there, so
  /// big books are not copied between isolates) with page-by-page progress.
  static Future<ExtractResult> _extract(String path, String ext, ExtractProgress onProgress) async {
    final port = ReceivePort();
    final done = Completer<ExtractResult>();
    port.listen((m) {
      if (m is List && m.length == 2 && m[0] is int) {
        onProgress(m[0] as int, m[1] as int);
      } else if (m is ExtractResult) {
        if (!done.isCompleted) done.complete(m);
      } else if (!done.isCompleted) {
        // An error (a list of message and stack) or the isolate ended without an answer.
        debugPrint('extract: $m');
        done.complete(ExtractResult(null, note: 'extractFailed'));
      }
    });
    try {
      await Isolate.spawn(_extractWorker, (port.sendPort, path, ext), onError: port.sendPort, onExit: port.sendPort);
      return await done.future;
    } catch (e) {
      debugPrint('extract: $e');
      return ExtractResult(null, note: 'extractFailed');
    } finally {
      port.close();
    }
  }

  Future<void> removePending(Attachment a) async {
    pending.remove(a);
    for (final f in [File(a.path), File('${a.path}.txt')]) {
      if (await f.exists()) await f.delete();
    }
    notifyListeners();
  }

  void _discardPending() {
    for (final a in pending) {
      for (final f in [File(a.path), File('${a.path}.txt')]) {
        if (f.existsSync()) f.deleteSync();
      }
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
    _questionIds[conv.id] = _nextQuestionId ?? _uuid.v4();
    _nextQuestionId = null;
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
    if (!failed || !_questionIds.containsKey(conv.id)) {
      if (!canAsk) return false;
      _countQuestion();
      // A new question for the proxy; retrying a failed answer keeps the old id.
      _questionIds[conv.id] = _uuid.v4();
    }
    if (conv.messages.last.role == Role.assistant) conv.messages.removeLast();
    await _answer(conv);
    return true;
  }

  Future<void> _answer(Conversation conv) async {
    final reply = Message(id: _uuid.v4(), role: Role.assistant, text: '', status: MsgStatus.streaming);
    conv.updatedAt = DateTime.now();
    _sort();
    final session = await aiSession(questionId: _questionIds[conv.id]);
    final client = _client(session);
    conv.messages.add(reply);
    notifyListeners();
    // A big file still uploading from when it was attached: finish that first.
    final waits = [for (final a in conv.attachments) ?_uploads[a.id]];
    if (waits.isNotEmpty) {
      reply.note = 'reading';
      notifyListeners();
      await Future.wait(waits);
      reply.note = null;
    }
    final stream = client.reply(conv);

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
