import 'dart:convert';

enum Role { user, assistant }

enum MsgStatus { complete, streaming, error, stopped }

/// A file or image the user attached. The original is copied into app storage;
/// [extractedText] holds the text pulled out on the phone (Word, Excel, ...).
class Attachment {
  Attachment({
    required this.id,
    required this.name,
    required this.ext,
    required this.size,
    required this.path,
    this.extractedText,
    this.note,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String name;
  final String ext;
  final int size;
  final String path;
  final String? extractedText;

  /// Why the content could not be read, if it could not.
  final String? note;
  final DateTime createdAt;

  bool get isImage => const {'jpg', 'jpeg', 'png', 'webp'}.contains(ext);
  bool get isPdf => ext == 'pdf';

  /// Sent to the model as the original bytes (Gemini reads PDFs and images itself).
  bool get sentAsBinary => isImage || isPdf;
  bool get readable => sentAsBinary || (extractedText != null && extractedText!.isNotEmpty);

  String get mime => switch (ext) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'jpg' || 'jpeg' => 'image/jpeg',
        _ => 'text/plain',
      };

  String get typeLabel => switch (ext) {
        'pdf' => 'PDF',
        'docx' => 'Word',
        'pptx' => 'PowerPoint',
        'xlsx' => 'Excel',
        'md' || 'markdown' => 'Markdown',
        _ => ext.toUpperCase(),
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ext': ext,
        'size': size,
        'path': path,
        if (extractedText != null) 'text': extractedText,
        if (note != null) 'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        id: j['id'] as String,
        name: j['name'] as String,
        ext: j['ext'] as String,
        size: j['size'] as int,
        path: j['path'] as String,
        extractedText: j['text'] as String?,
        note: j['note'] as String?,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
      );
}

class Message {
  Message({
    required this.id,
    required this.role,
    required this.text,
    this.status = MsgStatus.complete,
    this.error,
    this.via,
    List<String>? trace,
    List<Attachment>? attachments,
    DateTime? time,
  })  : trace = trace ?? [],
        attachments = attachments ?? [],
        time = time ?? DateTime.now();

  final String id;
  final Role role;
  String text;
  MsgStatus status;
  String? error;

  /// The server that wrote this reply (Gemini, Mistral, ...).
  String? via;

  /// Servers that failed before this reply, and why.
  final List<String> trace;

  /// Live progress while servers are busy; not saved.
  String? note;
  final List<Attachment> attachments;
  final DateTime time;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'status': status.name,
        if (error != null) 'error': error,
        if (via != null) 'via': via,
        if (trace.isNotEmpty) 'trace': trace,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'time': time.toIso8601String(),
      };

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        role: Role.values.byName(j['role'] as String),
        text: j['text'] as String? ?? '',
        status: MsgStatus.values.asNameMap()[j['status']] ?? MsgStatus.complete,
        error: j['error'] as String?,
        via: j['via'] as String?,
        trace: [for (final t in (j['trace'] as List? ?? const [])) t as String],
        attachments: [
          for (final a in (j['attachments'] as List? ?? const [])) Attachment.fromJson(a as Map<String, dynamic>),
        ],
        time: DateTime.tryParse(j['time'] as String? ?? ''),
      );
}

class Conversation {
  Conversation({required this.id, required this.title, List<Message>? messages, DateTime? updatedAt})
      : messages = messages ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  final List<Message> messages;
  DateTime updatedAt;

  Iterable<Attachment> get attachments => messages.expand((m) => m.attachments);

  bool matches(String q) {
    final s = q.toLowerCase();
    return title.toLowerCase().contains(s) ||
        messages.any((m) => m.text.toLowerCase().contains(s)) ||
        attachments.any((a) => a.name.toLowerCase().contains(s));
  }

  String encode() => jsonEncode({
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      });

  factory Conversation.decode(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return Conversation(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
      messages: [for (final m in (j['messages'] as List? ?? const [])) Message.fromJson(m as Map<String, dynamic>)],
    );
  }
}
