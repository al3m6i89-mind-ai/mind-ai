import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The Firebase project used for sign-in (values from its google-services.json;
/// they identify the project and are not secret). Empty until the project is
/// set up, and then sign-in is skipped instead of showing buttons that fail.
class FirebaseSetup {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'AIzaSyCsOnwLgQkuGN3V9-WOJBdzsmEWk2M-XvI');
  static const appId =
      String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '1:463476849908:android:d32305ad3915b7c0e8b2a1');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '463476849908');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'file-chat-224b4');
  /// The project's Web OAuth client (client_type 3 in google-services.json),
  /// which Google's account picker needs to hand Firebase an ID token.
  static const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID',
      defaultValue: '463476849908-0b871iie2oa3nkbernmph11mt93ps4ed.apps.googleusercontent.com');
  static bool get configured => apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty;
}

/// Sign-in with Google or a phone number, through Firebase Authentication.
class Auth extends ChangeNotifier {
  Auth.disabled() : available = false;
  Auth._() : available = true;

  /// Signed out, for screen tests.
  @visibleForTesting
  Auth.signedOutForTest() : available = true;

  /// False when Firebase is not set up for this build: the app opens without sign-in.
  final bool available;
  User? user;
  String? _verificationId;
  int? _resendToken;

  static Future<Auth> start() async {
    if (!FirebaseSetup.configured) return Auth.disabled();
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: FirebaseSetup.apiKey,
          appId: FirebaseSetup.appId,
          messagingSenderId: FirebaseSetup.senderId,
          projectId: FirebaseSetup.projectId,
          authDomain: '${FirebaseSetup.projectId}.firebaseapp.com',
        ),
      );
      final a = Auth._()..user = FirebaseAuth.instance.currentUser;
      FirebaseAuth.instance.authStateChanges().listen((u) {
        a.user = u;
        a.notifyListeners();
      });
      return a;
    } catch (_) {
      return Auth.disabled();
    }
  }

  bool get needsSignIn => available && user == null;

  /// Who is signed in, for the settings screen.
  String? get label {
    final u = user;
    if (u == null) return null;
    for (final v in [u.displayName, u.email, u.phoneNumber]) {
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  bool _googleReady = false;

  /// Returns null on success, or an error code for [S.authError]. Uses
  /// Android's own account picker when the Web client is known, otherwise
  /// Firebase's browser sign-in.
  Future<String?> google() async {
    if (FirebaseSetup.webClientId.isEmpty) {
      return _guard(() => FirebaseAuth.instance.signInWithProvider(GoogleAuthProvider()..addScope('email')));
    }
    try {
      final g = GoogleSignIn.instance;
      if (!_googleReady) {
        await g.initialize(serverClientId: FirebaseSetup.webClientId);
        _googleReady = true;
      }
      final account = await g.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) return 'no-id-token';
      return await _guard(() => FirebaseAuth.instance.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken)));
    } on GoogleSignInException catch (e) {
      return e.code == GoogleSignInExceptionCode.canceled ? 'canceled' : 'google-${e.code.name}';
    } catch (e) {
      return 'unknown:${e.runtimeType}';
    }
  }

  /// Sends the SMS code. Completes when the code is sent (or the phone
  /// verified itself automatically, then [user] is set).
  Future<String?> sendCode(String phone) {
    final done = Completer<String?>();
    _guard(() => FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: phone,
          forceResendingToken: _resendToken,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (cred) async {
            final err = await _guard(() => FirebaseAuth.instance.signInWithCredential(cred));
            if (!done.isCompleted) done.complete(err);
          },
          verificationFailed: (e) {
            debugPrint('auth: ${e.code} ${e.message}');
            if (!done.isCompleted) done.complete(_codeOf(e));
          },
          codeSent: (id, token) {
            _verificationId = id;
            _resendToken = token;
            if (!done.isCompleted) done.complete(null);
          },
          codeAutoRetrievalTimeout: (id) => _verificationId = id,
        )).then((err) {
      if (err != null && !done.isCompleted) done.complete(err);
    });
    return done.future;
  }

  Future<String?> verifyCode(String code) {
    final id = _verificationId;
    if (id == null) return Future.value('session-expired');
    return _guard(() => FirebaseAuth.instance
        .signInWithCredential(PhoneAuthProvider.credential(verificationId: id, smsCode: code.trim())));
  }

  Future<void> signOut() async {
    if (available) await FirebaseAuth.instance.signOut();
  }

  /// Firebase reports some failures (billing, app checks) only as "unknown" or
  /// "internal-error"; the server's text is kept so the cause can be seen.
  static String _codeOf(FirebaseAuthException e) {
    if ((e.code == 'unknown' || e.code == 'internal-error') && (e.message ?? '').isNotEmpty) {
      final m = e.message!;
      return '${e.code}: ${m.length > 160 ? m.substring(0, 160) : m}';
    }
    return e.code;
  }

  static Future<String?> _guard(Future<Object?> Function() f) async {
    try {
      await f();
      return null;
    } on FirebaseAuthException catch (e) {
      debugPrint('auth: ${e.code} ${e.message}');
      return _codeOf(e);
    } catch (e) {
      debugPrint('auth: $e');
      return 'unknown:${e.runtimeType}';
    }
  }
}
