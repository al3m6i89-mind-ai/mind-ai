import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Where the social data lives. The app ships with [FileSocialStore] (on the
/// phone); a server-backed store (Firebase, Supabase, your own API) can take
/// its place without touching the screens.
abstract class SocialStore {
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> data);

  /// Copies a picked photo or video somewhere permanent and returns its new path or URL.
  Future<String> importMedia(String path);
}

class FileSocialStore implements SocialStore {
  Directory? _dir;

  Future<Directory> _root() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/social');
    Directory('${_dir!.path}/media').createSync(recursive: true);
    return _dir!;
  }

  @override
  Future<Map<String, dynamic>?> load() async {
    final f = File('${(await _root()).path}/db.json');
    if (!f.existsSync()) return null;
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      // A half-written file from a crash: keep a copy and start clean.
      await f.copy('${f.path}.broken');
      return null;
    }
  }

  @override
  Future<void> save(Map<String, dynamic> data) async {
    final root = await _root();
    // Write then rename, so a crash never leaves a broken database.
    final tmp = File('${root.path}/db.json.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename('${root.path}/db.json');
  }

  @override
  Future<String> importMedia(String path) async {
    if (path.startsWith('http')) return path;
    final root = await _root();
    final dot = path.lastIndexOf('.');
    final ext = dot > path.lastIndexOf('/') ? path.substring(dot) : '';
    final out = '${root.path}/media/${const Uuid().v4()}$ext';
    await File(path).copy(out);
    return out;
  }
}

/// Keeps everything in memory. Used by the tests.
class MemorySocialStore implements SocialStore {
  Map<String, dynamic>? data;

  @override
  Future<Map<String, dynamic>?> load() async => data == null ? null : jsonDecode(jsonEncode(data)) as Map<String, dynamic>;

  @override
  Future<void> save(Map<String, dynamic> d) async => data = jsonDecode(jsonEncode(d)) as Map<String, dynamic>;

  @override
  Future<String> importMedia(String path) async => path;
}
