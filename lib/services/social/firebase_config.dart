import 'package:firebase_core/firebase_core.dart';

/// Your Firebase project's Android app settings.
///
/// Firebase console → ⚙️ Project settings → General → "Your apps" → the
/// Android app `com.zuhair.chat`. These values are not secrets: the
/// security rules in `firebase/firestore.rules` and `firebase/storage.rules`
/// are what protect the data.
///
/// While they are empty the Community runs on the phone only (with sample
/// content); fill them in and it becomes a real network shared by everyone.
class FirebaseConfig {
  /// "Web API Key" / api_key → current_key in google-services.json.
  static const apiKey = '';

  /// "App ID", looks like 1:1234567890:android:abc123...
  static const appId = '';

  /// "Project number" / project_number.
  static const messagingSenderId = '';

  /// "Project ID".
  static const projectId = '';

  /// Storage bucket, usually `<project-id>.firebasestorage.app`.
  static const storageBucket = '';

  static bool get ready => apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty && messagingSenderId.isNotEmpty;

  static FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: storageBucket.isEmpty ? null : storageBucket,
  );
}
