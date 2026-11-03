import 'package:flutter_test/flutter_test.dart';
import 'package:mind_ai/services/social/social_remote.dart';
import 'package:mind_ai/services/social/social_service.dart';
import 'package:mind_ai/services/social/social_store.dart';

/// A server holding [posts], answering postsPage like Firestore would.
class _FakeRemote implements SocialRemote {
  _FakeRemote(this.posts);
  final List<SocialPost> posts;
  int calls = 0;

  @override
  String? get authUid => null;

  @override
  Future<List<Map<String, dynamic>>> postsPage({String? kind, String? authorId, String? before, int limit = 24}) async {
    calls++;
    final list = posts
        .where((p) => kind == null || p.kind.name == kind)
        .where((p) => authorId == null || p.authorId == authorId)
        .map((p) => p.toJson())
        .where((j) => before == null || (j['createdAt'] as String).compareTo(before) < 0)
        .toList()
      ..sort((a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String));
    return list.take(limit).toList();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  final start = DateTime.utc(2026, 1, 1);
  SocialPost post(int i, PostKind kind, String author) => SocialPost(
    id: 'p$i',
    kind: kind,
    authorId: author,
    createdAt: start.add(Duration(minutes: i)),
    text: '#$i',
  );

  test('loads older posts page by page until the end, without repeats', () async {
    final all = [for (var i = 0; i < 60; i++) post(i, PostKind.photo, 'A')];
    final remote = _FakeRemote(all);
    final s = SocialService(MemorySocialStore(), remote: remote);
    await s.init();
    expect(s.canLoadMore(kind: PostKind.photo), isTrue);

    expect(await s.loadMore(kind: PostKind.photo), 24);
    expect(await s.loadMore(kind: PostKind.photo), 24);
    expect(await s.loadMore(kind: PostKind.photo), 12);
    expect(s.canLoadMore(kind: PostKind.photo), isFalse);
    expect(await s.loadMore(kind: PostKind.photo), 0);
    expect(remote.calls, 3);
    expect(s.byAuthor('A', PostKind.photo).length, 60);
    // Newest first, all 60 distinct.
    expect(s.byAuthor('A', PostKind.photo).first.id, 'p59');
    expect(s.byAuthor('A', PostKind.photo).map((p) => p.id).toSet().length, 60);
  });

  test('a section and a person page separately', () async {
    final all = [
      for (var i = 0; i < 30; i++) post(i, PostKind.reel, i.isEven ? 'A' : 'B'),
      for (var i = 30; i < 40; i++) post(i, PostKind.post, 'A'),
    ];
    final s = SocialService(MemorySocialStore(), remote: _FakeRemote(all));
    await s.init();
    await s.loadMore(kind: PostKind.reel, authorId: 'B');
    expect(s.byAuthor('B', PostKind.reel).length, 15);
    expect(s.canLoadMore(kind: PostKind.reel, authorId: 'B'), isFalse);
    // The reels section as a whole still has more to give.
    expect(s.canLoadMore(kind: PostKind.reel), isTrue);
    while (s.canLoadMore(kind: PostKind.reel)) {
      await s.loadMore(kind: PostKind.reel);
    }
    expect(s.byAuthor('A', PostKind.reel).length, 15);
    expect(s.byAuthor('B', PostKind.reel).length, 15);
    expect(s.byAuthor('A', PostKind.post), isEmpty);
  });

  test('phone-only mode never pages', () async {
    final s = SocialService(MemorySocialStore());
    await s.init();
    expect(s.canLoadMore(kind: PostKind.reel), isFalse);
    expect(await s.loadMore(kind: PostKind.reel), 0);
  });
}
