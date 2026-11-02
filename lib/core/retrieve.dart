import 'dart:math' as math;

import 'models.dart';

/// Picks the parts of a big document that matter for a question, so a
/// thousand-page book is answered from its relevant pages in seconds instead
/// of sending the whole text (slow, and too big for most servers).
///
/// Scoring is BM25 over Arabic-folded words with light prefix and suffix
/// stripping, plus a bonus for words that appear next to each other as in the
/// question. Pages the user names ("صفحة 120", "page 12") are always included.
class Passage {
  Passage(this.index, this.text, this.page);
  final int index;
  final String text;

  /// The PDF page this passage is, when known.
  final int? page;
}

class Retrieved {
  Retrieved(this.text, this.shown, this.total, {required this.whole});
  final String text;
  final int shown;
  final int total;

  /// True when the document was small enough to send in full.
  final bool whole;
}

final _pageMark = RegExp(r'\[الصفحة (\d+) / Page \d+\]');
final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final _askedPage = RegExp(r'(?<![\p{L}])(?:الصفحه|الصفحة|صفحه|صفحة|صفحات|ص\.?|pages?|p\.)\s*(\d{1,5})', caseSensitive: false, unicode: true);

const _stop = {
  // Arabic question and filler words (already folded).
  'ما', 'ماذا', 'من', 'في', 'علي', 'الي', 'عن', 'هل', 'كم', 'كيف', 'متي', 'اين', 'لماذا', 'هو', 'هي', 'هذا', 'هذه',
  'ذلك', 'تلك', 'التي', 'الذي', 'الذين', 'او', 'ثم', 'مع', 'كل', 'بعض', 'اي', 'لا', 'لم', 'لن', 'قد', 'كان', 'كانت',
  'يكون', 'تكون', 'انه', 'انها', 'ان', 'اذا', 'به', 'بها', 'له', 'لها', 'فيه', 'فيها', 'منه', 'منها', 'عند', 'بين',
  'اريد', 'ابي', 'ابغي', 'وش', 'ايش', 'شو', 'اعطني', 'اذكر', 'اشرح', 'وضح', 'لي', 'الملف', 'الكتاب', 'المستند',
  'يا', 'و', 'ف', 'ب', 'ل', 'ك',
  // English.
  'the', 'a', 'an', 'of', 'in', 'on', 'to', 'is', 'are', 'was', 'were', 'what', 'which', 'who', 'how', 'when', 'where',
  'why', 'does', 'do', 'did', 'and', 'or', 'for', 'with', 'about', 'from', 'this', 'that', 'it', 'be', 'by', 'as',
  'me', 'tell', 'please', 'file', 'document', 'book', 'can', 'you',
};

String _digits(String s) => s.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (m) {
      final c = m[0]!.codeUnitAt(0);
      return '${c >= 0x06F0 ? c - 0x06F0 : c - 0x0660}';
    });

/// The search form of one word: folded, without common Arabic prefixes and
/// suffixes or an English plural "s".
String stem(String w) {
  var s = w;
  if (RegExp('[؀-ۿ]').hasMatch(s)) {
    for (final p in const ['وال', 'بال', 'كال', 'فال', 'لل', 'ال']) {
      if (s.startsWith(p) && s.length - p.length >= 2) {
        s = s.substring(p.length);
        break;
      }
    }
    for (final x in const ['ات', 'ون', 'ين', 'ها', 'هم', 'كم', 'نا', 'يه', 'ه', 'ي']) {
      if (s.endsWith(x) && s.length - x.length >= 3) {
        s = s.substring(0, s.length - x.length);
        break;
      }
    }
  } else if (s.length > 3 && s.endsWith('s') && !s.endsWith('ss')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

List<String> words(String text) => [
      for (final m in _word.allMatches(Conversation.fold(_digits(text)))) stem(m[0]!),
    ];

List<String> _queryWords(String q) => [
      for (final m in _word.allMatches(Conversation.fold(_digits(q))))
        if (!_stop.contains(m[0]!) && (m[0]!.length > 1 || RegExp(r'\d').hasMatch(m[0]!))) stem(m[0]!),
    ];

/// Splits a document into passages: PDF pages where the text is marked by
/// page, otherwise pieces of about [size] characters cut at line ends.
List<Passage> passages(String text, {int size = 3000}) {
  final out = <Passage>[];
  final marks = _pageMark.allMatches(text).toList();
  if (marks.isNotEmpty) {
    final head = text.substring(0, marks.first.start).trim();
    if (head.isNotEmpty) out.add(Passage(0, head, null));
    for (var i = 0; i < marks.length; i++) {
      final end = i + 1 < marks.length ? marks[i + 1].start : text.length;
      out.add(Passage(out.length, text.substring(marks[i].start, end).trim(), int.parse(marks[i][1]!)));
    }
    return out;
  }
  final buf = StringBuffer();
  for (final line in text.split('\n')) {
    if (buf.length + line.length > size && buf.isNotEmpty) {
      out.add(Passage(out.length, buf.toString().trim(), null));
      buf.clear();
    }
    // A single huge line (minified text) is cut where it must be.
    var rest = line;
    while (rest.length > size) {
      out.add(Passage(out.length, rest.substring(0, size), null));
      rest = rest.substring(size);
    }
    buf.writeln(rest);
  }
  if (buf.toString().trim().isNotEmpty) out.add(Passage(out.length, buf.toString().trim(), null));
  return out;
}

/// The parts of [text] that best answer [question] within [budget] characters.
/// [context] is the previous question, for follow-ups such as "explain more".
Retrieved relevant(String text, String question, {String context = '', int budget = 48000}) {
  final all = passages(text);
  if (text.length <= budget) return Retrieved(text, all.length, all.length, whole: true);

  final asked = {
    for (final m in _askedPage.allMatches(Conversation.fold(_digits('$question $context')))) int.parse(m[1]!),
  };
  final query = <String, double>{};
  for (final w in _queryWords(context)) {
    query[w] = 0.5;
  }
  for (final w in _queryWords(question)) {
    query[w] = 1;
  }
  final qList = _queryWords(question);

  // BM25.
  final docs = [for (final p in all) words(p.text)];
  final avg = docs.fold<int>(0, (n, d) => n + d.length) / math.max(1, docs.length);
  final df = <String, int>{};
  final tfs = <Map<String, int>>[];
  for (final d in docs) {
    final tf = <String, int>{};
    for (final w in d) {
      if (query.containsKey(w)) tf[w] = (tf[w] ?? 0) + 1;
    }
    for (final w in tf.keys) {
      df[w] = (df[w] ?? 0) + 1;
    }
    tfs.add(tf);
  }
  final n = all.length;
  final scores = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    var s = 0.0;
    final len = docs[i].length;
    tfs[i].forEach((w, f) {
      final idf = math.log(1 + (n - df[w]! + 0.5) / (df[w]! + 0.5));
      s += query[w]! * idf * (f * 2.2) / (f + 1.2 * (0.25 + 0.75 * len / math.max(1, avg)));
    });
    // Words that sit together as in the question ("مدة العقد") count extra.
    if (qList.length > 1 && s > 0) {
      final joined = ' ${docs[i].join(' ')} ';
      for (var k = 0; k + 1 < qList.length; k++) {
        if (joined.contains(' ${qList[k]} ${qList[k + 1]} ')) s += 1.5;
      }
    }
    scores[i] = s;
  }

  final chosen = <int>{};
  var used = 0;
  bool take(int i) {
    if (i < 0 || i >= n || chosen.contains(i)) return false;
    final cost = all[i].text.length + 2;
    if (used + cost > budget && chosen.isNotEmpty) return false;
    chosen.add(i);
    used += cost;
    return true;
  }

  for (var i = 0; i < n; i++) {
    if (all[i].page != null && asked.contains(all[i].page)) take(i);
  }
  final ranked = [for (var i = 0; i < n; i++) if (scores[i] > 0) i]..sort((a, b) => scores[b].compareTo(scores[a]));
  if (ranked.isEmpty && chosen.isEmpty) {
    // Nothing matched (a summary question): an even spread across the document.
    final per = math.max(1, (used + text.length) ~/ math.max(1, budget));
    for (var i = 0; i < n; i += per) {
      take(i);
    }
  } else {
    for (final (k, i) in ranked.indexed) {
      if (used >= budget) break;
      take(i);
      // An answer often runs on to the next page.
      if (k < 3) take(i + 1);
    }
  }

  final order = chosen.toList()..sort();
  final out = StringBuffer();
  int? last;
  for (final i in order) {
    if (last != null && i != last + 1) out.writeln('\n[…]');
    out.writeln(all[i].text);
    last = i;
  }
  return Retrieved(out.toString(), order.length, n, whole: false);
}
