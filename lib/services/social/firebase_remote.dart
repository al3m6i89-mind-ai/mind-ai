import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'social_service.dart' show SocialService;
import 'social_remote.dart';

/// The social space on Firebase: Auth for sign-in, Firestore for data,
/// Storage for photos and videos. Matching rules: `firebase/*.rules`.
class FirebaseSocialRemote implements SocialRemote {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _subs = <StreamSubscription<dynamic>>[];

  // ---- push notifications: this phone's token, saved in /tokens for the server.
  String? _token;
  String? _pushId;
  StreamSubscription<String>? _tokenRefresh;

  Future<void> _registerPush(String meId) async {
    _pushId = meId;
    try {
      final m = FirebaseMessaging.instance;
      final perm = await m.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await m.getToken();
      if (token != null) await _saveToken(token);
      _tokenRefresh ??= m.onTokenRefresh.listen(_saveToken);
    } catch (_) {
      // No Google Play services or no network: the app still works without push.
    }
  }

  Future<void> _saveToken(String token) async {
    final id = _pushId, uid = authUid;
    if (id == null || uid == null) return;
    _token = token;
    await _db.collection('tokens').doc(token).set({
      'id': id,
      'authUid': uid,
      'platform': 'android',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  String? get authUid => _auth.currentUser?.uid;

  @override
  String? get authEmail => _auth.currentUser?.email;

  // ------------------------------------------------------------ sign-in

  static String _authMessage(FirebaseAuthException e) => switch (e.code) {
    'invalid-email' => 'البريد الإلكتروني غير صحيح',
    'user-not-found' || 'wrong-password' || 'invalid-credential' => 'البريد أو كلمة المرور غير صحيحة',
    'email-already-in-use' => 'هذا البريد مسجّل، سجّل الدخول بدلاً من إنشاء حساب',
    'weak-password' => 'كلمة المرور ضعيفة، استخدم 6 أحرف على الأقل',
    'too-many-requests' => 'محاولات كثيرة، انتظر قليلاً ثم حاول مرة أخرى',
    'network-request-failed' => 'لا يوجد اتصال بالإنترنت',
    'operation-not-allowed' => 'فعّل تسجيل الدخول بالبريد في Firebase: Authentication ← Sign-in method ← Email/Password',
    _ => e.message ?? e.code,
  };

  Future<void> _authCall(Future<void> Function() f) async {
    try {
      await f();
    } on FirebaseAuthException catch (e) {
      throw ArgumentError(_authMessage(e));
    }
  }

  @override
  Future<void> signIn(String email, String password) =>
      _authCall(() => _auth.signInWithEmailAndPassword(email: email.trim(), password: password));

  @override
  Future<void> signUp(String email, String password) =>
      _authCall(() => _auth.createUserWithEmailAndPassword(email: email.trim(), password: password));

  @override
  Future<void> resetPassword(String email) => _authCall(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> signOut() async {
    stop();
    // This phone stops receiving the old account's notifications.
    final token = _token;
    _pushId = null;
    _token = null;
    if (token != null) {
      try {
        await _db.collection('tokens').doc(token).delete();
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
    await _auth.signOut();
  }

  @override
  Future<String?> linkedId() async {
    final uid = authUid;
    if (uid == null) return null;
    final snap = await _db.collection('uids').doc(uid).get();
    return snap.data()?['id'] as String?;
  }

  @override
  Future<void> createProfile(SocialUser u) async {
    final uid = authUid;
    if (uid == null) throw StateError('سجّل الدخول أولاً');
    final handleRef = _db.collection('handles').doc(u.handle);
    final userRef = _db.collection('users').doc(u.id);
    await _db.runTransaction((tx) async {
      final h = await tx.get(handleRef);
      if (h.exists) throw ArgumentError('المعرّف @${u.handle} مستخدم، جرّب غيره');
      final existing = await tx.get(userRef);
      if (existing.exists) throw StateError('id-taken');
      tx.set(_db.collection('uids').doc(uid), {'id': u.id});
      tx.set(userRef, {...u.toJson(), 'local': false, 'authUid': uid});
      tx.set(handleRef, {'id': u.id});
    });
  }

  @override
  Future<void> changeHandle(String id, String oldHandle, String newHandle) async {
    if (oldHandle == newHandle) return;
    final newRef = _db.collection('handles').doc(newHandle);
    await _db.runTransaction((tx) async {
      final taken = await tx.get(newRef);
      if (taken.exists && taken.data()?['id'] != id) throw ArgumentError('المعرّف @$newHandle مستخدم، جرّب غيره');
      tx.set(newRef, {'id': id});
      tx.delete(_db.collection('handles').doc(oldHandle));
      tx.update(_db.collection('users').doc(id), {'handle': newHandle});
    });
  }

  // ------------------------------------------------------------ live data

  @override
  void listen(String meId, void Function(String collection, List<Map<String, dynamic>> docs) onDocs) {
    stop();
    void on(String name, Query<Map<String, dynamic>> q) {
      _subs.add(
        q.snapshots().listen(
          (s) => onDocs(name, [for (final d in s.docs) d.data()]),
          // A rule or index problem shouldn't crash the app; the screen keeps what it has.
          onError: (Object _) {},
        ),
      );
    }

    final dayAgo = DateTime.now().toUtc().subtract(Story.life).toIso8601String();
    on('users', _db.collection('users').limit(5000));
    // The newest posts stay live; older ones come page by page (postsPage).
    on('posts', _db.collection('posts').orderBy('createdAt', descending: true).limit(liveWindow));
    on('comments', _db.collection('comments').orderBy('createdAt', descending: true).limit(3000));
    on('stories', _db.collection('stories').where('createdAt', isGreaterThan: dayAgo));
    on('notices', _db.collection('notices').where('toId', isEqualTo: meId).limit(500));
    on('chats', _db.collection('chats').where('members', arrayContains: meId));
    on('messages', _db.collection('messages').where('members', arrayContains: meId).limit(3000));
    _registerPush(meId);
  }

  @override
  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  // ------------------------------------------------------------ writes

  static Object? _value(Object? v) => switch (v) {
    ArrayAdd(:final value) => FieldValue.arrayUnion([value]),
    ArrayRemove(:final value) => FieldValue.arrayRemove([value]),
    Increment(:final by) => FieldValue.increment(by),
    _ => v,
  };

  @override
  Future<void> put(String collection, String id, Map<String, dynamic> data, {bool merge = false}) =>
      _db.collection(collection).doc(id).set(data, SetOptions(merge: merge));

  @override
  Future<void> patch(String collection, String id, Map<String, dynamic> fields) =>
      _db.collection(collection).doc(id).update(fields.map((k, v) => MapEntry(k, _value(v))));

  @override
  Future<void> delete(String collection, String id) => _db.collection(collection).doc(id).delete();

  /// How many of the newest posts are kept live.
  static const liveWindow = SocialService.liveWindow;

  @override
  Future<List<Map<String, dynamic>>> postsPage({String? kind, String? authorId, String? before, int limit = 24}) async {
    Query<Map<String, dynamic>> q = _db.collection('posts');
    // Each filter + order pair has a composite index (firebase/firestore.indexes.json).
    if (kind != null) q = q.where('kind', isEqualTo: kind);
    if (authorId != null) q = q.where('authorId', isEqualTo: authorId);
    q = q.orderBy('createdAt', descending: true);
    if (before != null) q = q.startAfter([before]);
    final snap = await q.limit(limit).get();
    return [for (final d in snap.docs) d.data()];
  }

  @override
  Future<String> upload(String path) async {
    if (path.startsWith('http')) return path;
    final uid = authUid;
    if (uid == null) throw StateError('سجّل الدخول أولاً');
    final dot = path.lastIndexOf('.');
    final ext = dot > path.lastIndexOf('/') ? path.substring(dot).toLowerCase() : '';
    final type = switch (ext) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.mp4' => 'video/mp4',
      '.mov' => 'video/quicktime',
      '.webm' => 'video/webm',
      _ => null,
    };
    final ref = FirebaseStorage.instance.ref('media/$uid/${const Uuid().v4()}$ext');
    try {
      await ref.putFile(File(path), SettableMetadata(contentType: type));
    } on FirebaseException catch (e) {
      throw ArgumentError(
        e.code == 'unauthorized' || e.code == 'bucket-not-found' || e.code == 'project-not-found'
            ? 'رفع الصور والفيديو غير مفعّل: فعّل Storage في Firebase وانشر قواعده (firebase/storage.rules)'
            : 'تعذّر رفع الملف: ${e.message ?? e.code}',
      );
    }
    return ref.getDownloadURL();
  }
}
