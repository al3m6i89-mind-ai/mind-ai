import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Pulls readable text out of documents on the phone, keeping where each part
/// came from (slide number, sheet and cell) so answers can cite it.
class ExtractResult {
  ExtractResult(this.text, {this.note});
  final String? text;
  final String? note;
}

const supportedExtensions = {
  'pdf', 'docx', 'pptx', 'xlsx', 'txt', 'csv', 'md', 'markdown', 'jpg', 'jpeg', 'png', 'webp', //
};
const legacyOffice = {'doc', 'ppt', 'xls'};
const maxTextChars = 400000;

String extensionOf(String name) => name.contains('.') ? name.split('.').last.toLowerCase() : '';

/// Checks the bytes really are the claimed type. Returns an error key or null.
String? validateBytes(String ext, Uint8List b) {
  if (b.isEmpty) return 'emptyFile';
  bool starts(List<int> sig) => b.length >= sig.length && List.generate(sig.length, (i) => b[i] == sig[i]).every((x) => x);
  final ok = switch (ext) {
    'pdf' => starts(utf8.encode('%PDF')) || utf8.decode(b.take(1024).toList(), allowMalformed: true).contains('%PDF'),
    'docx' || 'pptx' || 'xlsx' => starts([0x50, 0x4B, 0x03, 0x04]),
    'jpg' || 'jpeg' => starts([0xFF, 0xD8, 0xFF]),
    'png' => starts([0x89, 0x50, 0x4E, 0x47]),
    'webp' => b.length > 12 && starts(utf8.encode('RIFF')) && utf8.decode(b.sublist(8, 12), allowMalformed: true) == 'WEBP',
    'txt' || 'csv' || 'md' || 'markdown' => !b.take(8192).contains(0),
    _ => false,
  };
  return ok ? null : 'contentMismatch';
}

ExtractResult extractText(String ext, Uint8List bytes) {
  try {
    final text = switch (ext) {
      'txt' || 'csv' || 'md' || 'markdown' => _decodeText(bytes),
      'docx' => _docx(bytes),
      'pptx' => _pptx(bytes),
      'xlsx' => _xlsx(bytes),
      _ => null,
    };
    if (text == null) return ExtractResult(null);
    if (text.trim().isEmpty) return ExtractResult(null, note: 'noText');
    if (text.length > maxTextChars) {
      return ExtractResult(text.substring(0, maxTextChars), note: 'truncated');
    }
    return ExtractResult(text);
  } catch (_) {
    return ExtractResult(null, note: 'extractFailed');
  }
}

String _decodeText(Uint8List b) {
  try {
    return utf8.decode(b);
  } catch (_) {
    return latin1.decode(b);
  }
}

Archive _zip(Uint8List b) => ZipDecoder().decodeBytes(b);

String? _file(Archive a, String name) {
  final f = a.findFile(name);
  if (f == null) return null;
  return utf8.decode(f.content as List<int>, allowMalformed: true);
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(2)!, radix: m.group(1)!.isEmpty ? 10 : 16);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    })
    .replaceAll('&amp;', '&');

String _docx(Uint8List bytes) {
  final xml = _file(_zip(bytes), 'word/document.xml') ?? (throw const FormatException('no word/document.xml'));
  final out = StringBuffer();
  final para = RegExp(r'<w:p[ >].*?</w:p>', dotAll: true);
  // <w:tab/> must not be read as the start of a <w:t> run.
  final run = RegExp(r'<w:t(?:\s[^>]*)?>(.*?)</w:t>', dotAll: true);
  final style = RegExp(r'<w:pStyle w:val="([^"]+)"');
  for (final p in para.allMatches(xml)) {
    final body = p.group(0)!;
    final text = run.allMatches(body).map((m) => _unescape(m.group(1)!)).join();
    if (text.trim().isEmpty) continue;
    final st = style.firstMatch(body)?.group(1)?.toLowerCase() ?? '';
    final isHeading = st.startsWith('heading') || st.startsWith('title') || st.contains('عنوان');
    out.writeln(isHeading ? '\n## $text' : text);
  }
  return out.toString();
}

String _pptx(Uint8List bytes) {
  final a = _zip(bytes);
  final slide = RegExp(r'^ppt/slides/slide(\d+)\.xml$');
  final nums = <int>[];
  for (final f in a.files) {
    final m = slide.firstMatch(f.name);
    if (m != null) nums.add(int.parse(m.group(1)!));
  }
  if (nums.isEmpty && a.findFile('ppt/presentation.xml') == null) throw const FormatException('not a pptx');
  nums.sort();
  final run = RegExp(r'<a:t>(.*?)</a:t>', dotAll: true);
  final para = RegExp(r'<a:p>.*?</a:p>', dotAll: true);
  final out = StringBuffer();
  for (final n in nums) {
    final xml = _file(a, 'ppt/slides/slide$n.xml') ?? '';
    out.writeln('\n[الشريحة $n / Slide $n]');
    for (final p in para.allMatches(xml)) {
      final t = run.allMatches(p.group(0)!).map((m) => _unescape(m.group(1)!)).join();
      if (t.trim().isNotEmpty) out.writeln(t);
    }
    final notes = _file(a, 'ppt/notesSlides/notesSlide$n.xml');
    if (notes != null) {
      final t = run.allMatches(notes).map((m) => _unescape(m.group(1)!)).join(' ').trim();
      if (t.isNotEmpty && t != '$n') out.writeln('(ملاحظات المتحدث: $t)');
    }
  }
  return out.toString();
}

String _xlsx(Uint8List bytes) {
  final a = _zip(bytes);
  final shared = <String>[];
  final sst = _file(a, 'xl/sharedStrings.xml');
  if (sst != null) {
    for (final si in RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(sst)) {
      shared.add(RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(si.group(1)!).map((m) => _unescape(m.group(1)!)).join());
    }
  }
  // Sheet names in workbook order, mapped to their files through the relationships.
  final wb = _file(a, 'xl/workbook.xml') ?? (throw const FormatException('no xl/workbook.xml'));
  final rels = _file(a, 'xl/_rels/workbook.xml.rels') ?? '';
  final relTarget = <String, String>{};
  for (final m in RegExp(r'<Relationship [^>]*?Id="([^"]+)"[^>]*?Target="([^"]+)"').allMatches(rels)) {
    relTarget[m.group(1)!] = m.group(2)!;
  }
  for (final m in RegExp(r'<Relationship [^>]*?Target="([^"]+)"[^>]*?Id="([^"]+)"').allMatches(rels)) {
    relTarget[m.group(2)!] = m.group(1)!;
  }
  final out = StringBuffer();
  final sheets = RegExp(r'<sheet [^>]*?name="([^"]+)"[^>]*?r:id="([^"]+)"').allMatches(wb).toList();
  var index = 0;
  for (final s in sheets) {
    index++;
    final name = _unescape(s.group(1)!);
    var target = relTarget[s.group(2)!] ?? 'worksheets/sheet$index.xml';
    target = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    final xml = _file(a, target);
    if (xml == null) continue;
    out.writeln('\n[ورقة العمل: $name / Sheet: $name]');
    for (final row in RegExp(r'<row [^>]*>(.*?)</row>', dotAll: true).allMatches(xml)) {
      final cells = <String>[];
      for (final c in RegExp(r'<c ([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true).allMatches(row.group(1)!)) {
        final attrs = c.group(1)!;
        final inner = c.group(2) ?? '';
        final ref = RegExp(r'r="([A-Z]+\d+)"').firstMatch(attrs)?.group(1) ?? '';
        final type = RegExp(r't="([^"]+)"').firstMatch(attrs)?.group(1);
        final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(inner)?.group(1);
        final f = RegExp(r'<f[^>]*>(.*?)</f>', dotAll: true).firstMatch(inner)?.group(1);
        String? value;
        if (type == 's' && v != null) {
          final i = int.tryParse(v);
          value = i != null && i < shared.length ? shared[i] : v;
        } else if (type == 'inlineStr') {
          value = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(inner).map((m) => _unescape(m.group(1)!)).join();
        } else if (v != null) {
          value = _unescape(v);
        }
        if (value == null || value.isEmpty) {
          // A formula saved without its result (common from scripts) is still worth citing.
          if (f != null) cells.add('$ref (=${_unescape(f)})');
          continue;
        }
        cells.add(f != null ? '$ref=$value (=${_unescape(f)})' : '$ref=$value');
      }
      if (cells.isNotEmpty) out.writeln(cells.join(' | '));
    }
  }
  return out.toString();
}
