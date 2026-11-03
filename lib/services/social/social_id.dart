import 'dart:math';

/// The one ID that identifies a person across Reels, Photos and Posts.
///
/// Format: `MA-XXXX-XXXX-C`
/// * 8 random characters from Crockford's base-32 alphabet (no I, L, O, U, so
///   it can't be misread), about 1.1 trillion combinations.
/// * 1 check character (Luhn mod 32) that catches any single mistyped
///   character and nearly every swap of two neighbours, so a wrong ID is
///   rejected before any lookup.
class SocialId {
  static const prefix = 'MA';
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const _bodyLength = 8;

  static final _rand = Random.secure();

  /// A fresh, valid ID that is not in [taken].
  static String generate({Set<String> taken = const {}}) {
    while (true) {
      final body = List.generate(_bodyLength, (_) => alphabet[_rand.nextInt(alphabet.length)]).join();
      final id = _format(body + _check(body));
      if (!taken.contains(id)) return id;
    }
  }

  /// Turns what a person typed (`ma 7k3p 9qxd 4`, `MA7K3P9QXD4`, with O for 0,
  /// I or L for 1) into the canonical form, or null when it isn't a valid ID.
  static String? normalize(String input) {
    var s = input.toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');
    if (s.startsWith(prefix)) s = s.substring(prefix.length);
    s = s.replaceAll('O', '0').replaceAll('I', '1').replaceAll('L', '1');
    if (s.length != _bodyLength + 1) return null;
    if (s.split('').any((c) => !alphabet.contains(c))) return null;
    final body = s.substring(0, _bodyLength);
    if (_check(body) != s[_bodyLength]) return null;
    return _format(s);
  }

  static bool isValid(String input) => normalize(input) != null;

  /// True when the text looks like an attempt at an ID (used by search).
  static bool looksLikeId(String input) =>
      RegExp(r'^\s*MA[\s\-]?[0-9A-Z]{4}', caseSensitive: false).hasMatch(input);

  static String _format(String s) => '$prefix-${s.substring(0, 4)}-${s.substring(4, 8)}-${s.substring(8)}';

  /// Luhn mod N over the base-32 alphabet.
  static String _check(String body) {
    const n = 32;
    var factor = 2;
    var sum = 0;
    for (var i = body.length - 1; i >= 0; i--) {
      var addend = factor * alphabet.indexOf(body[i]);
      factor = factor == 2 ? 1 : 2;
      addend = addend ~/ n + addend % n;
      sum += addend;
    }
    return alphabet[(n - sum % n) % n];
  }
}

/// Rules for the @handle, which is also shared by all three sections.
class Handle {
  static final _valid = RegExp(r'^[a-z0-9_](?:[a-z0-9_.]{1,18}[a-z0-9_])?$');

  /// Null when fine, otherwise the reason in Arabic.
  static String? problem(String handle) {
    final h = handle.trim().toLowerCase();
    if (h.length < 3) return 'المعرّف 3 أحرف على الأقل';
    if (h.length > 20) return 'المعرّف 20 حرفاً كحد أقصى';
    if (!_valid.hasMatch(h)) return 'استخدم حروفاً إنجليزية وأرقاماً و _ و . فقط (بدون نقطة في البداية أو النهاية)';
    if (h.contains('..')) return 'لا تكرر النقطة';
    return null;
  }

  /// A usable handle suggestion from an e-mail or a name.
  static String suggest(String from) {
    var s = from.split('@').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.]'), '');
    s = s.replaceAll(RegExp(r'\.{2,}'), '.').replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (s.length > 20) s = s.substring(0, 20);
    if (s.length < 3) s = 'user${Random().nextInt(90000) + 10000}';
    return s;
  }
}
