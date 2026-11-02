import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_chat/core/auth.dart';
import 'package:file_chat/core/plan.dart';
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
    store = AppStore(await SharedPreferences.getInstance(), dir, adBlockCheck: () async => false);
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
    expect(find.textContaining('Gemini'), findsNothing);
    expect(find.textContaining('مفتاح'), findsNothing);
    await t.tap(find.text('English'));
    await t.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
  });

  testWidgets('an ad blocker on the free plan covers the app until it is off', (t) async {
    var blocked = true;
    final dir = await t.runAsync(() => Directory.systemTemp.createTemp('fc'));
    store = AppStore(await t.runAsync(SharedPreferences.getInstance) as SharedPreferences, dir!,
        adBlockCheck: () async => blocked);
    await pump(t);
    expect(find.text('أوقف مانع الإعلانات'), findsOneWidget);
    blocked = false;
    await t.tap(find.text('أوقفته، تحقّق مجدداً'));
    await t.pumpAndSettle();
    expect(find.text('اسأل عن ملفاتك وصورك'), findsOneWidget);
  });

  testWidgets('signed out: the login screen comes first', (t) async {
    final dir = await t.runAsync(() => Directory.systemTemp.createTemp('fc'));
    store = AppStore(await t.runAsync(SharedPreferences.getInstance) as SharedPreferences, dir!,
        adBlockCheck: () async => false, auth: Auth.signedOutForTest());
    await pump(t);
    expect(find.text('المتابعة بحساب Google'), findsOneWidget);
    expect(find.text('إرسال رمز التحقق'), findsOneWidget);
  });

  testWidgets('attached file shows as a pending card', (t) async {
    await pump(t);
    await t.runAsync(() => store.addAttachment('notes.txt', Uint8List.fromList(utf8.encode('hello')), 'محادثة جديدة'));
    await t.pumpAndSettle();
    expect(find.text('notes.txt'), findsOneWidget);
    expect(store.pending, hasLength(1));
  });

  test('free plan stops after the daily questions', () async {
    await store.addAttachment('n.txt', Uint8List.fromList(utf8.encode('x')), 'محادثة جديدة');
    // Sending needs no network here: count only, the answer itself fails offline.
    for (var i = 0; i < Plan.freeDailyQuestions; i++) {
      expect(store.canAsk, isTrue);
      store.debugCountQuestion();
    }
    expect(store.questionsLeft, 0);
    expect(await store.send('another', 'محادثة جديدة'), isFalse);
    expect(store.maxFileBytes, Plan.freeMaxFileBytes);
  });
}
