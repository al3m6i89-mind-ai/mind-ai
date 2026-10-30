import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_chat/core/ai.dart';
import 'package:file_chat/core/extract.dart';
import 'package:file_chat/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Uint8List zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, body) {
    final data = utf8.encode(body);
    a.addFile(ArchiveFile(name, data.length, data));
  });
  return Uint8List.fromList(ZipEncoder().encode(a));
}

void main() {
  group('validateBytes', () {
    test('accepts matching signatures', () {
      expect(validateBytes('pdf', Uint8List.fromList(utf8.encode('%PDF-1.7 ...'))), isNull);
      expect(validateBytes('png', Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D])), isNull);
      expect(validateBytes('docx', zip({'a': 'b'})), isNull);
      expect(validateBytes('txt', Uint8List.fromList(utf8.encode('مرحبا'))), isNull);
    });

    test('rejects empty and mismatched files', () {
      expect(validateBytes('txt', Uint8List(0)), 'emptyFile');
      expect(validateBytes('pdf', Uint8List.fromList(utf8.encode('not a pdf'))), 'contentMismatch');
      expect(validateBytes('jpg', Uint8List.fromList(utf8.encode('MZ executable'))), 'contentMismatch');
      expect(validateBytes('txt', Uint8List.fromList([0x41, 0x00, 0x42])), 'contentMismatch');
    });
  });

  test('extensionOf', () {
    expect(extensionOf('تقرير.Final.DOCX'), 'docx');
    expect(extensionOf('noext'), '');
  });

  test('docx keeps headings and skips tab tags', () {
    final bytes = zip({
      'word/document.xml': '<w:document><w:body>'
          '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>المقدمة</w:t></w:r></w:p>'
          '<w:p><w:r><w:t xml:space="preserve">السعر </w:t></w:r><w:r><w:tab/><w:t>100 &amp; ضريبة</w:t></w:r></w:p>'
          '</w:body></w:document>',
    });
    final r = extractText('docx', bytes);
    expect(r.note, isNull);
    expect(r.text, contains('## المقدمة'));
    expect(r.text, contains('السعر 100 & ضريبة'));
    expect(r.text, isNot(contains('<')));
  });

  test('pptx numbers slides and reads notes', () {
    final bytes = zip({
      'ppt/slides/slide2.xml': '<p:sld><a:p><a:r><a:t>الثانية</a:t></a:r></a:p></p:sld>',
      'ppt/slides/slide1.xml': '<p:sld><a:p><a:r><a:t>Hello</a:t></a:r><a:r><a:t> world</a:t></a:r></a:p></p:sld>',
      'ppt/notesSlides/notesSlide1.xml': '<a:t>ملاحظة مهمة</a:t>',
    });
    final t = extractText('pptx', bytes).text!;
    expect(t.indexOf('Slide 1'), lessThan(t.indexOf('Slide 2')));
    expect(t, contains('Hello world'));
    expect(t, contains('ملاحظة مهمة'));
  });

  test('xlsx names sheets and cells with shared strings and formulas', () {
    final bytes = zip({
      'xl/workbook.xml': '<workbook><sheets><sheet name="المبيعات" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels':
          '<Relationships><Relationship Id="rId1" Type="x" Target="worksheets/sheet1.xml"/></Relationships>',
      'xl/sharedStrings.xml': '<sst><si><t>الإجمالي</t></si></sst>',
      'xl/worksheets/sheet1.xml': '<worksheet><sheetData>'
          '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="D1" t="inlineStr"><is><t>&#1605;&#x631;</t></is></c><c r="E1"><f>A1*2</f></c><c r="B1"><f>SUM(B2:B3)</f><v>30</v></c><c r="C1" s="2"/></row>'
          '</sheetData></worksheet>',
    });
    final t = extractText('xlsx', bytes).text!;
    expect(t, contains('Sheet: المبيعات'));
    expect(t, contains('A1=الإجمالي'));
    expect(t, contains('B1=30 (=SUM(B2:B3))'));
    expect(t, contains('D1=مر'));
    expect(t, contains('E1 (=A1*2)'));
    expect(t, isNot(contains('C1')));
  });

  test('broken archive is reported, not thrown', () {
    final r = extractText('docx', Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 1, 2, 3]));
    expect(r.text, isNull);
    expect(r.note, 'extractFailed');
  });

  test('empty text is flagged', () {
    expect(extractText('txt', Uint8List.fromList(utf8.encode('   \n'))).note, 'noText');
  });

  test('conversation round-trips and searches', () {
    final c = Conversation(id: '1', title: 'فاتورة', messages: [
      Message(id: 'm', role: Role.user, text: 'كم الإجمالي؟', attachments: [
        Attachment(id: 'a', name: 'invoice.pdf', ext: 'pdf', size: 10, path: '/x/a.pdf'),
      ]),
      Message(id: 'r', role: Role.assistant, text: '100', status: MsgStatus.stopped),
    ]);
    final back = Conversation.decode(c.encode());
    expect(back.title, 'فاتورة');
    expect(back.messages.last.status, MsgStatus.stopped);
    expect(back.attachments.single.isPdf, isTrue);
    expect(back.matches('invoice'), isTrue);
    expect(back.matches('الإجمالي'), isTrue);
    expect(back.matches('غير موجود'), isFalse);
  });

  test('retired Gemini model: the successor named in the error', () {
    const err = 'This model models/gemini-2.5-flash is no longer available. Please use models/gemini-3.8-flash.';
    expect(AiClient.replacementModel(err, {'gemini-2.5-flash'}), 'gemini-3.8-flash');
    expect(AiClient.replacementModel('not found', {'x'}), isNull);
  });

  test('pdf text is read page by page', () async {
    final doc = PdfDocument();
    for (final t in ['Invoice No 77', 'Total 1250 SAR']) {
      doc.pages.add().graphics.drawString(t, PdfStandardFont(PdfFontFamily.helvetica, 12));
    }
    final bytes = Uint8List.fromList(await doc.save());
    doc.dispose();
    expect(validateBytes('pdf', bytes), isNull);
    final t = extractText('pdf', bytes).text!;
    expect(t, contains('Page 1'));
    expect(t.indexOf('Invoice No 77'), lessThan(t.indexOf('Page 2')));
    expect(t.indexOf('Page 2'), lessThan(t.indexOf('Total 1250 SAR')));
  });
}
