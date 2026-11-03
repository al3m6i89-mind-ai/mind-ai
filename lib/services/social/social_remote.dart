import 'models.dart';

/// A server that holds the social space for everyone (Firebase today).
///
/// The service keeps a local copy for instant screens and sends each change
/// here as a small, field-level write, so two people liking the same post at
/// the same moment never overwrite each other.
abstract class SocialRemote {
  // ---- sign-in (one login = one unified ID)
  String? get authUid;
  String? get authEmail;
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> resetPassword(String email);
  Future<void> signOut();

  /// The unified ID linked to the signed-in login, or null before the profile is made.
  Future<String?> linkedId();

  /// Claims the user's ID and @handle in one transaction and links them to the
  /// login. Throws [ArgumentError] when the handle is taken.
  Future<void> createProfile(SocialUser u);

  /// Moves the @handle claim; throws [ArgumentError] when the new one is taken.
  Future<void> changeHandle(String id, String oldHandle, String newHandle);

  // ---- live data
  /// Delivers every document of a collection each time it changes. Collections:
  /// users, posts, comments, stories, notices (mine), chats (mine), messages (mine).
  void listen(String meId, void Function(String collection, List<Map<String, dynamic>> docs) onDocs);
  void stop();

  // ---- writes
  /// Writes a whole document ([merge] keeps fields not in [data]).
  Future<void> put(String collection, String id, Map<String, dynamic> data, {bool merge = false});

  /// Updates some fields. Values may be [ArrayAdd], [ArrayRemove] or [Increment].
  /// Keys may be dotted paths (`readAt.MA-...`).
  Future<void> patch(String collection, String id, Map<String, dynamic> fields);
  Future<void> delete(String collection, String id);

  /// Uploads a photo or video and returns its public download URL.
  Future<String> upload(String path);
}

/// Adds a value to an array field without touching the rest of it.
class ArrayAdd {
  const ArrayAdd(this.value);
  final Object value;
}

/// Removes a value from an array field without touching the rest of it.
class ArrayRemove {
  const ArrayRemove(this.value);
  final Object value;
}

/// Adds [by] to a number field on the server.
class Increment {
  const Increment(this.by);
  final int by;
}
