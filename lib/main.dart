import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/store.dart';
import 'ui/gate.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await AppStore.open();
  if (store.auth.available) _reportCrashes();
  runApp(ChangeNotifierProvider.value(value: store, child: const FileChatApp()));
}

/// Sends crashes and uncaught errors to Firebase Crashlytics (release builds only).
void _reportCrashes() {
  try {
    final c = FirebaseCrashlytics.instance;
    c.setCrashlyticsCollectionEnabled(kReleaseMode);
    FlutterError.onError = (d) {
      FlutterError.presentError(d);
      c.recordFlutterFatalError(d);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      c.recordError(e, st, fatal: true);
      return true;
    };
  } catch (e) {
    debugPrint('crashlytics: $e');
  }
}

class FileChatApp extends StatelessWidget {
  const FileChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return MaterialApp(
      title: 'قارئ الملفات',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: store.themeMode,
      locale: Locale(store.lang),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const StartGate(),
    );
  }
}
