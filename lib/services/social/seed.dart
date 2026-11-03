import 'models.dart';
import 'social_id.dart';

/// Starter accounts and content so the three feeds are not empty on first
/// launch. Every count (likes, comments, followers) is real data between these
/// accounts; nothing is inflated.
class SocialSeed {
  SocialSeed(this.now);
  final DateTime now;

  final users = <SocialUser>[];
  final posts = <SocialPost>[];
  final comments = <Comment>[];
  final stories = <Story>[];
  var _n = 0;

  static const _gtv = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample';

  String _id(String p) => 'seed-$p-${_n++}';
  DateTime _ago(int minutes) => now.subtract(Duration(minutes: minutes));
  SocialUser _u(String handle) => users.firstWhere((u) => u.handle == handle);

  void build() {
    final taken = <String>{};
    SocialUser add(String handle, String name, String bio, int img, {bool verified = false}) {
      final id = SocialId.generate(taken: taken);
      taken.add(id);
      final u = SocialUser(
        id: id,
        handle: handle,
        name: name,
        bio: bio,
        avatar: 'https://i.pravatar.cc/300?img=$img',
        verified: verified,
        joined: _ago(60 * 24 * 300),
      );
      users.add(u);
      return u;
    }

    add('mindai', 'Mind Ai', 'الحساب الرسمي لمجتمع Mind Ai ✨ حساب واحد، ID واحد، لثلاث تجارب.', 68, verified: true);
    add('sara.travels', 'سارة | رحلات', 'أوثّق رحلاتي حول العالم ✈️🌍', 47, verified: true);
    add('chef_omar', 'الشيف عمر', 'وصفات سريعة كل يوم 🍳', 12);
    add('tech.yousef', 'يوسف التقني', 'مراجعات أجهزة وبرمجة 💻 | مطوّر Flutter', 15, verified: true);
    add('noura.art', 'نورة', 'رسامة رقمية 🎨 الطلبات بالخاص', 45);
    add('fahad.fit', 'فهد فتنس', 'تمارين وتغذية 💪', 33);
    add('lama.reads', 'لمى تقرأ', 'كتاب كل أسبوع 📚', 44);
    add('khalid.cam', 'خالد | تصوير', 'مصوّر طبيعة ومدن 📷', 59);

    // Follow graph.
    void follow(String a, String b) {
      _u(a).following.add(_u(b).id);
      _u(b).followers.add(_u(a).id);
    }

    for (final u in users.where((u) => u.handle != 'mindai')) {
      follow(u.handle, 'mindai');
    }
    follow('sara.travels', 'khalid.cam');
    follow('khalid.cam', 'sara.travels');
    follow('chef_omar', 'fahad.fit');
    follow('fahad.fit', 'chef_omar');
    follow('tech.yousef', 'noura.art');
    follow('noura.art', 'lama.reads');
    follow('lama.reads', 'noura.art');
    follow('lama.reads', 'tech.yousef');
    follow('mindai', 'tech.yousef');

    Set<String> by(List<String> handles) => {for (final h in handles) _u(h).id};

    // ---- Reels
    SocialPost reel(String handle, String video, String text, int ago, List<String> likers, {String sound = ''}) {
      final p = SocialPost(
        id: _id('reel'),
        kind: PostKind.reel,
        authorId: _u(handle).id,
        createdAt: _ago(ago),
        text: text,
        sound: sound,
        media: [Media('$_gtv/$video.mp4', video: true, thumb: '$_gtv/images/$video.jpg')],
        likes: by(likers),
        viewers: by(likers),
        views: likers.length,
      );
      posts.add(p);
      return p;
    }

    reel('sara.travels', 'ForBiggerEscapes', 'أجمل هروب من زحمة المدينة 🌄 #سفر #طبيعة', 95, [
      'khalid.cam',
      'lama.reads',
      'noura.art',
      'mindai',
    ], sound: 'Summer Vibes - Lofi');
    reel('khalid.cam', 'ForBiggerBlazes', 'لقطة اليوم 🔥 صوّرتها بإعدادات بسيطة #تصوير', 240, ['sara.travels', 'tech.yousef']);
    final r3 = reel('tech.yousef', 'ForBiggerJoyrides', 'جرّبت أسرع طريقة لنقل الشاشة للتلفاز 📺 #تقنية', 400, [
      'noura.art',
      'lama.reads',
      'mindai',
      'fahad.fit',
    ]);
    reel('fahad.fit', 'ForBiggerFun', 'روتين الصباح في 30 ثانية 💪 #رياضة', 720, ['chef_omar']);
    reel('chef_omar', 'ForBiggerMeltdowns', 'لما الطبخة تفشل 😂 #طبخ', 1500, ['fahad.fit', 'sara.travels', 'lama.reads']);
    reel('mindai', 'ForBiggerBlazes', 'مرحباً بك في مجتمع Mind Ai 🎉 صوّر، شارك، واكتب… بحساب واحد. #MindAi', 3000, [
      'sara.travels',
      'tech.yousef',
      'khalid.cam',
    ]);

    // ---- Photos
    SocialPost photo(String handle, List<String> seeds, String text, int ago, List<String> likers, {String location = ''}) {
      final p = SocialPost(
        id: _id('photo'),
        kind: PostKind.photo,
        authorId: _u(handle).id,
        createdAt: _ago(ago),
        text: text,
        location: location,
        media: [for (final s in seeds) Media('https://picsum.photos/seed/$s/1080/1080')],
        likes: by(likers),
      );
      posts.add(p);
      return p;
    }

    final p1 = photo('sara.travels', ['alps1', 'alps2', 'alps3'], 'ثلاث صور من جبال الألب 🏔️ أيها أجمل؟ #سفر', 60, [
      'khalid.cam',
      'noura.art',
      'lama.reads',
      'fahad.fit',
      'mindai',
    ], location: 'سويسرا');
    photo('khalid.cam', ['city9'], 'المدينة بعد المطر 🌧️ #تصوير', 300, ['sara.travels', 'tech.yousef'], location: 'الرياض');
    photo('chef_omar', ['food7', 'food8'], 'فطور اليوم 🥞 الوصفة في التعليقات #طبخ', 500, ['fahad.fit', 'lama.reads']);
    photo('noura.art', ['art42'], 'لوحة جديدة 🎨 استغرقت 12 ساعة #فن', 900, ['lama.reads', 'tech.yousef', 'mindai']);
    photo('lama.reads', ['books3'], 'قائمة قراءات هذا الشهر 📚 #كتب', 1400, ['noura.art']);

    // ---- Posts (text)
    SocialPost post(String handle, String text, int ago, List<String> likers, {String? replyTo, String? quoteOf}) {
      final p = SocialPost(
        id: _id('post'),
        kind: PostKind.post,
        authorId: _u(handle).id,
        createdAt: _ago(ago),
        text: text,
        replyTo: replyTo,
        quoteOf: quoteOf,
        likes: by(likers),
        viewers: by(likers),
        views: likers.length,
      );
      posts.add(p);
      return p;
    }

    final t1 = post(
      'mindai',
      'أهلاً بكم في Mind Ai 👋\nحساب واحد بـ ID واحد يجمع: 🎬 الريلز، 📸 الصور، 💬 المنشورات.\nابحث عن أي شخص بالـ ID أو @المعرّف. #MindAi',
      2900,
      ['sara.travels', 'tech.yousef', 'noura.art', 'khalid.cam', 'lama.reads'],
    );
    final t2 = post('tech.yousef', 'رأي غير شعبي: أفضل لغة للمبتدئين هي Dart 🎯 #برمجة #Flutter', 180, [
      'noura.art',
      'lama.reads',
    ]);
    post('lama.reads', 'أتفق! بدأت فيها وكانت سهلة جداً', 150, ['tech.yousef'], replyTo: t2.id);
    post('noura.art', 'وش رأيكم في هذا؟ 👇', 120, ['lama.reads'], quoteOf: t2.id);
    post('sara.travels', 'نصيحة سفر: احجز قبل شهرين على الأقل وستوفر 40% ✈️ #سفر', 420, ['khalid.cam', 'fahad.fit', 'mindai']);
    post('fahad.fit', 'الاستمرارية أهم من الشدّة. 20 دقيقة يومياً تكفي 💪 #رياضة', 800, ['chef_omar', 'sara.travels']);
    post('tech.yousef', '@mindai متى نقدر نثبّت المنشور في أعلى الملف الشخصي؟ 😄', 2500, ['mindai'], replyTo: t1.id);

    // ---- Comments
    void comment(SocialPost p, String handle, String text, int ago, {String? parent, List<String> likers = const []}) {
      comments.add(
        Comment(
          id: _id('c'),
          postId: p.id,
          authorId: _u(handle).id,
          text: text,
          createdAt: _ago(ago),
          parentId: parent,
          likes: by(likers),
        ),
      );
    }

    comment(p1, 'khalid.cam', 'الثانية بدون نقاش 😍', 50, likers: ['sara.travels', 'noura.art']);
    comment(p1, 'sara.travels', 'وأنا أحبها أكثر شيء', 45, parent: comments.last.id);
    comment(p1, 'lama.reads', 'خذيني معك المرة الجاية 🥹', 40);
    comment(r3, 'noura.art', 'مفيد جداً شكراً!', 380, likers: ['tech.yousef']);

    // ---- Stories
    void story(String handle, String seed, String caption, int ago) {
      stories.add(
        Story(
          id: _id('story'),
          authorId: _u(handle).id,
          media: Media('https://picsum.photos/seed/$seed/1080/1920'),
          caption: caption,
          createdAt: _ago(ago),
        ),
      );
    }

    story('sara.travels', 'st1', 'صباح الخير من الجبال ☀️', 30);
    story('sara.travels', 'st2', '', 25);
    story('khalid.cam', 'st3', 'خلف الكواليس 📷', 200);
    story('chef_omar', 'st4', 'جاهز للطبخ؟', 400);
    story('noura.art', 'st5', 'شغل اليوم ✍️', 600);
    story('mindai', 'st6', 'ميزة جديدة: القصص 🎉', 900);
  }
}
