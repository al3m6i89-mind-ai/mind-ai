import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'seed.dart';
import 'social_id.dart';
import 'social_remote.dart';
import 'social_store.dart';
import 'text_utils.dart';

export 'models.dart';

class SearchResults {
  const SearchResults({this.users = const [], this.posts = const {}, this.exactId});
  final List<SocialUser> users;
  final Map<PostKind, List<SocialPost>> posts;

  /// Set when the query was a valid unified ID that belongs to someone.
  final SocialUser? exactId;

  bool get isEmpty => users.isEmpty && posts.values.every((l) => l.isEmpty);
}

/// The whole social space: one account (one ID) shared by Reels, Photos and
/// Posts, with one follow graph, one inbox and one notification list.
class SocialService extends ChangeNotifier {
  SocialService(this._store, {DateTime Function()? clock, this.remote}) : _clock = clock ?? DateTime.now;

  final SocialStore _store;

  /// The server (Firebase). Null keeps everything on this phone.
  final SocialRemote? remote;
  bool get online => remote != null;

  /// The last write the server refused, to show the user.
  String? lastError;
  final DateTime Function() _clock;
  final _uuid = const Uuid();

  final Map<String, SocialUser> _users = {};
  final Map<String, SocialPost> _posts = {};
  final Map<String, Comment> _comments = {};
  final Map<String, Story> _stories = {};
  final List<Notice> _notices = [];
  final Map<String, Chat> _chats = {};
  String? _meId;
  bool ready = false;

  // ---- infinite scroll (server mode)
  static const pageSize = 24;

  /// Newest posts the server keeps live (FirebaseSocialRemote.liveWindow).
  static const liveWindow = 150;
  final Map<String, DateTime> _failedAt = {};
  final Set<String> _livePosts = {};
  final Map<String, String> _cursors = {};
  final Set<String> _exhausted = {};
  final Set<String> _loadingPages = {};

  /// The live window moved: new and changed posts come in; a post that left
  /// the window only because newer ones arrived stays (it's still real), while
  /// one missing from inside the window was deleted.
  void _applyLivePosts(List<SocialPost> live) {
    final ids = {for (final p in live) p.id};
    final oldest = live.isEmpty ? null : live.map((p) => p.createdAt).reduce((a, b) => a.isBefore(b) ? a : b);
    for (final id in _livePosts.difference(ids)) {
      final p = _posts[id];
      if (p == null) continue;
      final slidOut = oldest != null && p.createdAt.isBefore(oldest) && live.length >= liveWindow;
      if (!slidOut) _posts.remove(id);
    }
    for (final p in live) {
      _posts[p.id] = p;
    }
    _livePosts
      ..clear()
      ..addAll(ids);
  }

  static String _pageKey(PostKind? kind, String? authorId) => '${kind?.name ?? '*'}|${authorId ?? '*'}';

  /// Whether older posts may exist for this list (always false on the phone-only mode,
  /// which already has everything).
  bool canLoadMore({PostKind? kind, String? authorId}) => online && !_exhausted.contains(_pageKey(kind, authorId));

  bool isLoadingMore({PostKind? kind, String? authorId}) => _loadingPages.contains(_pageKey(kind, authorId));

  bool get loadingAnyPage => _loadingPages.isNotEmpty;

  /// Fetches the next page of older posts for a section and/or a person.
  /// Returns how many new posts arrived.
  Future<int> loadMore({PostKind? kind, String? authorId}) async {
    final key = _pageKey(kind, authorId);
    if (!online || _exhausted.contains(key) || _loadingPages.contains(key)) return 0;
    // After a failure (no network, index still building) wait a little before retrying.
    final failed = _failedAt[key];
    if (failed != null && DateTime.now().difference(failed) < const Duration(seconds: 20)) return 0;
    _loadingPages.add(key);
    notifyListeners();
    var added = 0;
    try {
      // Continue below this list's last page; the first page starts below the
      // live window (which already holds everything newer, for every list).
      // Posts loaded by other lists don't move the cursor, so nothing is skipped.
      var before = _cursors[key];
      if (before == null && _livePosts.isNotEmpty && _livePosts.length < liveWindow) {
        // The live window isn't even full: the server has nothing older.
        _exhausted.add(key);
        return 0;
      }
      if (before == null) {
        final live = _livePosts.map((id) => _posts[id]).whereType<SocialPost>();
        if (live.length >= liveWindow) {
          before = live.map((p) => p.createdAt).reduce((a, b) => a.isBefore(b) ? a : b).toUtc().toIso8601String();
        }
      }
      final docs = await remote!.postsPage(kind: kind?.name, authorId: authorId, before: before, limit: pageSize);
      for (final d in docs) {
        final p = SocialPost.fromJson(d);
        if (!_posts.containsKey(p.id)) added++;
        _posts[p.id] = p;
      }
      if (docs.isNotEmpty) _cursors[key] = docs.last['createdAt'] as String;
      if (docs.length < pageSize) _exhausted.add(key);
      _failedAt.remove(key);
    } catch (e) {
      lastError = '$e';
      _failedAt[key] = DateTime.now();
    } finally {
      _loadingPages.remove(key);
      notifyListeners();
    }
    return added;
  }

  DateTime get now => _clock();

  // ======================================================== load / save

  Future<void> init() async {
    if (online) {
      await _connect();
      ready = true;
      notifyListeners();
      return;
    }
    final data = await _store.load();
    if (data == null) {
      final seed = SocialSeed(now)..build();
      for (final u in seed.users) {
        _users[u.id] = u;
      }
      for (final p in seed.posts) {
        _posts[p.id] = p;
      }
      for (final c in seed.comments) {
        _comments[c.id] = c;
      }
      for (final s in seed.stories) {
        _stories[s.id] = s;
      }
      await _save();
    } else {
      for (final e in data['users'] as List? ?? const []) {
        final u = SocialUser.fromJson(e as Map<String, dynamic>);
        _users[u.id] = u;
      }
      for (final e in data['posts'] as List? ?? const []) {
        final p = SocialPost.fromJson(e as Map<String, dynamic>);
        _posts[p.id] = p;
      }
      for (final e in data['comments'] as List? ?? const []) {
        final c = Comment.fromJson(e as Map<String, dynamic>);
        _comments[c.id] = c;
      }
      for (final e in data['stories'] as List? ?? const []) {
        final s = Story.fromJson(e as Map<String, dynamic>);
        _stories[s.id] = s;
      }
      for (final e in data['notices'] as List? ?? const []) {
        _notices.add(Notice.fromJson(e as Map<String, dynamic>));
      }
      for (final e in data['chats'] as List? ?? const []) {
        final c = Chat.fromJson(e as Map<String, dynamic>);
        _chats[c.key] = c;
      }
      final me = data['me'] as String?;
      _meId = me != null && _users.containsKey(me) ? me : null;
      // Stories older than a day are gone.
      _stories.removeWhere((_, s) => !s.isLive(now));
    }
    ready = true;
    notifyListeners();
  }

  // ======================================================== server

  /// Links the signed-in login to its profile and starts the live data.
  Future<void> _connect() async {
    final r = remote!;
    _meId = null;
    if (r.authUid == null) return;
    try {
      _meId = await r.linkedId();
    } catch (e) {
      lastError = '$e';
    }
    if (_meId != null) r.listen(_meId!, _apply);
  }

  void _apply(String collection, List<Map<String, dynamic>> docs) {
    switch (collection) {
      case 'users':
        final mine = me;
        _users
          ..clear()
          ..addEntries(docs.map(SocialUser.fromJson).map((u) => MapEntry(u.id, u)));
        if (mine != null) _users.putIfAbsent(mine.id, () => mine);
      case 'posts':
        _applyLivePosts(docs.map(SocialPost.fromJson).toList());
      case 'comments':
        _comments
          ..clear()
          ..addEntries(docs.map(Comment.fromJson).map((c) => MapEntry(c.id, c)));
      case 'stories':
        _stories
          ..clear()
          ..addEntries(docs.map(Story.fromJson).map((x) => MapEntry(x.id, x)));
      case 'notices':
        _notices
          ..clear()
          ..addAll(docs.map(Notice.fromJson))
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case 'chats':
        _chatDocs = docs;
        _rebuildChats();
      case 'messages':
        _messageDocs = docs;
        _rebuildChats();
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> _chatDocs = [];
  List<Map<String, dynamic>> _messageDocs = [];

  void _rebuildChats() {
    _chats.clear();
    for (final d in _chatDocs) {
      final c = Chat.fromJson({...d, 'messages': const []});
      _chats[c.key] = c;
    }
    for (final d in _messageDocs) {
      final members = (d['members'] as List).cast<String>();
      if (members.length != 2) continue;
      final chat = _chats.putIfAbsent(Chat.keyFor(members[0], members[1]), () => Chat(members: members));
      chat.messages.add(Message.fromJson(d));
    }
    for (final c in _chats.values) {
      c.messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
  }

  /// Sends a change to the server; never throws (the live data restores the
  /// server's truth if a write is refused, and [lastError] says why).
  void _send(Future<void> Function(SocialRemote r) write) {
    final r = remote;
    if (r == null) return;
    write(r).catchError((Object e) {
      lastError = e is ArgumentError ? '${e.message}' : '$e';
      notifyListeners();
    });
  }

  Future<String> _media(String path) => online ? remote!.upload(path) : _store.importMedia(path);

  /// The e-mail of the signed-in login (server mode).
  String? get signedInEmail => remote?.authEmail;
  bool get signedIn => remote?.authUid != null;

  Future<void> signIn(String email, String password) async {
    await remote!.signIn(email, password);
    await _connect();
    notifyListeners();
  }

  Future<void> signUp(String email, String password) async {
    await remote!.signUp(email, password);
    await _connect();
    notifyListeners();
  }

  Future<void> resetPassword(String email) => remote!.resetPassword(email);

  Future<void> signOut() async {
    if (!online) return;
    await remote!.signOut();
    _meId = null;
    _users.clear();
    _posts.clear();
    _comments.clear();
    _stories.clear();
    _notices.clear();
    _chats.clear();
    _chatDocs = [];
    _messageDocs = [];
    notifyListeners();
  }

  Future<void> _save() async {
    if (online) return;
    await _store.save({
    'version': 1,
    'me': _meId,
    'users': _users.values.map((u) => u.toJson()).toList(),
    'posts': _posts.values.map((p) => p.toJson()).toList(),
    'comments': _comments.values.map((c) => c.toJson()).toList(),
    'stories': _stories.values.map((s) => s.toJson()).toList(),
    'notices': _notices.map((n) => n.toJson()).toList(),
    'chats': _chats.values.map((c) => c.toJson()).toList(),
    });
  }

  Future<void> _changed() async {
    notifyListeners();
    await _save();
  }

  // ======================================================== accounts

  SocialUser? get me => _meId == null ? null : _users[_meId];
  String get meId => _meId ?? '';
  bool get hasAccount => me != null;

  /// Accounts created on this phone (switchable).
  List<SocialUser> get localAccounts => _users.values.where((u) => u.local).toList();

  SocialUser? user(String id) => _users[id];
  SocialUser? byHandle(String handle) {
    final h = handle.toLowerCase().replaceFirst('@', '');
    for (final u in _users.values) {
      if (u.handle.toLowerCase() == h) return u;
    }
    return null;
  }

  /// Finds a person by their unified ID, however it was typed.
  SocialUser? byId(String input) {
    final id = SocialId.normalize(input);
    return id == null ? null : _users[id];
  }

  bool handleFree(String handle, {String? exceptId}) {
    final u = byHandle(handle);
    return u == null || u.id == exceptId;
  }

  /// Creates an account with a new unified ID and makes it the active one.
  Future<SocialUser> createAccount({required String name, required String handle, String bio = '', String avatar = ''}) async {
    final h = handle.trim().toLowerCase();
    final problem = Handle.problem(h);
    if (problem != null) throw ArgumentError(problem);
    if (!handleFree(h)) throw ArgumentError('المعرّف @$h مستخدم، جرّب غيره');
    if (name.trim().isEmpty) throw ArgumentError('اكتب اسمك');
    SocialUser make() => SocialUser(
      id: SocialId.generate(taken: _users.keys.toSet()),
      handle: h,
      name: name.trim(),
      bio: bio.trim(),
      local: !online,
      joined: now,
    );
    var u = make();
    if (online) {
      if (remote!.authUid == null) throw StateError('سجّل الدخول أولاً');
      // The server is the judge of uniqueness; a clashing ID is simply drawn again.
      for (var attempt = 0;; attempt++) {
        try {
          await remote!.createProfile(u);
          break;
        } on StateError catch (e) {
          if (e.message != 'id-taken' || attempt > 5) rethrow;
          u = make();
        }
      }
      if (avatar.isNotEmpty) {
        u.avatar = await _media(avatar);
        _send((r) => r.patch('users', u.id, {'avatar': u.avatar}));
      }
      _users[u.id] = u;
      _meId = u.id;
      remote!.listen(u.id, _apply);
      notifyListeners();
      return u;
    }
    if (avatar.isNotEmpty) u.avatar = await _media(avatar);
    _users[u.id] = u;
    _meId = u.id;
    final official = byHandle('mindai');
    if (official != null) _follow(u, official);
    await _changed();
    return u;
  }

  Future<void> switchAccount(String id) async {
    if (online || _users[id]?.local != true) return;
    _meId = id;
    await _changed();
  }

  Future<void> updateProfile({String? name, String? handle, String? bio, String? link, String? avatarPath, bool? private}) async {
    final u = me;
    if (u == null) return;
    if (handle != null) {
      final h = handle.trim().toLowerCase();
      final problem = Handle.problem(h);
      if (problem != null) throw ArgumentError(problem);
      if (!handleFree(h, exceptId: u.id)) throw ArgumentError('المعرّف @$h مستخدم، جرّب غيره');
      if (online) await remote!.changeHandle(u.id, u.handle, h);
      u.handle = h;
    }
    if (name != null) {
      if (name.trim().isEmpty) throw ArgumentError('الاسم لا يكون فارغاً');
      u.name = name.trim();
    }
    if (bio != null) u.bio = bio.trim();
    if (link != null) u.link = link.trim();
    if (private != null) u.private = private;
    if (avatarPath != null) u.avatar = avatarPath.isEmpty ? '' : await _media(avatarPath);
    _send((r) => r.patch('users', u.id, {'name': u.name, 'bio': u.bio, 'link': u.link, 'private': u.private, 'avatar': u.avatar}));
    await _changed();
  }

  // ======================================================== follow / block

  bool follows(String a, String b) => _users[a]?.following.contains(b) ?? false;
  bool isFollowing(String id) => follows(meId, id);

  void _follow(SocialUser a, SocialUser b) {
    a.following.add(b.id);
    b.followers.add(a.id);
  }

  Future<void> toggleFollow(String id) async {
    final a = me, b = _users[id];
    if (a == null || b == null || a.id == b.id) return;
    if (a.following.remove(b.id)) {
      b.followers.remove(a.id);
      _send((r) => r.patch('users', a.id, {'following': ArrayRemove(b.id)}));
      _send((r) => r.patch('users', b.id, {'followers': ArrayRemove(a.id)}));
    } else {
      _follow(a, b);
      _send((r) => r.patch('users', a.id, {'following': ArrayAdd(b.id)}));
      _send((r) => r.patch('users', b.id, {'followers': ArrayAdd(a.id)}));
      _notify(NoticeType.follow, to: b.id);
    }
    await _changed();
  }

  bool isBlocked(String id) => me?.blocked.contains(id) ?? false;

  Future<void> toggleBlock(String id) async {
    final a = me, b = _users[id];
    if (a == null || b == null || a.id == b.id) return;
    if (!a.blocked.remove(id)) {
      a.blocked.add(id);
      // Blocking also removes the follow both ways.
      a.following.remove(id);
      b.followers.remove(a.id);
      b.following.remove(a.id);
      a.followers.remove(id);
      _send((r) => r.patch('users', a.id, {'blocked': ArrayAdd(id)}));
      _send((r) => r.patch('users', a.id, {'following': ArrayRemove(id)}));
      _send((r) => r.patch('users', a.id, {'followers': ArrayRemove(id)}));
      _send((r) => r.patch('users', id, {'followers': ArrayRemove(a.id)}));
      _send((r) => r.patch('users', id, {'following': ArrayRemove(a.id)}));
    } else {
      _send((r) => r.patch('users', a.id, {'blocked': ArrayRemove(id)}));
    }
    await _changed();
  }

  /// People to suggest: followed by people I follow first, then popular.
  List<SocialUser> suggestions({int max = 10}) {
    final m = me;
    final score = <String, int>{};
    for (final u in _users.values) {
      if (m == null || u.id == m.id || m.following.contains(u.id) || m.blocked.contains(u.id)) continue;
      var s = u.followers.length;
      if (m.following.any((f) => _users[f]?.following.contains(u.id) ?? false)) s += 100;
      if (u.following.contains(m.id)) s += 200;
      score[u.id] = s;
    }
    final ids = score.keys.toList()..sort((a, b) => score[b]!.compareTo(score[a]!));
    return ids.take(max).map((id) => _users[id]!).toList();
  }

  // ======================================================== reading posts

  SocialPost? post(String id) => _posts[id];

  bool _visible(SocialPost p) {
    final m = me;
    if (m == null) return true;
    final author = _users[p.authorId];
    if (author == null || m.blocked.contains(p.authorId) || author.blocked.contains(m.id)) return false;
    // A private account shows its content only to followers.
    return !author.private || author.id == m.id || m.following.contains(author.id);
  }

  /// Ranking used by every "for you" feed: engagement, decayed by age, with a
  /// boost for people you follow.
  static double rank({
    required int likes,
    required int comments,
    required int reposts,
    required int saves,
    required int views,
    required double ageHours,
    bool followed = false,
  }) {
    final engagement = 1 + likes * 2 + comments * 3 + reposts * 4 + saves * 3 + views * 0.05;
    final score = engagement / pow(ageHours + 2, 1.5);
    return followed ? score * 1.5 : score;
  }

  double _score(SocialPost p) => rank(
    likes: p.likes.length,
    comments: commentCount(p),
    reposts: repostCount(p),
    saves: p.saves.length,
    views: p.views,
    ageHours: now.difference(p.createdAt).inMinutes / 60,
    followed: isFollowing(p.authorId),
  );

  /// The feed for a section. [following] limits it to people you follow (and
  /// you), newest first; otherwise everything is ranked for you.
  List<SocialPost> feed(PostKind kind, {bool following = false}) {
    final m = me;
    final all = _posts.values.where((p) => p.kind == kind && p.replyTo == null && _visible(p));
    if (following) {
      final list = all.where((p) => p.authorId == m?.id || (m?.following.contains(p.authorId) ?? false)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    }
    final list = all.where((p) => p.repostOf == null).toList();
    final scores = {for (final p in list) p.id: _score(p)};
    list.sort((a, b) => scores[b.id]!.compareTo(scores[a.id]!));
    return list;
  }

  /// Photos home: people you follow newest first, then suggested posts.
  List<SocialPost> photoHome() {
    final mine = feed(PostKind.photo, following: true).where((p) => p.repostOf == null).toList();
    final seen = mine.map((p) => p.id).toSet();
    return [...mine, ...feed(PostKind.photo).where((p) => !seen.contains(p.id))];
  }

  /// Everything a person made in one section (reposts included in Posts).
  List<SocialPost> byAuthor(String uid, PostKind kind, {bool replies = false}) {
    final list = _posts.values
        .where((p) => p.authorId == uid && p.kind == kind && (replies ? p.replyTo != null : p.replyTo == null) && _visible(p))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<SocialPost> saved(PostKind kind) => _posts.values.where((p) => p.kind == kind && p.saves.contains(meId)).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<SocialPost> likedBy(String uid, PostKind kind) =>
      _posts.values.where((p) => p.kind == kind && p.likes.contains(uid) && _visible(p)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Answers to a post in the Posts section, oldest first.
  List<SocialPost> replies(String postId) =>
      _posts.values.where((p) => p.replyTo == postId && _visible(p)).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// The chain of posts above a reply, root first.
  List<SocialPost> ancestors(SocialPost p) {
    final out = <SocialPost>[];
    var cur = p.replyTo == null ? null : _posts[p.replyTo];
    while (cur != null && out.length < 20) {
      out.insert(0, cur);
      cur = cur.replyTo == null ? null : _posts[cur.replyTo];
    }
    return out;
  }

  int commentCount(SocialPost p) =>
      p.kind == PostKind.post ? replies(p.id).length : _comments.values.where((c) => c.postId == p.id).length;

  int repostCount(SocialPost p) =>
      _posts.values.where((x) => (x.repostOf == p.id || x.quoteOf == p.id) && _users.containsKey(x.authorId)).length;

  /// Who reposted or quoted a post.
  List<String> reposters(String postId) => {
    for (final x in _posts.values)
      if (x.repostOf == postId || x.quoteOf == postId) x.authorId,
  }.toList();

  List<SocialPost> quotes(String postId) =>
      _posts.values.where((x) => x.quoteOf == postId && _visible(x)).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  bool liked(SocialPost p) => p.likes.contains(meId);
  bool isSaved(SocialPost p) => p.saves.contains(meId);
  bool reposted(SocialPost p) => _posts.values.any((x) => x.repostOf == p.id && x.authorId == meId);

  /// Total likes a person has received on everything they posted.
  int likesReceived(String uid) => _posts.values.where((p) => p.authorId == uid).fold(0, (s, p) => s + p.likes.length);

  int postCount(String uid) => _posts.values.where((p) => p.authorId == uid && p.replyTo == null && p.repostOf == null).length;

  // ======================================================== actions on posts

  Future<void> toggleLike(SocialPost p) async {
    if (!hasAccount) return;
    if (!p.likes.remove(meId)) {
      p.likes.add(meId);
      _send((r) => r.patch('posts', p.id, {'likes': ArrayAdd(meId)}));
      _notify(NoticeType.like, to: p.authorId, postId: p.id);
    } else {
      _send((r) => r.patch('posts', p.id, {'likes': ArrayRemove(meId)}));
    }
    await _changed();
  }

  /// Double-tap: only ever likes, never unlikes.
  Future<void> like(SocialPost p) async {
    if (!liked(p)) await toggleLike(p);
  }

  Future<void> toggleSave(SocialPost p) async {
    if (!hasAccount) return;
    if (!p.saves.remove(meId)) {
      p.saves.add(meId);
      _send((r) => r.patch('posts', p.id, {'saves': ArrayAdd(meId)}));
      _notify(NoticeType.save, to: p.authorId, postId: p.id);
    } else {
      _send((r) => r.patch('posts', p.id, {'saves': ArrayRemove(meId)}));
    }
    await _changed();
  }

  Future<void> markShared(SocialPost p) async {
    p.shares++;
    _send((r) => r.patch('posts', p.id, {'shares': const Increment(1)}));
    await _changed();
  }

  /// Counts a view once per person.
  Future<void> view(SocialPost p) async {
    if (!hasAccount || p.viewers.contains(meId)) return;
    p.viewers.add(meId);
    p.views++;
    _send((r) => r.patch('posts', p.id, {'viewers': ArrayAdd(meId), 'views': const Increment(1)}));
    await _changed();
  }

  Future<SocialPost> createReel({required String videoPath, String caption = '', String sound = '', String thumbPath = ''}) async {
    _checkText(caption, SocialText.captionLimit);
    final src = await _media(videoPath);
    final thumb = thumbPath.isEmpty ? '' : await _media(thumbPath);
    return _add(SocialPost(
      id: _uuid.v4(),
      kind: PostKind.reel,
      authorId: _mustMe(),
      createdAt: now,
      text: caption.trim(),
      sound: sound.trim(),
      media: [Media(src, video: true, thumb: thumb)],
    ));
  }

  Future<SocialPost> createPhoto({required List<String> paths, String caption = '', String location = ''}) async {
    if (paths.isEmpty) throw ArgumentError('اختر صورة واحدة على الأقل');
    if (paths.length > 10) throw ArgumentError('10 صور كحد أقصى');
    _checkText(caption, SocialText.captionLimit);
    final media = [for (final path in paths) Media(await _media(path))];
    return _add(SocialPost(
      id: _uuid.v4(),
      kind: PostKind.photo,
      authorId: _mustMe(),
      createdAt: now,
      text: caption.trim(),
      location: location.trim(),
      media: media,
    ));
  }

  Future<SocialPost> createPost({String text = '', List<String> imagePaths = const [], String? replyTo, String? quoteOf}) async {
    if (text.trim().isEmpty && imagePaths.isEmpty && quoteOf == null) throw ArgumentError('اكتب شيئاً');
    _checkText(text, SocialText.postLimit);
    if (imagePaths.length > 4) throw ArgumentError('4 صور كحد أقصى');
    final media = [for (final path in imagePaths) Media(await _media(path))];
    final p = await _add(SocialPost(
      id: _uuid.v4(),
      kind: PostKind.post,
      authorId: _mustMe(),
      createdAt: now,
      text: text.trim(),
      media: media,
      replyTo: replyTo,
      quoteOf: quoteOf,
    ));
    final parent = replyTo == null ? null : _posts[replyTo];
    if (parent != null) _notify(NoticeType.reply, to: parent.authorId, postId: p.id, text: p.text);
    final quoted = quoteOf == null ? null : _posts[quoteOf];
    if (quoted != null) _notify(NoticeType.quote, to: quoted.authorId, postId: p.id, text: p.text);
    await _changed();
    return p;
  }

  /// Reposts, or takes the repost back when already reposted.
  Future<void> toggleRepost(SocialPost p) async {
    final mine = _posts.values.where((x) => x.repostOf == p.id && x.authorId == meId).toList();
    if (mine.isNotEmpty) {
      for (final x in mine) {
        _posts.remove(x.id);
        _send((r) => r.delete('posts', x.id));
      }
      await _changed();
      return;
    }
    await _add(SocialPost(id: _uuid.v4(), kind: p.kind, authorId: _mustMe(), createdAt: now, repostOf: p.id));
    _notify(NoticeType.repost, to: p.authorId, postId: p.id);
    await _changed();
  }

  Future<void> deletePost(SocialPost p) async {
    if (p.authorId != meId) return;
    if (online) {
      // Comments first: the rules let the post's owner remove them only while the post exists.
      for (final c in _comments.values.where((c) => c.postId == p.id).toList()) {
        await remote!.delete('comments', c.id);
      }
      await remote!.delete('posts', p.id);
    }
    _posts.remove(p.id);
    // Reposts of it go too; replies and quotes stay but show "unavailable".
    _posts.removeWhere((_, x) => x.repostOf == p.id && (!online || x.authorId == meId));
    _comments.removeWhere((_, c) => c.postId == p.id);
    _notices.removeWhere((n) => n.postId == p.id);
    await _changed();
  }

  Future<void> setCommentsOff(SocialPost p, bool off) async {
    if (p.authorId != meId) return;
    p.commentsOff = off;
    _send((r) => r.patch('posts', p.id, {'commentsOff': off}));
    await _changed();
  }

  Future<void> editText(SocialPost p, String text) async {
    if (p.authorId != meId) return;
    _checkText(text, p.kind == PostKind.post ? SocialText.postLimit : SocialText.captionLimit);
    p.text = text.trim();
    _send((r) => r.patch('posts', p.id, {'text': p.text}));
    await _changed();
  }

  Future<SocialPost> _add(SocialPost p) async {
    if (online) await remote!.put('posts', p.id, p.toJson());
    _posts[p.id] = p;
    _notifyMentions(p.text, postId: p.id);
    await _changed();
    return p;
  }

  String _mustMe() {
    if (!hasAccount) throw StateError('أنشئ حسابك أولاً');
    return meId;
  }

  void _checkText(String text, int max) {
    if (text.trim().runes.length > max) throw ArgumentError('النص أطول من $max حرفاً');
  }

  // ======================================================== comments

  /// Top-level comments, most liked first, then newest.
  List<Comment> comments(String postId) {
    final list = _comments.values.where((c) => c.postId == postId && c.parentId == null && _commentVisible(c)).toList()
      ..sort((a, b) {
        final byLikes = b.likes.length.compareTo(a.likes.length);
        return byLikes != 0 ? byLikes : b.createdAt.compareTo(a.createdAt);
      });
    return list;
  }

  List<Comment> answers(String commentId) =>
      _comments.values.where((c) => c.parentId == commentId && _commentVisible(c)).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  bool _commentVisible(Comment c) => !(me?.blocked.contains(c.authorId) ?? false) && _users.containsKey(c.authorId);

  Future<Comment> addComment(String postId, String text, {String? parentId}) async {
    final p = _posts[postId];
    if (p == null) throw ArgumentError('المحتوى غير موجود');
    if (p.commentsOff) throw ArgumentError('التعليقات مغلقة');
    if (text.trim().isEmpty) throw ArgumentError('اكتب تعليقاً');
    _checkText(text, 500);
    // Answers to an answer attach to the top comment, so threads stay one level deep.
    final parent = parentId == null ? null : _comments[parentId];
    final c = Comment(
      id: _uuid.v4(),
      postId: postId,
      authorId: _mustMe(),
      text: text.trim(),
      createdAt: now,
      parentId: parent?.parentId ?? parent?.id,
    );
    if (online) await remote!.put('comments', c.id, c.toJson());
    _comments[c.id] = c;
    _notify(NoticeType.comment, to: p.authorId, postId: p.id, text: c.text);
    if (parent != null && parent.authorId != p.authorId) {
      _notify(NoticeType.reply, to: parent.authorId, postId: p.id, text: c.text);
    }
    _notifyMentions(c.text, postId: p.id);
    await _changed();
    return c;
  }

  Future<void> toggleCommentLike(Comment c) async {
    if (!hasAccount) return;
    if (!c.likes.remove(meId)) {
      c.likes.add(meId);
      _send((r) => r.patch('comments', c.id, {'likes': ArrayAdd(meId)}));
    } else {
      _send((r) => r.patch('comments', c.id, {'likes': ArrayRemove(meId)}));
    }
    await _changed();
  }

  Future<void> deleteComment(Comment c) async {
    final p = _posts[c.postId];
    // The writer, or the owner of the post, can remove a comment.
    if (c.authorId != meId && p?.authorId != meId) return;
    final gone = [c, ..._comments.values.where((x) => x.parentId == c.id && (x.authorId == meId || p?.authorId == meId))];
    for (final x in gone) {
      _comments.remove(x.id);
      _send((r) => r.delete('comments', x.id));
    }
    if (!online) _comments.removeWhere((_, x) => x.parentId == c.id);
    await _changed();
  }

  // ======================================================== stories

  List<Story> storiesOf(String uid) =>
      _stories.values.where((s) => s.authorId == uid && s.isLive(now)).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  bool hasUnseenStory(String uid) => storiesOf(uid).any((s) => !s.seenBy.contains(meId));

  /// People shown in the stories row: me first, then followed people with
  /// unseen stories, then the rest that have stories.
  List<SocialUser> storyRing() {
    final m = me;
    final ids = _stories.values
        .where((s) => s.isLive(now) && s.authorId != m?.id && !(m?.blocked.contains(s.authorId) ?? false))
        .map((s) => s.authorId)
        .toSet()
        .toList();
    int weight(String id) => (hasUnseenStory(id) ? 0 : 2) + (isFollowing(id) ? 0 : 1);
    ids.sort((a, b) => weight(a).compareTo(weight(b)));
    return [?m, ...ids.map((id) => _users[id]).whereType<SocialUser>()];
  }

  Future<Story> addStory(String path, {String caption = '', bool video = false}) async {
    final s = Story(
      id: _uuid.v4(),
      authorId: _mustMe(),
      media: Media(await _media(path), video: video),
      caption: caption.trim(),
      createdAt: now,
    );
    if (online) await remote!.put('stories', s.id, s.toJson());
    _stories[s.id] = s;
    await _changed();
    return s;
  }

  Future<void> markStorySeen(Story s) async {
    if (!hasAccount || s.seenBy.contains(meId)) return;
    s.seenBy.add(meId);
    _send((r) => r.patch('stories', s.id, {'seenBy': ArrayAdd(meId)}));
    await _changed();
  }

  Future<void> toggleStoryLike(Story s) async {
    if (!hasAccount) return;
    if (!s.likes.remove(meId)) {
      s.likes.add(meId);
      _send((r) => r.patch('stories', s.id, {'likes': ArrayAdd(meId)}));
      _notify(NoticeType.storyLike, to: s.authorId);
    } else {
      _send((r) => r.patch('stories', s.id, {'likes': ArrayRemove(meId)}));
    }
    await _changed();
  }

  Future<void> deleteStory(Story s) async {
    if (s.authorId != meId) return;
    _stories.remove(s.id);
    _send((r) => r.delete('stories', s.id));
    await _changed();
  }

  // ======================================================== notifications

  void _notify(NoticeType type, {required String to, String? postId, String text = ''}) {
    if (to == meId || !_users.containsKey(to)) return;
    // Liking, unliking and liking again shouldn't stack up: these get one
    // fixed ID per person, post and kind, so a repeat replaces the old one.
    final once = type == NoticeType.like || type == NoticeType.follow || type == NoticeType.save || type == NoticeType.repost;
    if (once) {
      _notices.removeWhere((n) => n.type == type && n.toId == to && n.fromId == meId && n.postId == postId);
    }
    final n = Notice(
      id: once ? '${type.name}_${meId}_${to}_${postId ?? ''}' : _uuid.v4(),
      type: type,
      toId: to,
      fromId: meId,
      postId: postId,
      text: text.length > 300 ? text.substring(0, 300) : text,
      createdAt: now,
    );
    if (online) {
      // Someone else's notice: it lives on the server only.
      _send((r) => r.put('notices', n.id, n.toJson()));
      return;
    }
    _notices.insert(0, n);
    if (_notices.length > 2000) _notices.removeRange(2000, _notices.length);
  }

  void _notifyMentions(String text, {String? postId}) {
    for (final h in SocialText.mentions(text)) {
      final u = byHandle(h);
      if (u != null) _notify(NoticeType.mention, to: u.id, postId: postId, text: text);
    }
  }

  List<Notice> get notices =>
      _notices.where((n) => n.toId == meId && !(me?.blocked.contains(n.fromId) ?? false)).toList();

  int get unreadNotices => notices.where((n) => !n.read).length;

  Future<void> markNoticesRead() async {
    var any = false;
    for (final n in notices) {
      if (!n.read) {
        n.read = true;
        any = true;
        _send((r) => r.patch('notices', n.id, {'read': true}));
      }
    }
    if (any) await _changed();
  }

  // ======================================================== messages

  List<Chat> get chats => _chats.values.where((c) => c.members.contains(meId) && c.messages.isNotEmpty).toList()
    ..sort((a, b) => b.messages.last.createdAt.compareTo(a.messages.last.createdAt));

  Chat chatWith(String uid) =>
      _chats[Chat.keyFor(meId, uid)] ?? Chat(members: [meId, uid]);

  int get unreadMessages => chats.fold(0, (s, c) => s + c.unread(meId));

  Future<void> sendMessage(String to, {String text = '', String? postId}) async {
    if (text.trim().isEmpty && postId == null) return;
    if (_users[to]?.blocked.contains(meId) ?? false) throw ArgumentError('لا يمكنك مراسلة هذا الحساب');
    final key = Chat.keyFor(_mustMe(), to);
    final chat = _chats.putIfAbsent(key, () => Chat(members: [meId, to]));
    final m = Message(id: _uuid.v4(), fromId: meId, text: text.trim(), postId: postId, createdAt: now);
    if (online) {
      await remote!.put('chats', key, {
        'members': chat.members,
        'readAt': {meId: now.toUtc().toIso8601String()},
      }, merge: true);
      await remote!.put('messages', m.id, {...m.toJson(), 'members': chat.members});
    }
    chat.messages.add(m);
    chat.readAt[meId] = now;
    _notify(NoticeType.message, to: to, text: text.trim());
    await _changed();
  }

  Future<void> markChatRead(String uid) async {
    final chat = _chats[Chat.keyFor(meId, uid)];
    if (chat == null || chat.unread(meId) == 0) return;
    chat.readAt[meId] = now;
    _send((r) => r.patch('chats', chat.key, {'readAt.$meId': now.toUtc().toIso8601String()}));
    await _changed();
  }

  // ======================================================== search & trends

  SearchResults search(String query) {
    final q = query.trim();
    if (q.isEmpty) return const SearchResults();
    final exact = SocialId.looksLikeId(q) ? byId(q) : null;
    final lower = q.toLowerCase();
    final m = me;
    final users = _users.values.where((u) {
      if (m != null && u.blocked.contains(m.id)) return false;
      final h = lower.startsWith('@') ? lower.substring(1) : lower;
      return u.handle.contains(h) || u.name.toLowerCase().contains(lower) || u.id == exact?.id;
    }).toList()
      ..sort((a, b) {
        int w(SocialUser u) => u.id == exact?.id ? 0 : (u.handle == lower.replaceFirst('@', '') ? 1 : 2);
        final c = w(a).compareTo(w(b));
        return c != 0 ? c : b.followers.length.compareTo(a.followers.length);
      });
    final tag = lower.startsWith('#') ? lower.substring(1) : null;
    final posts = <PostKind, List<SocialPost>>{};
    for (final k in PostKind.values) {
      posts[k] = _posts.values
          .where((p) => p.kind == k && p.repostOf == null && _visible(p))
          .where((p) => tag != null ? SocialText.hashtags(p.text).contains(tag) : p.text.toLowerCase().contains(lower))
          .toList()
        ..sort((a, b) => _score(b).compareTo(_score(a)));
    }
    return SearchResults(users: tag != null ? const [] : users, posts: posts, exactId: exact);
  }

  /// Hashtags used most over the last 7 days, across all three sections.
  List<(String, int)> trends({int max = 10}) {
    final since = now.subtract(const Duration(days: 7));
    final counts = <String, int>{};
    for (final p in _posts.values) {
      if (p.createdAt.isBefore(since) || p.repostOf != null) continue;
      for (final t in SocialText.hashtags(p.text)) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final list = counts.entries.toList()
      ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    return [for (final e in list.take(max)) (e.key, e.value)];
  }
}
