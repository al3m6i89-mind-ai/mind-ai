import 'dart:typed_data';

enum Role { system, user, assistant }

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    this.imageBytes,
    this.imageUrl,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  final Role role;
  String text;

  /// An image attached by the user, or generated inline by the assistant.
  final Uint8List? imageBytes;
  final String? imageUrl;
  final DateTime time;

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'text': text,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'time': time.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: Role.values.byName(j['role'] as String),
        text: j['text'] as String? ?? '',
        imageUrl: j['imageUrl'] as String?,
        time: DateTime.tryParse(j['time'] as String? ?? ''),
      );
}

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Result of an image request: raw bytes plus the size actually produced.
class GeneratedImage {
  GeneratedImage(this.bytes, {this.prompt = ''});
  final Uint8List bytes;
  final String prompt;
}

class GeneratedVideo {
  GeneratedVideo({this.url, this.bytes});
  final String? url;
  final Uint8List? bytes;
}
