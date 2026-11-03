import 'package:flutter_test/flutter_test.dart';
import 'package:mind_ai/services/social/social_id.dart';
import 'package:mind_ai/services/social/social_service.dart';
import 'package:mind_ai/services/social/social_store.dart';
import 'package:mind_ai/services/social/text_utils.dart';

void main() {
  group('unified ID', () {
    test('generates valid, unique IDs in the MA-XXXX-XXXX-X format', () {
      final seen = <String>{};
      for (var i = 0; i < 2000; i++) {
        final id = SocialId.generate(taken: seen);
        expect(RegExp(r'^MA-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]$').hasMatch(id), isTrue, reason: id);
        expect(SocialId.isValid(id), isTrue);
        expect(seen.add(id), isTrue);
      }
    });

    test('accepts sloppy typing and rejects any single wrong character', () {
      final id = SocialId.generate();
      expect(SocialId.normalize(id.toLowerCase().replaceAll('-', ' ')), id);
      expect(SocialId.normalize(id.replaceAll('-', '')), id);
      final raw = id.replaceAll('-', '').substring(2);
      for (var pos = 0; pos < raw.length; pos++) {
        for (final c in SocialId.alphabet.split('')) {
          if (c == raw[pos]) continue;
          final typo = raw.replaceRange(pos, pos + 1, c);
          expect(SocialId.normalize('MA$typo'), isNull, reason: 'typo $typo was accepted');
        }
      }
    });

    test('handles: rules and suggestions', () {
      expect(Handle.problem('ab'), isNotNull);
      expect(Handle.problem('.abc'), isNotNull);
      expect(Handle.problem('ab..c'), isNotNull);
      expect(Handle.problem('عربي'), isNotNull);
      expect(Handle.problem('sara.travels_1'), isNull);
      expect(Handle.problem(Handle.suggest('Sara.Ali+x@mail.com')), isNull);
      expect(Handle.problem(Handle.suggest('a@b.c')), isNull);
    });
  });

  group('text', () {
    test('counts', () {
      expect(SocialText.count(950), '950');
      expect(SocialText.count(1200), '1.2 ألف');
      expect(SocialText.count(15000), '15 ألف');
      expect(SocialText.count(999999), '999 ألف');
      expect(SocialText.count(2500000), '2.5 مليون');
    });

    test('hashtags in Arabic and mentions, not e-mails', () {
      expect(SocialText.hashtags('رحلة #سفر و #Travel_2026'), {'سفر', 'travel_2026'});
      final pieces = SocialText.pieces('مرحبا @sara.travels راسلني a@b.com #فن');
      expect(pieces.where((p) => p.mention != null).map((p) => p.mention), ['sara.travels']);
      expect(pieces.where((p) => p.tag != null).map((p) => p.tag), ['فن']);
      expect(pieces.map((p) => p.text).join(), 'مرحبا @sara.travels راسلني a@b.com #فن');
    });
  });

  group('service', () {
    late MemorySocialStore store;
    late SocialService s;

    setUp(() async {
      store = MemorySocialStore();
      s = SocialService(store);
      await s.init();
    });

    test('seeds three non-empty sections', () {
      for (final k in PostKind.values) {
        expect(s.feed(k), isNotEmpty, reason: k.name);
      }
      expect(s.hasAccount, isFalse);
    });

    test('one account, one ID across all three sections', () async {
      final me = await s.createAccount(name: 'علي', handle: 'Ali_1');
      expect(me.handle, 'ali_1');
      expect(SocialId.isValid(me.id), isTrue);
      final reel = await s.createReel(videoPath: '/v.mp4', caption: 'أول ريل #تجربة');
      final photo = await s.createPhoto(paths: ['/a.jpg', '/b.jpg'], caption: 'صوري');
      final post = await s.createPost(text: 'أول منشور');
      expect({reel.authorId, photo.authorId, post.authorId}, {me.id});
      expect(s.byId(me.id.toLowerCase())?.handle, 'ali_1');
      expect(s.search(me.id).exactId?.id, me.id);
      expect(s.postCount(me.id), 3);
      await expectLater(s.createAccount(name: 'x', handle: 'ALI_1'), throwsArgumentError);
    });

    test('follow once, see them in every section; block hides everything', () async {
      await s.createAccount(name: 'علي', handle: 'ali');
      final sara = s.byHandle('sara.travels')!;
      expect(s.feed(PostKind.reel, following: true).any((p) => p.authorId == sara.id), isFalse);
      await s.toggleFollow(sara.id);
      for (final k in PostKind.values) {
        expect(s.feed(k, following: true).any((p) => p.authorId == sara.id), isTrue, reason: k.name);
      }
      expect(sara.followers, contains(s.meId));
      await s.toggleBlock(sara.id);
      expect(s.isFollowing(sara.id), isFalse);
      for (final k in PostKind.values) {
        expect(s.feed(k).any((p) => p.authorId == sara.id), isFalse, reason: k.name);
      }
    });

    test('likes, saves, views count each person once and persist', () async {
      await s.createAccount(name: 'علي', handle: 'ali');
      final p = s.feed(PostKind.photo).first;
      final before = p.likes.length;
      await s.toggleLike(p);
      await s.like(p); // double tap never unlikes
      expect(p.likes.length, before + 1);
      final views = p.views;
      await s.view(p);
      await s.view(p);
      expect(p.views, views + 1);
      await s.toggleSave(p);
      expect(s.saved(PostKind.photo).map((x) => x.id), contains(p.id));

      final again = SocialService(store);
      await again.init();
      expect(again.me?.handle, 'ali');
      expect(again.post(p.id)!.likes, contains(again.meId));
      expect(again.saved(PostKind.photo).map((x) => x.id), contains(p.id));
    });

    test('comments, threaded answers and notifications between two accounts', () async {
      final a = await s.createAccount(name: 'أ', handle: 'aaa');
      final photo = await s.createPhoto(paths: ['/x.jpg'], caption: 'hi');
      final b = await s.createAccount(name: 'ب', handle: 'bbb');
      await s.toggleFollow(a.id);
      await s.toggleLike(photo);
      final c = await s.addComment(photo.id, 'جميلة @aaa');
      final answer = await s.addComment(photo.id, 'رد', parentId: c.id);
      final deeper = await s.addComment(photo.id, 'رد على الرد', parentId: answer.id);
      expect(deeper.parentId, c.id);
      expect(s.commentCount(photo), 3);

      await s.switchAccount(a.id);
      final types = s.notices.map((n) => n.type).toSet();
      expect(types, containsAll([NoticeType.follow, NoticeType.like, NoticeType.comment, NoticeType.mention]));
      expect(s.notices.every((n) => n.fromId == b.id), isTrue);
      expect(s.unreadNotices, greaterThan(0));
      await s.markNoticesRead();
      expect(s.unreadNotices, 0);

      await s.setCommentsOff(photo, true);
      await s.switchAccount(b.id);
      await expectLater(s.addComment(photo.id, 'x'), throwsArgumentError);
    });

    test('posts: 280 limit, replies, reposts and quotes', () async {
      await s.createAccount(name: 'علي', handle: 'ali');
      await expectLater(s.createPost(text: 'ا' * 281), throwsArgumentError);
      final root = s.feed(PostKind.post).first;
      final before = s.commentCount(root);
      final reply = await s.createPost(text: 'رد', replyTo: root.id);
      expect(s.commentCount(root), before + 1);
      expect(s.ancestors(reply).last.id, root.id);
      expect(s.feed(PostKind.post).any((p) => p.id == reply.id), isFalse);

      final reposts = s.repostCount(root);
      await s.toggleRepost(root);
      expect(s.reposted(root), isTrue);
      expect(s.repostCount(root), reposts + 1);
      await s.toggleRepost(root);
      expect(s.repostCount(root), reposts);
      await s.createPost(text: 'اقتباس', quoteOf: root.id);
      expect(s.repostCount(root), reposts + 1);
      expect(s.reposters(root.id), contains(s.meId));
    });

    test('stories expire after 24 hours and track who saw them', () async {
      var now = DateTime(2026, 1, 1, 12);
      final st = MemorySocialStore();
      final svc = SocialService(st, clock: () => now);
      await svc.init();
      await svc.createAccount(name: 'علي', handle: 'ali');
      final story = await svc.addStory('/s.jpg');
      expect(svc.storyRing().first.id, svc.meId);
      expect(svc.storiesOf(svc.meId), [story]);
      now = now.add(const Duration(hours: 25));
      expect(svc.storiesOf(svc.meId), isEmpty);
    });

    test('messages: one thread per pair, unread counts', () async {
      final a = await s.createAccount(name: 'أ', handle: 'aaa');
      final b = await s.createAccount(name: 'ب', handle: 'bbb');
      await s.sendMessage(a.id, text: 'مرحبا');
      await s.sendMessage(a.id, postId: s.feed(PostKind.reel).first.id);
      await s.switchAccount(a.id);
      expect(s.chats.length, 1);
      expect(s.unreadMessages, 2);
      await s.markChatRead(b.id);
      expect(s.unreadMessages, 0);
    });

    test('trends and hashtag search span all sections', () async {
      await s.createAccount(name: 'علي', handle: 'ali');
      await s.createReel(videoPath: '/v.mp4', caption: '#اختبار_موحد');
      await s.createPhoto(paths: ['/p.jpg'], caption: '#اختبار_موحد');
      await s.createPost(text: '#اختبار_موحد');
      await s.createPost(text: 'مرة أخرى #اختبار_موحد');
      expect(s.trends().first, ('اختبار_موحد', 4));
      final r = s.search('#اختبار_موحد');
      expect(r.posts[PostKind.reel]!.length, 1);
      expect(r.posts[PostKind.photo]!.length, 1);
      expect(r.posts[PostKind.post]!.length, 2);
    });

    test('reports: one per person, auto-hide at 3, moderator actions', () async {
      final a = await s.createAccount(name: 'أ', handle: 'aaa');
      final photo = await s.createPhoto(paths: ['/x.jpg'], caption: 'hi');
      await expectLater(
        s.report(ReportTarget.post, photo.id, authorId: a.id, reason: ReportReason.spam),
        throwsArgumentError,
      );
      for (final h in ['rep1', 'rep2', 'rep3']) {
        await s.createAccount(name: h, handle: h);
        expect(photo.hidden, isFalse);
        await s.report(ReportTarget.post, photo.id, authorId: a.id, reason: ReportReason.spam, note: 'x');
        expect(s.reported(ReportTarget.post, photo.id), isTrue);
      }
      expect(photo.hidden, isTrue);
      // The same person can't report twice.
      await expectLater(
        s.report(ReportTarget.post, photo.id, authorId: a.id, reason: ReportReason.hate),
        throwsArgumentError,
      );
      final cases = s.reportCases();
      expect(cases.length, 1);
      expect(cases.first.reports.length, 3);
      expect(cases.first.reasons.first, (ReportReason.spam, 3));

      await s.dismissReports(cases.first);
      expect(photo.hidden, isFalse);
      expect(s.reportCases(), isEmpty);
      expect(s.reportCases(open: false).length, 1);
    });

    test('a suspended account cannot post, and a removed post is gone', () async {
      final a = await s.createAccount(name: 'أ', handle: 'aaa');
      final post = await s.createPost(text: 'سيُحذف');
      await s.createAccount(name: 'ب', handle: 'bbb');
      await s.report(ReportTarget.post, post.id, authorId: a.id, reason: ReportReason.scam);
      await s.removeReported(s.reportCases().first);
      expect(s.post(post.id), isNull);
      await s.setSuspended(a.id, true);
      await s.switchAccount(a.id);
      await expectLater(s.createPost(text: 'x'), throwsArgumentError);
    });

    test('ranking favours fresh engagement', () {
      final fresh = SocialService.rank(likes: 10, comments: 2, reposts: 0, saves: 0, views: 100, ageHours: 1);
      final old = SocialService.rank(likes: 10, comments: 2, reposts: 0, saves: 0, views: 100, ageHours: 48);
      expect(fresh, greaterThan(old));
    });
  });
}
