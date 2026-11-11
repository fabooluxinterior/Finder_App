/// Build-time configuration, supplied with --dart-define.
///
/// Demo mode (seeded profiles, simulated replies, mock billing) is compiled
/// in only with --dart-define=DEMO=true. Being a const, the demo backend and
/// sample data are tree-shaken out of every other build.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const revenueCatAndroidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');

  static const isDemo = bool.fromEnvironment('DEMO');

  /// The CI run number the app was built from (--dart-define=BUILD_NUMBER). It
  /// is also the Android version code, so newer builds install over older ones.
  /// 0 for local builds: the "update available" check is off then.
  static const buildNumber = int.fromEnvironment('BUILD_NUMBER');

  /// Where new builds are published (GitHub Releases, public download).
  static const updateRepo = 'fabooluxinterior/Finder_App';
  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Bump when the Terms, Privacy Policy or Community Guidelines change
  /// materially; users who accepted an older version must re-consent.
  static const policyVersion = '2026-11-19';
  static const minimumAge = 18;

  static const productId = 'fast_track_79_monthly';
  static const entitlementId = 'fast_track';

  static const passHideDays = 7;
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
