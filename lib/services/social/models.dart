/// Data for the social space. One [SocialUser] (one ID) owns content in all
/// three sections; every piece of content is a [SocialPost] with a [PostKind].
library;

enum PostKind { reel, photo, post }

extension PostKindInfo on PostKind {
  String get label => switch (this) {
    PostKind.reel => 'ريلز',
    PostKind.photo => 'صور',
    PostKind.post => 'منشورات',
  };

  String get single => switch (this) {
    PostKind.reel => 'ريل',
    PostKind.photo => 'صورة',
    PostKind.post => 'منشور',
  };

  String get emoji => switch (this) {
    PostKind.reel => '🎬',
    PostKind.photo => '📸',
    PostKind.post => '💬',
  };
}

Set<String> _set(Object? v) => {...?(v as List?)?.cast<String>()};

class SocialUser {
  SocialUser({
    required this.id,
    required this.handle,
    required this.name,
    this.bio = '',
    this.avatar = '',
    this.link = '',
    this.verified = false,
    this.private = false,
    this.local = false,
    Set<String>? following,
    Set<String>? followers,
    Set<String>? blocked,
    DateTime? joined,
  }) : following = following ?? {},
       followers = followers ?? {},
       blocked = blocked ?? {},
       joined = joined ?? DateTime.now();

  /// The unified ID (see SocialId).
  final String id;
  String handle;
  String name;
  String bio;

  /// URL or local file path; empty shows initials.
  String avatar;
  String link;
  bool verified;
  bool private;

  /// Created on this phone (can be switched to).
  final bool local;
  final Set<String> following;
  final Set<String> followers;
  final Set<String> blocked;
  final DateTime joined;

  Map<String, dynamic> toJson() => {
    'id': id,
    'handle': handle,
    'name': name,
    'bio': bio,
    'avatar': avatar,
    'link': link,
    'verified': verified,
    'private': private,
    'local': local,
    'following': following.toList(),
    'followers': followers.toList(),
    'blocked': blocked.toList(),
    'joined': joined.toUtc().toIso8601String(),
  };

  factory SocialUser.fromJson(Map<String, dynamic> j) => SocialUser(
    id: j['id'] as String,
    handle: j['handle'] as String,
    name: j['name'] as String,
    bio: j['bio'] as String? ?? '',
    avatar: j['avatar'] as String? ?? '',
    link: j['link'] as String? ?? '',
    verified: j['verified'] as bool? ?? false,
    private: j['private'] as bool? ?? false,
    local: j['local'] as bool? ?? false,
    following: _set(j['following']),
    followers: _set(j['followers']),
    blocked: _set(j['blocked']),
    joined: DateTime.tryParse(j['joined'] as String? ?? '')?.toLocal(),
  );
}

class Media {
  const Media(this.src, {this.video = false, this.thumb = ''});

  /// URL or local file path.
  final String src;
  final bool video;

  /// Poster image for videos (URL or path); may be empty.
  final String thumb;

  Map<String, dynamic> toJson() => {'src': src, 'video': video, 'thumb': thumb};
  factory Media.fromJson(Map<String, dynamic> j) =>
      Media(j['src'] as String, video: j['video'] as bool? ?? false, thumb: j['thumb'] as String? ?? '');
}

class SocialPost {
  SocialPost({
    required this.id,
    required this.kind,
    required this.authorId,
    required this.createdAt,
    this.text = '',
    this.media = const [],
    this.location = '',
    this.sound = '',
    this.replyTo,
    this.quoteOf,
    this.repostOf,
    this.commentsOff = false,
    this.views = 0,
    this.shares = 0,
    Set<String>? likes,
    Set<String>? saves,
    Set<String>? viewers,
  }) : likes = likes ?? {},
       saves = saves ?? {},
       viewers = viewers ?? {};

  final String id;
  final PostKind kind;
  final String authorId;
  final DateTime createdAt;
  String text;
  final List<Media> media;
  final String location;

  /// Reels: name of the sound ("original sound - @handle" when empty).
  final String sound;

  /// Posts section: the post this one answers.
  final String? replyTo;

  /// Posts section: the post quoted inside this one.
  final String? quoteOf;

  /// A plain repost (no text) of another post. Shown as that post.
  final String? repostOf;
  bool commentsOff;
  int views;
  int shares;
  final Set<String> likes;
  final Set<String> saves;

  /// Who has seen it, so views count each person once.
  final Set<String> viewers;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'authorId': authorId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'text': text,
    'media': media.map((m) => m.toJson()).toList(),
    'location': location,
    'sound': sound,
    'replyTo': replyTo,
    'quoteOf': quoteOf,
    'repostOf': repostOf,
    'commentsOff': commentsOff,
    'views': views,
    'shares': shares,
    'likes': likes.toList(),
    'saves': saves.toList(),
    'viewers': viewers.toList(),
  };

  factory SocialPost.fromJson(Map<String, dynamic> j) => SocialPost(
    id: j['id'] as String,
    kind: PostKind.values.byName(j['kind'] as String),
    authorId: j['authorId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    text: j['text'] as String? ?? '',
    media: [...?(j['media'] as List?)?.map((e) => Media.fromJson(e as Map<String, dynamic>))],
    location: j['location'] as String? ?? '',
    sound: j['sound'] as String? ?? '',
    replyTo: j['replyTo'] as String?,
    quoteOf: j['quoteOf'] as String?,
    repostOf: j['repostOf'] as String?,
    commentsOff: j['commentsOff'] as bool? ?? false,
    views: j['views'] as int? ?? 0,
    shares: j['shares'] as int? ?? 0,
    likes: _set(j['likes']),
    saves: _set(j['saves']),
    viewers: _set(j['viewers']),
  );
}

/// Comment on a reel or a photo (posts answer each other with replies instead).
class Comment {
  Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.text,
    required this.createdAt,
    this.parentId,
    Set<String>? likes,
  }) : likes = likes ?? {};

  final String id;
  final String postId;
  final String authorId;
  final String text;
  final DateTime createdAt;

  /// Set when this is an answer to another comment.
  final String? parentId;
  final Set<String> likes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'postId': postId,
    'authorId': authorId,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'parentId': parentId,
    'likes': likes.toList(),
  };

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
    id: j['id'] as String,
    postId: j['postId'] as String,
    authorId: j['authorId'] as String,
    text: j['text'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    parentId: j['parentId'] as String?,
    likes: _set(j['likes']),
  );
}

class Story {
  Story({
    required this.id,
    required this.authorId,
    required this.media,
    required this.createdAt,
    this.caption = '',
    Set<String>? seenBy,
    Set<String>? likes,
  }) : seenBy = seenBy ?? {},
       likes = likes ?? {};

  static const life = Duration(hours: 24);

  final String id;
  final String authorId;
  final Media media;
  final String caption;
  final DateTime createdAt;
  final Set<String> seenBy;
  final Set<String> likes;

  bool isLive(DateTime now) => now.difference(createdAt) < life;

  Map<String, dynamic> toJson() => {
    'id': id,
    'authorId': authorId,
    'media': media.toJson(),
    'caption': caption,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'seenBy': seenBy.toList(),
    'likes': likes.toList(),
  };

  factory Story.fromJson(Map<String, dynamic> j) => Story(
    id: j['id'] as String,
    authorId: j['authorId'] as String,
    media: Media.fromJson(j['media'] as Map<String, dynamic>),
    caption: j['caption'] as String? ?? '',
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    seenBy: _set(j['seenBy']),
    likes: _set(j['likes']),
  );
}

enum NoticeType { like, comment, reply, follow, repost, quote, mention, save, storyLike, message }

class Notice {
  Notice({
    required this.id,
    required this.type,
    required this.toId,
    required this.fromId,
    required this.createdAt,
    this.postId,
    this.text = '',
    this.read = false,
  });

  final String id;
  final NoticeType type;
  final String toId;
  final String fromId;
  final String? postId;
  final String text;
  final DateTime createdAt;
  bool read;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'toId': toId,
    'fromId': fromId,
    'postId': postId,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'read': read,
  };

  factory Notice.fromJson(Map<String, dynamic> j) => Notice(
    id: j['id'] as String,
    type: NoticeType.values.byName(j['type'] as String),
    toId: j['toId'] as String,
    fromId: j['fromId'] as String,
    postId: j['postId'] as String?,
    text: j['text'] as String? ?? '',
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    read: j['read'] as bool? ?? false,
  );
}

class Message {
  Message({required this.id, required this.fromId, required this.createdAt, this.text = '', this.postId});

  final String id;
  final String fromId;
  final String text;

  /// A post shared into the chat.
  final String? postId;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'fromId': fromId,
    'text': text,
    'postId': postId,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory Message.fromJson(Map<String, dynamic> j) => Message(
    id: j['id'] as String,
    fromId: j['fromId'] as String,
    text: j['text'] as String? ?? '',
    postId: j['postId'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
  );
}

/// A one-to-one chat. [key] is both IDs sorted and joined, so the same two
/// people always share one thread.
class Chat {
  Chat({required this.members, List<Message>? messages, Map<String, DateTime>? readAt})
    : messages = messages ?? [],
      readAt = readAt ?? {};

  final List<String> members;
  final List<Message> messages;
  final Map<String, DateTime> readAt;

  static String keyFor(String a, String b) => ([a, b]..sort()).join('|');
  String get key => keyFor(members[0], members[1]);
  String other(String me) => members.firstWhere((m) => m != me, orElse: () => me);

  int unread(String me) {
    final seen = readAt[me];
    return messages.where((m) => m.fromId != me && (seen == null || m.createdAt.isAfter(seen))).length;
  }

  Map<String, dynamic> toJson() => {
    'members': members,
    'messages': messages.map((m) => m.toJson()).toList(),
    'readAt': readAt.map((k, v) => MapEntry(k, v.toUtc().toIso8601String())),
  };

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
    members: (j['members'] as List).cast<String>(),
    messages: [...?(j['messages'] as List?)?.map((e) => Message.fromJson(e as Map<String, dynamic>))],
    readAt: {
      ...?(j['readAt'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, DateTime.parse(v as String).toLocal())),
    },
  );
}
