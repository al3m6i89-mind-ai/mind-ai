import '../services/settings_service.dart';

/// An image model the user can pick in the studio, with its price in points.
class ImageTool {
  const ImageTool(this.id, this.label, this.emoji, this.points, this.backend, {this.model, this.note = ''});
  final String id;
  final String label;
  final String emoji;
  final int points;
  final ImageBackend backend;

  /// Pollinations model name, when [backend] is Pollinations.
  final String? model;
  final String note;

  bool available(SettingsService s) => switch (backend) {
    ImageBackend.pollinations => true,
    ImageBackend.huggingface => s.hfToken.isNotEmpty,
    ImageBackend.cloudflare => s.cfToken.isNotEmpty && s.cfAccountId.isNotEmpty,
    ImageBackend.seedream => s.arkKey.isNotEmpty,
    ImageBackend.gemini => s.textKey(TextBackend.gemini).isNotEmpty,
    ImageBackend.replicate => s.replicateKey.isNotEmpty,
    ImageBackend.custom => s.customImageUrl.isNotEmpty,
  };

  /// What to add in the settings to unlock this tool.
  String get needs => switch (backend) {
    ImageBackend.pollinations => '',
    ImageBackend.huggingface => 'رمز Hugging Face',
    ImageBackend.cloudflare => 'رمز Cloudflare',
    ImageBackend.seedream => 'مفتاح BytePlus',
    ImageBackend.gemini => 'مفتاح Gemini',
    ImageBackend.replicate => 'مفتاح Replicate',
    ImageBackend.custom => 'رابط مخصص',
  };

  static const all = [
    ImageTool('flux', 'FLUX', '⚡', 1, ImageBackend.pollinations, model: 'flux', note: 'مجاني وجودة عالية'),
    ImageTool('turbo', 'Turbo', '🚀', 1, ImageBackend.pollinations, model: 'turbo', note: 'الأسرع'),
    ImageTool('cf', 'Cloudflare FLUX', '☁️', 1, ImageBackend.cloudflare, note: 'مجاني وسريع برمز'),
    ImageTool('hf', 'Hugging Face FLUX', '🤗', 2, ImageBackend.huggingface, note: 'دقيق ومجاني برمز'),
    ImageTool('gemini', 'Gemini Nano Banana', '🍌', 3, ImageBackend.gemini, note: 'ممتاز للتعديل والنصوص'),
    ImageTool('seedream', 'Seedream', '🌟', 6, ImageBackend.seedream, note: 'الأقوى والأدق'),
    ImageTool('rseedream', 'Seedream (Replicate)', '🌟', 6, ImageBackend.replicate, note: 'Seedream من أي دولة'),
    ImageTool('custom', 'مخصص', '🔧', 2, ImageBackend.custom),
  ];

  static ImageTool byId(String id) => all.firstWhere((t) => t.id == id, orElse: () => all.first);
}

/// A video model the user can pick, with its price in points. [backend] is null
/// for the free on-device clip (AI picture + camera motion).
class VideoTool {
  const VideoTool(this.id, this.label, this.emoji, this.points, this.backend, {this.note = ''});
  final String id;
  final String label;
  final String emoji;
  final int points;
  final VideoBackend? backend;
  final String note;

  bool available(SettingsService s) => switch (backend) {
    null => true,
    VideoBackend.pollinations => s.pollinationsToken.isNotEmpty,
    VideoBackend.huggingface => s.hfToken.isNotEmpty,
    VideoBackend.seedance => s.arkKey.isNotEmpty,
    VideoBackend.replicate => s.replicateKey.isNotEmpty,
    VideoBackend.custom => s.customVideoUrl.isNotEmpty,
  };

  String get needs => switch (backend) {
    null => '',
    VideoBackend.pollinations => 'رمز Pollinations',
    VideoBackend.huggingface => 'رمز Hugging Face',
    VideoBackend.seedance => 'مفتاح BytePlus',
    VideoBackend.replicate => 'مفتاح Replicate',
    VideoBackend.custom => 'رابط مخصص',
  };

  static const all = [
    VideoTool('free', 'مشهد متحرك', '🎞️', 5, null, note: 'مجاني: صورة ذكية + حركة كاميرا'),
    VideoTool('pollinations', 'Pollinations Video', '🌸', 12, VideoBackend.pollinations),
    VideoTool('hf', 'Hugging Face LTX', '🤗', 20, VideoBackend.huggingface, note: 'فيديو حقيقي'),
    VideoTool('replicate', 'Seedance (Replicate)', '🎬', 40, VideoBackend.replicate, note: 'Seedance من أي دولة'),
    VideoTool('seedance', 'Seedance Pro', '🎬', 40, VideoBackend.seedance, note: 'الأقوى: حركة سينمائية'),
    VideoTool('custom', 'مخصص', '🔧', 20, VideoBackend.custom),
  ];

  static VideoTool byId(String id) => all.firstWhere((t) => t.id == id, orElse: () => all.first);
}
