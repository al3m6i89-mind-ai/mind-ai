/// What each plan allows. The paid plan is a monthly Google Play subscription.
class Plan {
  static const productId = 'file_chat_premium_monthly';

  static const freeDailyQuestions = 20;
  static const freeMaxFileBytes = 50 * 1024 * 1024;

  /// No plan limit; this only guards the phone's memory, which holds the whole file while reading it.
  static const premiumMaxFileBytes = 500 * 1024 * 1024;
}
