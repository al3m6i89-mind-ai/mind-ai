import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Text providers the user can switch between. All of them have a free tier.
enum TextBackend { pollinations, anthropic, openai, gemini, groq, openrouter, custom }

/// Image providers. Pollinations needs no key; Gemini uses its free image model.
enum ImageBackend { pollinations, huggingface, cloudflare, seedream, replicate, gemini, custom }

/// Video providers. Video has no truly unlimited free API, so this stays pluggable.
enum VideoBackend { pollinations, huggingface, seedance, replicate, custom }

extension TextBackendInfo on TextBackend {
  String get label => switch (this) {
    TextBackend.pollinations => 'Pollinations (مجاني بدون مفتاح)',
    TextBackend.anthropic => 'Claude من Anthropic (مفتاح)',
    TextBackend.openai => 'ChatGPT من OpenAI (مفتاح)',
    TextBackend.gemini => 'Google Gemini (مفتاح مجاني)',
    TextBackend.groq => 'Groq (مفتاح مجاني وسريع جداً)',
    TextBackend.openrouter => 'OpenRouter (نماذج مجانية)',
    TextBackend.custom => 'مزوّد مخصص (OpenAI-compatible)',
  };

  String get defaultBaseUrl => switch (this) {
    TextBackend.pollinations => 'https://text.pollinations.ai/openai',
    TextBackend.anthropic => 'https://api.anthropic.com/v1/messages',
    TextBackend.openai => 'https://api.openai.com/v1/chat/completions',
    TextBackend.gemini => 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
    TextBackend.groq => 'https://api.groq.com/openai/v1/chat/completions',
    TextBackend.openrouter => 'https://openrouter.ai/api/v1/chat/completions',
    TextBackend.custom => '',
  };

  String get defaultModel => switch (this) {
    TextBackend.pollinations => 'openai',
    TextBackend.anthropic => 'claude-opus-5-5',
    TextBackend.openai => 'gpt-5',
    TextBackend.gemini => 'gemini-2.5-flash',
    TextBackend.groq => 'llama-3.3-70b-versatile',
    TextBackend.openrouter => 'deepseek/deepseek-chat-v3-0324:free',
    TextBackend.custom => '',
  };

  bool get needsKey => this != TextBackend.pollinations;

  /// Page where the user gets a key for this backend.
  String? get keyUrl => switch (this) {
    TextBackend.pollinations => 'https://enter.pollinations.ai',
    TextBackend.anthropic => 'https://platform.claude.com/settings/keys',
    TextBackend.openai => 'https://platform.openai.com/api-keys',
    TextBackend.gemini => 'https://aistudio.google.com/apikey',
    TextBackend.groq => 'https://console.groq.com/keys',
    TextBackend.openrouter => 'https://openrouter.ai/keys',
    TextBackend.custom => null,
  };
}

extension ImageBackendInfo on ImageBackend {
  String get label => switch (this) {
    ImageBackend.pollinations => 'Pollinations (مجاني بدون مفتاح)',
    ImageBackend.huggingface => 'Hugging Face (رمز مجاني)',
    ImageBackend.cloudflare => 'Cloudflare Workers AI (مجاني)',
    ImageBackend.seedream => 'Seedream من BytePlus (مفتاح)',
    ImageBackend.gemini => 'Google Gemini Image (مفتاح مجاني)',
    ImageBackend.replicate => 'Replicate (مفتاح)',
    ImageBackend.custom => 'رابط مخصص',
  };
}

extension VideoBackendInfo on VideoBackend {
  String get label => switch (this) {
    VideoBackend.pollinations => 'Pollinations Video',
    VideoBackend.huggingface => 'Hugging Face (رمز)',
    VideoBackend.seedance => 'Seedance من BytePlus (مفتاح)',
    VideoBackend.replicate => 'Replicate (مفتاح)',
    VideoBackend.custom => 'رابط مخصص',
  };
}

class SettingsService extends ChangeNotifier {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsService> load() async => SettingsService(await SharedPreferences.getInstance());

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

  // ---- Account
  bool get signedIn => _s('accountEmail').isNotEmpty;
  String get accountEmail => _s('accountEmail');
  Future<void> signIn(String name, String email) async {
    await _prefs.setString('userName', name);
    await _set('accountEmail', email);
  }

  Future<void> signOut() => _set('accountEmail', '');

  String get userName => _s('userName');
  Future<void> setUserName(String v) => _set('userName', v);

  // ---- Text
  TextBackend get textBackend => TextBackend.values.byName(_s('textBackend', TextBackend.pollinations.name));
  Future<void> setTextBackend(TextBackend b) => _set('textBackend', b.name);

  String textKey(TextBackend b) => _s('key_${b.name}');
  Future<void> setTextKey(TextBackend b, String v) async {
    await _set('key_${b.name}', v.trim());
    // A new strong key replaces the keyless default right away.
    if (v.trim().isNotEmpty && textBackend == TextBackend.pollinations && b != TextBackend.custom) {
      await setTextBackend(b);
    }
  }

  String textModel(TextBackend b) => _s('model_${b.name}', b.defaultModel);
  Future<void> setTextModel(TextBackend b, String v) => _set('model_${b.name}', v.trim());

  String textBaseUrl(TextBackend b) => _s('url_${b.name}', b.defaultBaseUrl);
  Future<void> setTextBaseUrl(TextBackend b, String v) => _set('url_${b.name}', v.trim());

  /// The strongest text backend that has a key, for jobs that need a smart model
  /// (the code agent, prompt writing). Falls back to the chosen backend.
  TextBackend get bestTextBackend {
    for (final b in const [
      TextBackend.anthropic,
      TextBackend.openai,
      TextBackend.gemini,
      TextBackend.groq,
      TextBackend.openrouter,
    ]) {
      if (textKey(b).isNotEmpty) return b;
    }
    return textBackend;
  }

  // ---- BytePlus ModelArk (Seedream images, Seedance video)
  String get arkKey => _s('arkKey');
  Future<void> setArkKey(String v) => _set('arkKey', v.trim());

  String get arkBaseUrl => _s('arkBaseUrl', 'https://ark.ap-southeast.bytepluses.com/api/v3');
  Future<void> setArkBaseUrl(String v) => _set('arkBaseUrl', v.trim());

  /// Model or endpoint id (ep-...) as shown in the ModelArk console.
  String get seedreamModel => _s('seedreamModel', 'seedream-4-0-250828');
  Future<void> setSeedreamModel(String v) => _set('seedreamModel', v.trim());

  String get seedanceModel => _s('seedanceModel', 'seedance-1-0-pro-250528');
  Future<void> setSeedanceModel(String v) => _set('seedanceModel', v.trim());

  // ---- Cloudflare Workers AI (free daily allowance)
  String get cfAccountId => _s('cfAccountId');
  Future<void> setCfAccountId(String v) => _set('cfAccountId', v.trim());
  String get cfToken => _s('cfToken');
  Future<void> setCfToken(String v) => _set('cfToken', v.trim());

  // ---- Hugging Face (images through hf-inference, video through its fal-ai route)
  String get hfToken => _s('hfToken');
  Future<void> setHfToken(String v) => _set('hfToken', v.trim());

  String get hfImageModel => _s('hfImageModel', 'fal-ai/flux/schnell');
  Future<void> setHfImageModel(String v) => _set('hfImageModel', v.trim());

  String get hfVideoModel => _s('hfVideoModel', 'fal-ai/ltx-video');
  Future<void> setHfVideoModel(String v) => _set('hfVideoModel', v.trim());

  /// Last tool picked in the image and video screens (see providers/tools.dart).
  String get imageToolId => _s('imageToolId', 'flux');
  Future<void> setImageToolId(String v) => _set('imageToolId', v);
  String get videoToolId => _s('videoToolId', 'free');
  Future<void> setVideoToolId(String v) => _set('videoToolId', v);

  // ---- Image
  ImageBackend get imageBackend => ImageBackend.values.byName(_s('imageBackend', ImageBackend.pollinations.name));
  Future<void> setImageBackend(ImageBackend b) => _set('imageBackend', b.name);

  String get imageModel => _s('imageModel', 'flux');
  Future<void> setImageModel(String v) => _set('imageModel', v.trim());

  String get pollinationsToken => _s('pollinationsToken');
  Future<void> setPollinationsToken(String v) => _set('pollinationsToken', v.trim());

  /// Custom image endpoint. `{prompt}`, `{width}`, `{height}` and `{seed}` are substituted.
  String get customImageUrl => _s('customImageUrl');
  Future<void> setCustomImageUrl(String v) => _set('customImageUrl', v.trim());

  // ---- Video
  VideoBackend get videoBackend => VideoBackend.values.byName(_s('videoBackend', VideoBackend.pollinations.name));
  Future<void> setVideoBackend(VideoBackend b) => _set('videoBackend', b.name);

  String get replicateKey => _s('replicateKey');
  Future<void> setReplicateKey(String v) => _set('replicateKey', v.trim());

  String get replicateVideoModel => _s('replicateVideoModel', 'bytedance/seedance-1-pro');
  Future<void> setReplicateVideoModel(String v) => _set('replicateVideoModel', v.trim());

  String get replicateImageModel => _s('replicateImageModel', 'bytedance/seedream-4');
  Future<void> setReplicateImageModel(String v) => _set('replicateImageModel', v.trim());

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
