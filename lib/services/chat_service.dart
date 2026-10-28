import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../providers/ai_models.dart';
import '../providers/image_gen.dart';
import '../providers/text_provider.dart';
import 'library_service.dart';
import 'subscription_service.dart';

/// Personas, like Dola's bots: each one is just a system prompt and a look.
class Persona {
  const Persona(this.id, this.name, this.emoji, this.tagline, this.system);
  final String id;
  final String name;
  final String emoji;
  final String tagline;
  final String system;

  static const _base =
      'أنت Mind Ai، مساعد ذكي ودود ومحترف. أجب بلغة المستخدم (العربية افتراضياً) وبأسلوب واضح ومنظم مع Markdown عند الحاجة.';

  static const all = [
    Persona('mind', 'Mind Ai', '🧠', 'مساعدك لكل شيء', _base),
    Persona('coder', 'المبرمج', '👨‍💻', 'يكتب ويشرح ويصلح الأكواد',
        '$_base أنت خبير برمجة (Flutter, Kotlin, Python, JavaScript, Web). اكتب أكواداً كاملة قابلة للتشغيل داخل كتل ``` مع اسم اللغة، واشرح باختصار.'),
    Persona('artist', 'الفنان', '🎨', 'يحوّل أفكارك لأوصاف صور مذهلة',
        '$_base أنت فنان ومهندس أوامر صور. ساعد المستخدم في كتابة أوصاف (prompts) احترافية بالإنجليزية للصور والفيديو والملصقات.'),
    Persona('writer', 'الكاتب', '✍️', 'مقالات، منشورات، قصص',
        '$_base أنت كاتب محتوى محترف ومبدع للتسويق ووسائل التواصل والقصص.'),
    Persona('tutor', 'المعلّم', '📚', 'يشرح أي درس بسهولة',
        '$_base أنت معلم صبور يشرح خطوة بخطوة مع أمثلة.'),
    Persona('translator', 'المترجم', '🌍', 'ترجمة دقيقة لأي لغة',
        '$_base أنت مترجم محترف. ترجم بدقة وحافظ على المعنى والأسلوب.'),
  ];

  static Persona byId(String id) => all.firstWhere((p) => p.id == id, orElse: () => all.first);
}

class Conversation {
  Conversation({required this.id, required this.personaId, required this.title, List<ChatMessage>? messages})
      : messages = messages ?? [];

  final String id;
  final String personaId;
  String title;
  final List<ChatMessage> messages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'personaId': personaId,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] as String,
        personaId: j['personaId'] as String? ?? 'mind',
        title: j['title'] as String? ?? '',
        messages: (j['messages'] as List? ?? [])
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ChatService extends ChangeNotifier {
  ChatService(this._prefs, this._text, this._images, this._subs, this._library) {
    final raw = _prefs.getString('conversations');
    if (raw != null) {
      conversations.addAll(
        (jsonDecode(raw) as List).map((e) => Conversation.fromJson(e as Map<String, dynamic>)),
      );
    }
  }

  final SharedPreferences _prefs;
  final TextProvider _text;
  final ImageGen _images;
  final SubscriptionService _subs;
  final LibraryService _library;

  final List<Conversation> conversations = [];
  bool busy = false;

  Conversation start(String personaId) {
    final c = Conversation(id: const Uuid().v4(), personaId: personaId, title: 'محادثة جديدة');
    conversations.insert(0, c);
    notifyListeners();
    return c;
  }

  void remove(Conversation c) {
    conversations.remove(c);
    _persist();
    notifyListeners();
  }

  static final _drawIntent = RegExp(r'^(ارسم|ارسملي|صمم|صمّم|أنشئ صورة|انشئ صورة|سوي صورة|draw|/image)\s*', caseSensitive: false);

  Future<void> send(Conversation c, String text, {Uint8List? image}) async {
    if (busy) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && image == null) return;

    c.messages.add(ChatMessage(role: Role.user, text: trimmed, imageBytes: image));
    if (c.messages.length == 1) {
      c.title = trimmed.isEmpty ? 'صورة' : (trimmed.length > 32 ? '${trimmed.substring(0, 32)}…' : trimmed);
    }
    busy = true;
    notifyListeners();

    final reply = ChatMessage(role: Role.assistant, text: '');
    c.messages.add(reply);
    try {
      final draw = _drawIntent.firstMatch(trimmed);
      if (draw != null && image == null) {
        _subs.ensure(Usage.image);
        reply.text = '🎨 جاري الرسم…';
        notifyListeners();
        final prompt = trimmed.substring(draw.end);
        final enPrompt = await _toEnglishPrompt(prompt);
        final out = await _images.generate(enPrompt);
        final saved = await _library.save(out.bytes, CreationKind.image, prompt);
        await _subs.consume(Usage.image);
        c.messages.removeLast();
        c.messages.add(ChatMessage(role: Role.assistant, text: 'تفضل! 🎨 «$prompt»', imageUrl: saved.path));
      } else {
        _subs.ensure(Usage.chat);
        final persona = Persona.byId(c.personaId);
        final history = c.messages.where((m) => m != reply).toList();
        final window = history.length > 20 ? history.sublist(history.length - 20) : history;
        await for (final token in _text.chat(window, system: persona.system)) {
          reply.text += token;
          notifyListeners();
        }
        await _subs.consume(Usage.chat);
      }
    } catch (e) {
      reply.text = '⚠️ $e';
    } finally {
      busy = false;
      _persist();
      notifyListeners();
    }
  }

  /// Image models follow English prompts far better, so translate quietly first.
  Future<String> _toEnglishPrompt(String prompt) async {
    if (!RegExp(r'[؀-ۿ]').hasMatch(prompt)) return prompt;
    try {
      final out = await _text.complete(
        [ChatMessage(role: Role.user, text: prompt)],
        system:
            'Translate the user request into one vivid English image-generation prompt. Reply with the prompt only.',
      );
      return out.trim().isEmpty ? prompt : out.trim();
    } catch (_) {
      return prompt;
    }
  }

  Future<String> englishPrompt(String prompt) => _toEnglishPrompt(prompt);

  void _persist() {
    final keep = conversations.take(50).map((c) => c.toJson()).toList();
    _prefs.setString('conversations', jsonEncode(keep));
  }
}
