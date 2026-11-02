import 'dart:io';
import 'dart:typed_data';

import 'package:file_chat/core/extract.dart';
import 'package:file_chat/core/models.dart';
import 'package:file_chat/core/retrieve.dart';
import 'package:file_chat/core/store.dart';
import 'package:file_chat/core/strings.dart';
import 'package:file_chat/ui/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// A book of [pages] pages; page 137 holds the contract term.
String book(int pages) {
  final b = StringBuffer();
  for (var i = 1; i <= pages; i++) {
    b.writeln('\n${pageMark(i)}');
    if (i == 137) {
      b.writeln('البند السابع: مدة العقد ثلاث سنوات تبدأ من تاريخ التوقيع وتجدد تلقائيًا.');
    } else {
      b.writeln('فصل $i عن الزراعة والري والتربة والمحاصيل الموسمية في المناطق الجافة. ' * 12);
    }
  }
  return b.toString();
}

Future<Uint8List> pdf(int pages) async {
  final doc = PdfDocument();
  for (var i = 1; i <= pages; i++) {
    doc.pages.add().graphics.drawString(i == 7 ? 'Warranty period is 24 months' : 'Chapter $i about soil and water',
        PdfStandardFont(PdfFontFamily.helvetica, 12));
  }
  final bytes = Uint8List.fromList(await doc.save());
  doc.dispose();
  return bytes;
}

void main() {
  group('relevant pages of a big book', () {
    final text = book(400);

    test('the page that answers is found, without the whole book', () {
      final r = relevant(text, 'كم مدة العقد؟');
      expect(r.whole, isFalse);
      expect(r.text, contains('مدة العقد ثلاث سنوات'));
      expect(r.text, contains('[الصفحة 137 / Page 137]'));
      expect(r.text.length, lessThanOrEqualTo(48000 + 4000));
      expect(r.total, 400);
    });

    test('hamza, ta marbuta and "al" do not hide a match', () {
      final r = relevant(text, 'ما هي المده للعقود');
      expect(r.text, contains('مدة العقد'));
    });

    test('a page asked for by number is included, in Arabic digits too', () {
      final r = relevant(text, 'ماذا يوجد في الصفحة ٣٥٠؟');
      expect(r.text, contains('[الصفحة 350 / Page 350]'));
      expect(relevant(text, 'summarize page 12').text, contains('[الصفحة 12 / Page 12]'));
    });

    test('a follow-up keeps the earlier question', () {
      final r = relevant(text, 'وضح أكثر', context: 'كم مدة العقد؟');
      expect(r.text, contains('مدة العقد ثلاث سنوات'));
    });

    test('a summary question gets pages from across the book', () {
      final r = relevant(text, 'لخص');
      expect(r.text, contains('[الصفحة 1 / Page 1]'));
      expect(r.text, contains('[الصفحة 3'));
      expect(r.shown, greaterThan(10));
    });

    test('a small file is sent whole', () {
      final r = relevant(book(3), 'سؤال');
      expect(r.whole, isTrue);
    });

    test('word stems', () {
      expect(stem(Conversation.fold('والمحاصيل')), 'محاصيل');
      expect(stem('contracts'), 'contract');
    });
  });

  test('pdf reading reports page progress and counts text pages', () async {
    final seen = <int>[];
    final r = extractText('pdf', await pdf(30), onProgress: (d, t) {
      expect(t, 30);
      seen.add(d);
    });
    expect(seen.first, 0);
    expect(seen.last, 30);
    expect(r.pages, 30);
    expect(r.textPages, 30);
  });

  group('adding a big file', () {
    late AppStore store;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = AppStore(await SharedPreferences.getInstance(), await Directory.systemTemp.createTemp('fc'),
          adBlockCheck: () async => false);
    });

    test('streams in with a rising percentage and keeps the page count', () async {
      final bytes = await pdf(60);
      final progress = <double>[];
      store.addListener(() {
        final p = store.loadProgress;
        if (p != null) progress.add(p);
      });
      Stream<List<int>> chunks() async* {
        for (var i = 0; i < bytes.length; i += 4096) {
          yield bytes.sublist(i, i + 4096 > bytes.length ? bytes.length : i + 4096);
        }
      }

      await store.addAttachmentFrom('كتاب.pdf', bytes.length, chunks, 'محادثة جديدة');
      final a = store.pending.single;
      expect(a.pages, 60);
      expect(a.textual, isTrue);
      expect(File(a.path).lengthSync(), bytes.length);
      expect(a.extractedText, contains('Warranty period is 24 months'));
      expect(progress, isNotEmpty);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
      expect(progress.last, 1.0);
      expect(progress.where((p) => p > 0 && p < 1).length, greaterThan(5), reason: 'steps in between');
      expect(store.processing, 0);
      expect(store.loadName, isNull);
    });

    test('the picker\'s temporary copy is moved, not copied', () async {
      final tmp = File('${(await Directory.systemTemp.createTemp('fp')).path}/file_picker/1/a.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('hello');
      await store.addAttachmentFrom('a.txt', 5, () => throw StateError('should not read'), 'محادثة',
          movable: tmp.path);
      expect(tmp.existsSync(), isFalse);
      expect(File(store.pending.single.path).readAsStringSync(), 'hello');
    });

    test('a file that is not what its name says is removed again', () async {
      await expectLater(
          store.addAttachmentFrom('x.pdf', 4, () => Stream.value([1, 2, 3, 4]), 'محادثة'), throwsA(isA<AttachRejected>()));
      expect(store.pending, isEmpty);
      expect(store.processing, 0);
    });

    testWidgets('the ring shows the percentage and the page being read', (t) async {
      store
        ..loadName = 'كتاب.pdf'
        ..loadStage = 'read'
        ..loadProgress = 0.457
        ..loadDone = 120
        ..loadTotal = 300;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: LoadProgress(store: store, s: S('ar')))));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('45%'), findsOneWidget);
      expect(find.text('قراءة الصفحات 120 من 300'), findsOneWidget);
      expect(find.text('كتاب.pdf'), findsOneWidget);
    });
  });
}
