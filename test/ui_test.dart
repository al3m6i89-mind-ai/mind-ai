import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_chat/core/strings.dart';
import 'package:file_chat/core/auth.dart';
import 'package:file_chat/core/models.dart';
import 'package:file_chat/core/plan.dart';
import 'package:file_chat/core/store.dart';
import 'package:file_chat/core/updates.dart';
import 'package:file_chat/main.dart';
import 'package:file_chat/ui/account.dart';
import 'package:file_chat/ui/admin.dart';
import 'package:file_chat/ui/help.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppStore store;

  setUpAll(() => PackageInfo.setMockInitialValues(
      appName: 'File Chat', packageName: 'com.zuhair.file_chat', version: '1.4.3', buildNumber: '21', buildSignature: ''));

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
    expect(find.text('Version 1.4.3 (21)'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Check for updates'), 300);
  });

  testWidgets('long press selects chats, select all, delete selected', (t) async {
    for (final n in ['أولى', 'ثانية', 'ثالثة']) {
      store.conversations.add(Conversation(id: n, title: n));
    }
    await pump(t);
    await t.tap(find.byTooltip('المحادثات'));
    await t.pumpAndSettle();
    await t.longPress(find.text('ثانية'));
    await t.pumpAndSettle();
    expect(find.text('1 محدد'), findsOneWidget);
    await t.tap(find.text('تحديد الكل'));
    await t.pumpAndSettle();
    expect(find.text('3 محدد'), findsOneWidget);
    await t.tap(find.text('أولى'));
    await t.pumpAndSettle();
    expect(find.text('2 محدد'), findsOneWidget);
    await t.tap(find.byTooltip('حذف'));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.widgetWithText(FilledButton, 'حذف'));
      for (var i = 0; i < 20 && store.conversations.length > 1; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await t.pumpAndSettle();
    expect(store.conversations.map((c) => c.title), ['أولى']);
    expect(find.text('تحديد الكل'), findsNothing);
  });

  testWidgets('account screen shows the plan and today\'s usage', (t) async {
    await t.pumpWidget(ChangeNotifierProvider.value(
        value: store, child: const MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: AccountScreen()))));
    await t.pumpAndSettle();
    expect(find.text('باقتك'), findsOneWidget);
    expect(find.text('0 / ${Plan.freeDailyQuestions}'), findsOneWidget);
    expect(find.text('50 ميجابايت'), findsOneWidget);
    expect(find.text('يجب إيقافه'), findsOneWidget);
  });

  testWidgets('owner dashboard: numbers, users, and blocking an account', (t) async {
    final now = DateTime.utc(2026, 11, 2, 12).millisecondsSinceEpoch;
    var blocked = 0;
    final calls = <String>[];
    t.view.physicalSize = const Size(900, 3200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Map<String, dynamic> data() => {
          'now': now,
          'totals': {'users': 2, 'newToday': 1, 'activeToday': 2, 'active7': 2, 'subscribers': 1, 'questionsToday': 7,
            'voiceToday': 2, 'helpToday': 0, 'questionsAll': 123, 'byGoogle': 1, 'byEmail': 1, 'blocked': blocked},
          'days': [for (var i = 0; i < 14; i++) {'day': '2026-10-${(20 + i).toString().padLeft(2, '0')}', 'ask': i, 'voice': 0, 'help': 0, 'users': 0}],
          'users': [
            {'uid': 'u1', 'email': 'spam@gmail.com', 'provider': 'password', 'first': now - 3600000, 'last': now - 120000,
              'questions': 30, 'voice': 2, 'today': 7, 'premiumUntil': null, 'blocked': blocked},
            {'uid': 'u2', 'email': 'good@hotmail.com', 'provider': 'google.com', 'first': now - 86400000 * 3, 'last': now - 86400000,
              'questions': 1, 'voice': 0, 'today': 0, 'premiumUntil': now + 86400000 * 20, 'blocked': 0},
          ],
        };
    await t.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
            home: AdminScreen(
          load: () async => data(),
          block: (uid, b) async {
            calls.add('$uid:$b');
            blocked = b ? 1 : 0;
            return true;
          },
        ))));
    await t.pumpAndSettle();
    expect(find.text('123'), findsOneWidget);
    expect(find.text('spam@gmail.com'), findsOneWidget);
    expect(find.text('good@hotmail.com'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'spam');
    await t.pumpAndSettle();
    expect(find.text('good@hotmail.com'), findsNothing);
    await t.tap(find.text('spam@gmail.com'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'حظر'));
    await t.pumpAndSettle();
    expect(find.text('حظر spam@gmail.com؟'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'حظر'));
    await t.pumpAndSettle();
    expect(calls, ['u1:true']);
    expect(find.text('محظور'), findsOneWidget);
  });

  test('only the owner sees the dashboard button', () {
    expect(Admin.isOwner('5AZUY2@gmail.com'), isTrue);
    expect(Admin.isOwner('zuhair63766@gmail.com'), isFalse);
    expect(Admin.isOwner('someone@gmail.com'), isFalse);
    expect(Admin.isOwner(null), isFalse);
  });

  testWidgets('a new release shows a banner, settings can check again', (t) async {
    var build = 30;
    final dir = await t.runAsync(() => Directory.systemTemp.createTemp('fc'));
    store = AppStore(await t.runAsync(SharedPreferences.getInstance) as SharedPreferences, dir!,
        adBlockCheck: () async => false,
        updates: Updater(
          currentBuild: () async => 22,
          client: MockClient((_) async => http.Response(
              jsonEncode({'version': '1.5.0', 'build': build, 'url': 'https://example.com/a.apk'}), 200)),
        ));
    await pump(t);
    await t.pumpAndSettle();
    expect(find.text('تحديث جديد متاح · 1.5.0'), findsOneWidget, reason: '${store.updates.state} ${store.updates.error}');
    await t.tap(find.text('تحديث الآن'));
    await t.pumpAndSettle();
    expect(find.text('الإصدار 1.5.0 جاهز'), findsOneWidget);
    await t.tap(find.text('لاحقاً'));
    await t.pumpAndSettle();

    build = 22;
    await t.tap(find.byTooltip('المحادثات'));
    await t.pumpAndSettle();
    await t.tap(find.text('الإعدادات'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('البحث عن تحديثات'), 300);
    await t.tap(find.text('البحث عن تحديثات'));
    await t.pumpAndSettle();
    expect(find.text('لديك أحدث إصدار'), findsOneWidget);
  });

  testWidgets('help page: assistant, customer service, guide and FAQ', (t) async {
    await t.pumpWidget(ChangeNotifierProvider.value(
        value: store, child: const MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: HelpScreen()))));
    await t.pumpAndSettle();
    expect(find.text('5azuy2@gmail.com'), findsOneWidget);
    expect(find.text('+96897133135'), findsOneWidget);
    expect(find.text('طريقة الاستخدام'), findsOneWidget);
    await t.scrollUntilVisible(find.text('ما أنواع الملفات المدعومة؟'), 300);
    await t.tap(find.text('ما أنواع الملفات المدعومة؟'));
    await t.pumpAndSettle();
    expect(find.textContaining('PDF (حتى الممسوحة'), findsOneWidget);
    await t.scrollUntilVisible(find.text('المساعد الذكي'), -300);
    await t.tap(find.text('المساعد الذكي'));
    await t.pumpAndSettle();
    expect(find.textContaining('أنا مساعد قارئ الملفات'), findsOneWidget);
    expect(find.text('كيف أوقف مانع الإعلانات؟'), findsOneWidget);
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
    expect(find.text('الإصدار 1.4.3 (21)'), findsOneWidget);
    expect(find.text('إرسال رمز التحقق'), findsNothing); // phone sign-in is off until billing is on
  });

  testWidgets('an empty message box offers the microphone; typing turns it into send', (t) async {
    await pump(t);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    final box = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == S('ar').t('placeholder'));
    expect(box, findsOneWidget);
    await t.enterText(box, 'سؤال');
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.mic_rounded), findsNothing);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
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
