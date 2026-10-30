import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_chat/core/store.dart';
import 'package:file_chat/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('fc');
    store = AppStore(await SharedPreferences.getInstance(), dir);
  });

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(ChangeNotifierProvider.value(value: store, child: const FileChatApp()));
    await t.pumpAndSettle();
  }

  testWidgets('empty state, drawer and settings open', (t) async {
    await pump(t);
    expect(find.text('اسأل عن ملفاتك وصورك'), findsOneWidget);
    await t.tap(find.byTooltip('المحادثات'));
    await t.pumpAndSettle();
    expect(find.text('لا توجد محادثات بعد.'), findsOneWidget);
    await t.tap(find.text('الإعدادات'));
    await t.pumpAndSettle();
    expect(find.text('مزوّد الذكاء الاصطناعي'), findsOneWidget);
    await t.tap(find.text('English'));
    await t.pumpAndSettle();
    expect(find.text('AI provider'), findsOneWidget);
  });

  testWidgets('attached file shows as a pending card', (t) async {
    await pump(t);
    await t.runAsync(() => store.addAttachment('notes.txt', Uint8List.fromList(utf8.encode('hello')), 'محادثة جديدة'));
    await t.pumpAndSettle();
    expect(find.text('notes.txt'), findsOneWidget);
    expect(store.pending, hasLength(1));
  });
}
