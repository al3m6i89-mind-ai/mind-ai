import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

enum CreationKind { image, sticker, animatedSticker, face, video, voice }

extension CreationKindInfo on CreationKind {
  String get label => switch (this) {
    CreationKind.image => 'صورة',
    CreationKind.sticker => 'ملصق',
    CreationKind.animatedSticker => 'ملصق متحرك',
    CreationKind.face => 'فيس',
    CreationKind.video => 'فيديو',
    CreationKind.voice => 'صوت',
  };

  String get ext => switch (this) {
    CreationKind.image || CreationKind.face => 'jpg',
    CreationKind.sticker => 'png',
    CreationKind.animatedSticker => 'gif',
    CreationKind.video => 'mp4',
    CreationKind.voice => 'wav',
  };
}

class Creation {
  Creation({required this.id, required this.kind, required this.path, required this.prompt, required this.time});

  final String id;
  final CreationKind kind;
  final String path;
  final String prompt;
  final DateTime time;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'path': path,
    'prompt': prompt,
    'time': time.toIso8601String(),
  };

  factory Creation.fromJson(Map<String, dynamic> j) => Creation(
    id: j['id'] as String,
    kind: CreationKind.values.byName(j['kind'] as String),
    path: j['path'] as String,
    prompt: j['prompt'] as String? ?? '',
    time: DateTime.parse(j['time'] as String),
  );
}

/// Keeps every generated file on the phone and lists them in "My creations".
class LibraryService extends ChangeNotifier {
  final List<Creation> items = [];
  late Directory _dir;

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/creations')..createSync(recursive: true);
    final index = File('${_dir.path}/index.json');
    if (index.existsSync()) {
      final list = jsonDecode(index.readAsStringSync()) as List;
      items
        ..clear()
        ..addAll(list.map((e) => Creation.fromJson(e as Map<String, dynamic>)))
        ..removeWhere((c) => !File(c.path).existsSync());
    }
  }

  Future<Creation> save(Uint8List bytes, CreationKind kind, String prompt, {String? ext}) async {
    final id = const Uuid().v4();
    final file = File('${_dir.path}/$id.${ext ?? kind.ext}');
    await file.writeAsBytes(bytes);
    final c = Creation(id: id, kind: kind, path: file.path, prompt: prompt, time: DateTime.now());
    items.insert(0, c);
    await _flush();
    notifyListeners();
    return c;
  }

  Future<void> delete(Creation c) async {
    items.remove(c);
    final f = File(c.path);
    if (f.existsSync()) f.deleteSync();
    await _flush();
    notifyListeners();
  }

  Future<void> _flush() =>
      File('${_dir.path}/index.json').writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));

  static Future<void> toGallery(String path, {bool video = false}) async {
    if (!await Gal.hasAccess()) await Gal.requestAccess();
    if (video) {
      await Gal.putVideo(path, album: 'Mind Ai');
    } else {
      await Gal.putImage(path, album: 'Mind Ai');
    }
  }

  static Future<void> share(String path, {String? text}) => Share.shareXFiles([XFile(path)], text: text);
}
