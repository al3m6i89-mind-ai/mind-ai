/// What each plan allows. The paid plan is a Google Play subscription, monthly or yearly.
class Plan {
  static const productId = monthlyId;
  static const monthlyId = 'file_chat_premium_monthly';
  static const yearlyId = 'file_chat_premium_yearly';
  static const productIds = {monthlyId, yearlyId};

  /// Shown until Google Play reports the prices in the user's currency.
  static const monthlyUsd = 19.99;
  static const yearlyUsd = 179.99;

  /// The yearly plan against twelve months: 25%.
  static int get yearlySaving => (100 - yearlyUsd / (monthlyUsd * 12) * 100).round();

  static const freeDailyQuestions = 20;
  static const freeMaxFileBytes = 50 * 1024 * 1024;

  /// No plan limit; this only guards the phone's memory, which holds the whole file while reading it.
  static const premiumMaxFileBytes = 500 * 1024 * 1024;

  /// Free plan: a full-screen ad once every this many app openings (picked at random in the range).
  static const adEveryMin = 10, adEveryMax = 15;
}
