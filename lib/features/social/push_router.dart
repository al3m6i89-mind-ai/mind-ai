import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'messages_screen.dart';
import 'notifications_screen.dart';

/// What happens with a push notification inside the app: tapping one opens
/// the chat or the notifications list; one that arrives while the app is open
/// shows as a bar at the bottom.
class PushRouter {
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static Future<void> start() async {
    try {
      FirebaseMessaging.onMessageOpenedApp.listen(_open);
      FirebaseMessaging.onMessage.listen(_whileOpen);
      // The app was closed and started by tapping a notification.
      final first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _open(first));
      }
    } catch (_) {
      // Push isn't available on this phone; everything else keeps working.
    }
  }

  static void _open(RemoteMessage m) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final from = m.data['fromId'] ?? '';
    if (m.data['type'] == 'message' && from.isNotEmpty) {
      nav.push(MaterialPageRoute(builder: (_) => ChatScreen(userId: from)));
    } else {
      nav.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    }
  }

  static void _whileOpen(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text([n.title, n.body].whereType<String>().join('\n')),
        action: SnackBarAction(label: 'عرض', onPressed: () => _open(m)),
      ),
    );
  }
}
