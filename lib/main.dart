import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app/shell.dart';
import 'features/auth/sign_in_screen.dart';
import 'app/theme.dart';
import 'providers/image_gen.dart';
import 'providers/text_provider.dart';
import 'providers/video_provider.dart';
import 'providers/voice_gen.dart';
import 'services/build_service.dart';
import 'services/chat_service.dart';
import 'services/code_service.dart';
import 'services/library_service.dart';
import 'services/settings_service.dart';
import 'services/social/social_service.dart';
import 'services/social/firebase_config.dart';
import 'services/social/firebase_remote.dart';
import 'services/social/social_remote.dart';
import 'services/social/social_store.dart';
import 'services/subscription_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsService.load();
  final subs = SubscriptionService(settings.prefs);
  final library = LibraryService();
  await library.init();
  final text = TextProvider(settings);
  final images = ImageGen(settings);
  final code = CodeService(text, subs, settings);
  await code.init();
  subs.init();
  final social = SocialService(FileSocialStore(), remote: await _firebase());
  // Loads in the background; the Community tab shows a spinner until ready.
  social.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: subs),
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: code),
        ChangeNotifierProvider.value(value: social),
        ChangeNotifierProvider(create: (_) => ChatService(settings.prefs, text, images, subs, library, settings)),
        ChangeNotifierProvider(create: (_) => BuildService(settings)),
        Provider.value(value: text),
        Provider.value(value: images),
        Provider(create: (_) => VideoProvider(settings)),
        Provider(create: (_) => VoiceGen(settings)),
      ],
      child: const MindApp(),
    ),
  );
}

/// Connects the Community to Firebase when lib/services/social/firebase_config.dart
/// is filled in; otherwise it runs on the phone only.
Future<SocialRemote?> _firebase() async {
  if (!FirebaseConfig.ready) return null;
  try {
    await Firebase.initializeApp(options: FirebaseConfig.options);
    return FirebaseSocialRemote();
  } catch (e) {
    debugPrint('Firebase init failed, Community stays on the phone: $e');
    return null;
  }
}

class MindApp extends StatelessWidget {
  const MindApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = context.select<SettingsService, bool>((s) => s.darkMode);
    return MaterialApp(
      title: 'Mind Ai',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: context.read<SettingsService>().signedIn ? const Shell() : const SignInScreen(),
    );
  }
}
