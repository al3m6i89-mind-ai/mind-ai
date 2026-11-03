/// Counters, times and #hashtag / @mention parsing shared by all three sections.
class SocialText {
  static final hashtag = RegExp(r'#([\p{L}\p{N}_]+)', unicode: true);
  static final mention = RegExp(r'@([A-Za-z0-9_](?:[A-Za-z0-9_.]*[A-Za-z0-9_])?)');

  /// Max length of a post in the Posts section.
  static const postLimit = 280;
  static const captionLimit = 2200;

  static Set<String> hashtags(String text) =>
      {for (final m in hashtag.allMatches(text)) m.group(1)!.toLowerCase()};

  static Set<String> mentions(String text) =>
      {for (final m in mention.allMatches(text)) m.group(1)!.toLowerCase()};

  /// 950 → 950, 1200 → 1.2 ألف, 15300 → 15.3 ألف, 2500000 → 2.5 مليون.
  static String count(int n) {
    if (n < 1000) return '$n';
    String trim(double v) {
      final s = v >= 100 ? '${v.floor()}' : v.toStringAsFixed(1);
      return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    }

    if (n < 1000000) {
      final v = (n / 100).floor() / 10;
      return '${trim(v)} ألف';
    }
    if (n < 1000000000) {
      final v = (n / 100000).floor() / 10;
      return '${trim(v)} مليون';
    }
    return '${trim((n / 100000000).floor() / 10)} مليار';
  }

  /// Short relative time: الآن، 5د، 3س، 2ي، then a date.
  static String ago(DateTime t, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(t);
    if (d.inSeconds < 60) return 'الآن';
    if (d.inMinutes < 60) return '${d.inMinutes}د';
    if (d.inHours < 24) return '${d.inHours}س';
    if (d.inDays < 7) return '${d.inDays}ي';
    final n = now ?? DateTime.now();
    return t.year == n.year ? '${t.day}/${t.month}' : '${t.day}/${t.month}/${t.year}';
  }

  /// Splits text into plain, #hashtag and @mention pieces for rich display.
  static List<TextPiece> pieces(String text) {
    final all = RegExp(r'#[\p{L}\p{N}_]+|@[A-Za-z0-9_](?:[A-Za-z0-9_.]*[A-Za-z0-9_])?', unicode: true);
    final out = <TextPiece>[];
    var at = 0;
    for (final m in all.allMatches(text)) {
      // An @ inside an e-mail address is not a mention.
      if (m.group(0)!.startsWith('@') && m.start > 0 && RegExp(r'[A-Za-z0-9]').hasMatch(text[m.start - 1])) {
        continue;
      }
      if (m.start > at) out.add(TextPiece(text.substring(at, m.start)));
      final s = m.group(0)!;
      out.add(TextPiece(s, tag: s.startsWith('#') ? s.substring(1) : null, mention: s.startsWith('@') ? s.substring(1) : null));
      at = m.end;
    }
    if (at < text.length) out.add(TextPiece(text.substring(at)));
    return out;
  }
}

class TextPiece {
  const TextPiece(this.text, {this.tag, this.mention});
  final String text;
  final String? tag;
  final String? mention;
}
