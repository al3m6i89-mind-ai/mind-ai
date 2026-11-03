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
  static const apiKey = 'AIzaSyBp9fKMoz5bxHwg164vEsYc3y_4kFG9tiE';

  /// "App ID", looks like 1:1234567890:android:abc123...
  static const appId = '1:510760819274:android:95f1359109afa461bee4b3';

  /// "Project number" / project_number.
  static const messagingSenderId = '510760819274';

  /// "Project ID".
  static const projectId = 'chat-f9edd';

  /// Storage bucket, usually `<project-id>.firebasestorage.app`.
  static const storageBucket = 'chat-f9edd.firebasestorage.app';

  static bool get ready => apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty && messagingSenderId.isNotEmpty;

  static FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: storageBucket.isEmpty ? null : storageBucket,
  );
}
