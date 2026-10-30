// Renders screens to PNG for a visual check: flutter test test/shots_test.dart --update-goldens
import 'dart:convert';
import 'dart:io';

import 'package:file_chat/core/models.dart';
import 'package:file_chat/core/store.dart';
import 'package:file_chat/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> loadFonts() async {
  final plex = FontLoader('Plex');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    plex.addFont(Future.value(ByteData.sublistView(File('assets/fonts/IBMPlexSansArabic-$w.ttf').readAsBytesSync())));
  }
  await plex.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter-sdk/flutter';
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(
        File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

void main() {
  final out = Platform.environment['SHOTS'];
  if (out == null) return;

  Future<AppStore> makeStore(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    return AppStore(await SharedPreferences.getInstance(), await Directory.systemTemp.createTemp('fc'));
  }

  Future<void> shot(WidgetTester t, AppStore store, String name, {Future<void> Function()? then}) async {
    await t.runAsync(loadFonts);
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 2.75;
    await t.pumpWidget(ChangeNotifierProvider.value(value: store, child: const FileChatApp()));
    await t.pump(const Duration(seconds: 1));
    if (then != null) await then();
    await t.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$out/$name.png'));
  }

  for (final theme in ['light', 'dark']) {
    testWidgets('empty $theme', (t) async {
      await shot(t, (await t.runAsync(() => makeStore({'theme': theme})))!, 'empty_$theme');
    });
    testWidgets('chat $theme', (t) async {
      final store = (await t.runAsync(() => makeStore({'theme': theme, 'geminiKey': 'x'})))!;
      await t.runAsync(() async {
        await store.addAttachment('فاتورة-أكتوبر.xlsx', _xlsx(), 'محادثة جديدة');
      });
      final conv = store.current!;
      conv.title = 'فاتورة أكتوبر';
      conv.messages.addAll([
        Message(id: '1', role: Role.user, text: 'كم إجمالي الفاتورة؟', attachments: List.of(store.pending)),
        Message(
          id: '2',
          role: Role.assistant,
          text: 'إجمالي الفاتورة **1,250 ريال**، ويشمل:\n\n- الخدمات: 1,000 ريال\n- الضريبة: 250 ريال\n\n**المصدر:** فاتورة-أكتوبر.xlsx، ورقة «الفاتورة»، الخلية B4',
        ),
      ]);
      store.pending.clear();
      await shot(t, store, 'chat_$theme');
    });
  }
  testWidgets('drawer', (t) async {
    final store = (await t.runAsync(() => makeStore({'theme': 'light'})))!;
    await t.runAsync(() async {
      for (final n in ['تقرير المبيعات', 'عرض المشروع']) {
        await store.addAttachment('$n.txt', Uint8List.fromList(utf8.encode('x')), n);
        store.current!.messages.add(Message(id: n, role: Role.user, text: n, attachments: List.of(store.pending)));
        store.pending.clear();
        store.select(null);
      }
    });
    await shot(t, store, 'drawer', then: () async {
      await t.tap(find.byTooltip('المحادثات'));
      await t.pump(const Duration(seconds: 1));
    });
  });
}

Uint8List _xlsx() => Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]);
