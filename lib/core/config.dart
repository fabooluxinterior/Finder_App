/// Build-time configuration, supplied with --dart-define.
///
/// When SUPABASE_URL / SUPABASE_ANON_KEY are absent the app runs in
/// self-contained demo mode (seeded profiles, simulated replies, mock billing).
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const revenueCatAndroidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');

  static bool get isDemo => supabaseUrl.isEmpty || supabaseAnonKey.isEmpty;

  static const productId = 'fast_track_79_monthly';
  static const entitlementId = 'fast_track';

  static const freeDailySwipes = 10;
  static const passHideDays = 7;
  static const directNoteMaxLength = 100;
  static const voiceMaxSeconds = 45;
  static const voiceBitRate = 32000;
  static const voiceSampleRate = 22050;

  /// Messages a sender writes into a thread before contact-info filtering relaxes.
  static const sanitizedOpeningMessages = 5;

  static const keralaCities = [
    'Kochi',
    'Thiruvananthapuram',
    'Kozhikode',
    'Thrissur',
    'Kannur',
    'Kollam',
    'Alappuzha',
    'Kottayam',
    'Palakkad',
    'Malappuram',
  ];
}
