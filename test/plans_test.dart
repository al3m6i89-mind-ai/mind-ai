import 'dart:io';

import 'package:file_chat/core/plan.dart';
import 'package:file_chat/core/store.dart';
import 'package:file_chat/core/strings.dart';
import 'package:file_chat/ui/plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<AppStore> store(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    return AppStore(await SharedPreferences.getInstance(), await Directory.systemTemp.createTemp('fc'),
        adBlockCheck: () async => false);
  }

  test('prices: \$19.99 a month, \$179.99 a year, saving 25%', () {
    expect(Plan.monthlyUsd, 19.99);
    expect(Plan.yearlyUsd, 179.99);
    expect(Plan.yearlySaving, 25);
  });

  group('free plan', () {
    test('the offer waits for the second opening, then every few hours', () async {
      expect((await store({'launches': 1})).promoDue, isFalse);
      final s = await store({'launches': 2});
      expect(s.promoDue, isTrue);
      s.promoShown();
      expect(s.promoDue, isFalse);
      final old = DateTime.now().subtract(AppStore.promoEvery).millisecondsSinceEpoch - 1000;
      expect((await store({'launches': 5, 'promoAt': old})).promoDue, isTrue);
    });

    test('an ad once every 10 to 15 openings', () async {
      expect((await store({'launches': 9, 'nextAd': 10})).adDue, isFalse);
      final s = await store({'launches': 10, 'nextAd': 10});
      expect(s.adDue, isTrue);
      s.adShown();
      final next = (await SharedPreferences.getInstance()).getInt('nextAd')!;
      expect(next, inInclusiveRange(10 + Plan.adEveryMin, 10 + Plan.adEveryMax));
      expect(s.adDue, isFalse);
    });

    test('subscribers see neither', () async {
      final s = await store({'launches': 30, 'nextAd': 10, 'premium': true});
      expect(s.adDue, isFalse);
      expect(s.promoDue, isFalse);
    });
  });

  testWidgets('the offer opens in the middle of the screen with the yearly saving', (t) async {
    final s = await t.runAsync(() => store({}));
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: s!,
      child: MaterialApp(
        home: Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showPromo(c), child: const Text('go'))))),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text(S('ar').t('promoTitle')), findsOneWidget);
    expect(find.text('السنوي \$179.99 — وفّر 25%'), findsOneWidget);
    expect(find.text(S('ar').t('fNoAds')), findsOneWidget);
    await t.ensureVisible(find.text(S('ar').t('promoLater')));
    await t.pumpAndSettle();
    await t.tap(find.text(S('ar').t('promoLater')));
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('the plans page offers yearly first, and monthly', (t) async {
    final s = await t.runAsync(() => store({}));
    t.view.physicalSize = const Size(1200, 3000);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(ChangeNotifierProvider.value(value: s!, child: const MaterialApp(home: PlansScreen())));
    await t.pumpAndSettle();
    expect(find.text('\$179.99 / سنة'), findsOneWidget);
    expect(find.text('وفّر 25%'), findsOneWidget);
    await t.ensureVisible(find.text('شهري'));
    await t.pumpAndSettle();
    await t.tap(find.text('شهري'));
    await t.pumpAndSettle();
    expect(find.text('\$19.99 / شهر'), findsOneWidget);
  });
}
