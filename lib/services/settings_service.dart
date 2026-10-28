import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Text providers the user can switch between. All of them have a free tier.
enum TextBackend { pollinations, gemini, groq, openrouter, custom }

/// Image providers. Pollinations needs no key; Gemini uses its free image model.
enum ImageBackend { pollinations, gemini, custom }

/// Video providers. Video has no truly unlimited free API, so this stays pluggable.
enum VideoBackend { pollinations, replicate, custom }

extension TextBackendInfo on TextBackend {
  String get label => switch (this) {
        TextBackend.pollinations => 'Pollinations (مجاني بدون مفتاح)',
        TextBackend.gemini => 'Google Gemini (مفتاح مجاني)',
        TextBackend.groq => 'Groq (مفتاح مجاني وسريع جداً)',
        TextBackend.openrouter => 'OpenRouter (نماذج مجانية)',
        TextBackend.custom => 'مزوّد مخصص (OpenAI-compatible)',
      };

  String get defaultBaseUrl => switch (this) {
        TextBackend.pollinations => 'https://text.pollinations.ai/openai',
        TextBackend.gemini =>
          'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
        TextBackend.groq => 'https://api.groq.com/openai/v1/chat/completions',
        TextBackend.openrouter => 'https://openrouter.ai/api/v1/chat/completions',
        TextBackend.custom => '',
      };

  String get defaultModel => switch (this) {
        TextBackend.pollinations => 'openai',
        TextBackend.gemini => 'gemini-2.5-flash',
        TextBackend.groq => 'llama-3.3-70b-versatile',
        TextBackend.openrouter => 'deepseek/deepseek-chat-v3-0324:free',
        TextBackend.custom => '',
      };

  bool get needsKey => this != TextBackend.pollinations;
}

extension ImageBackendInfo on ImageBackend {
  String get label => switch (this) {
        ImageBackend.pollinations => 'Pollinations (مجاني بدون مفتاح)',
        ImageBackend.gemini => 'Google Gemini Image (مفتاح مجاني)',
        ImageBackend.custom => 'رابط مخصص',
      };
}

extension VideoBackendInfo on VideoBackend {
  String get label => switch (this) {
        VideoBackend.pollinations => 'Pollinations Video',
        VideoBackend.replicate => 'Replicate (مفتاح)',
        VideoBackend.custom => 'رابط مخصص',
      };
}

class SettingsService extends ChangeNotifier {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsService> load() async =>
      SettingsService(await SharedPreferences.getInstance());

  SharedPreferences get prefs => _prefs;

  String _s(String k, [String d = '']) => _prefs.getString(k) ?? d;
  Future<void> _set(String k, String v) async {
    await _prefs.setString(k, v);
    notifyListeners();
  }

  // ---- Appearance
  bool get darkMode => _prefs.getBool('darkMode') ?? false;
  Future<void> setDarkMode(bool v) async {
    await _prefs.setBool('darkMode', v);
    notifyListeners();
  }

  String get userName => _s('userName');
  Future<void> setUserName(String v) => _set('userName', v);

  // ---- Text
  TextBackend get textBackend =>
      TextBackend.values.byName(_s('textBackend', TextBackend.pollinations.name));
  Future<void> setTextBackend(TextBackend b) => _set('textBackend', b.name);

  String textKey(TextBackend b) => _s('key_${b.name}');
  Future<void> setTextKey(TextBackend b, String v) => _set('key_${b.name}', v.trim());

  String textModel(TextBackend b) => _s('model_${b.name}', b.defaultModel);
  Future<void> setTextModel(TextBackend b, String v) => _set('model_${b.name}', v.trim());

  String textBaseUrl(TextBackend b) => _s('url_${b.name}', b.defaultBaseUrl);
  Future<void> setTextBaseUrl(TextBackend b, String v) => _set('url_${b.name}', v.trim());

  // ---- Image
  ImageBackend get imageBackend =>
      ImageBackend.values.byName(_s('imageBackend', ImageBackend.pollinations.name));
  Future<void> setImageBackend(ImageBackend b) => _set('imageBackend', b.name);

  String get imageModel => _s('imageModel', 'flux');
  Future<void> setImageModel(String v) => _set('imageModel', v.trim());

  String get pollinationsToken => _s('pollinationsToken');
  Future<void> setPollinationsToken(String v) => _set('pollinationsToken', v.trim());

  /// Custom image endpoint. `{prompt}`, `{width}`, `{height}` and `{seed}` are substituted.
  String get customImageUrl => _s('customImageUrl');
  Future<void> setCustomImageUrl(String v) => _set('customImageUrl', v.trim());

  // ---- Video
  VideoBackend get videoBackend =>
      VideoBackend.values.byName(_s('videoBackend', VideoBackend.pollinations.name));
  Future<void> setVideoBackend(VideoBackend b) => _set('videoBackend', b.name);

  String get replicateKey => _s('replicateKey');
  Future<void> setReplicateKey(String v) => _set('replicateKey', v.trim());

  String get replicateVideoModel => _s('replicateVideoModel', 'minimax/video-01');
  Future<void> setReplicateVideoModel(String v) => _set('replicateVideoModel', v.trim());

  String get customVideoUrl => _s('customVideoUrl');
  Future<void> setCustomVideoUrl(String v) => _set('customVideoUrl', v.trim());

  // ---- GitHub cloud build (replaces Android Studio)
  String get githubToken => _s('githubToken');
  Future<void> setGithubToken(String v) => _set('githubToken', v.trim());

  /// `owner/repo` that receives generated projects and builds them with GitHub Actions.
  String get githubRepo => _s('githubRepo');
  Future<void> setGithubRepo(String v) => _set('githubRepo', v.trim());

  bool get githubReady => githubToken.isNotEmpty && githubRepo.contains('/');
}
