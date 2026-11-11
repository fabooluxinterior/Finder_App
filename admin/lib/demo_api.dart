import 'dart:async';

import 'api.dart';
import 'generated/migrations.g.dart';
import 'models.dart';

/// Sample data for previewing the admin app without a backend
/// (--dart-define=ADMIN_DEMO=true). Shown with a "Sample data" banner.
class DemoAdminApi extends AdminApi {
  @override
  bool get isDemo => true;

  final _auth = StreamController<void>.broadcast();
  String? _phone;
  bool _mfa = false;
  DateTime? _reminder;
  final _resolved = <String>{};
  final _reviewed = <String>{};
  final Map<String, ({bool? valid, String? message, DateTime? at})> _validated = {};

  @override
  Stream<void> authChanges() => _auth.stream;
  @override
  String? get identity => formatIdentity(_phone, null);

  @override
  Future<StaffAccess> access() async =>
      _phone == null ? StaffAccess.signedOut : (_mfa ? StaffAccess.admin : StaffAccess.needsMfa);

  @override
  Future<void> sendPhoneCode(String phone) async {
    normalizeIndianPhone(phone);
  }

  @override
  Future<void> verifyPhoneCode(String phone, String code) async {
    if (code.trim().length != 6) throw const AdminException('Enter the 6-digit code.');
    _phone = normalizeIndianPhone(phone);
    _auth.add(null);
  }

  @override
  Future<bool> hasAuthenticator() async => true;

  @override
  Future<void> verifyAuthenticator(String code) async {
    if (code.trim().length != 6) throw const AdminException('Enter the 6-digit code from your authenticator.');
    _mfa = true;
    _auth.add(null);
  }

  @override
  Future<void> signOut() async {
    _phone = null;
    _mfa = false;
    _auth.add(null);
  }

  @override
  Future<SchemaStatus> schemaStatus() async => SchemaStatus(
    changeLog: [
      for (final m in repoMigrations)
        AppliedMigration(
          id: m.id,
          description: m.description,
          status: 'applied',
          tables: [
            for (final t in m.tables.split(',').map((t) => t.trim()))
              if (t.isNotEmpty) t,
          ],
          appliedAt: DateTime(2026, 11, 7).add(Duration(days: repoMigrations.indexOf(m))),
        ),
    ],
  );

  @override
  Future<List<TableCount>> dataSnapshot() async => const [
    TableCount('profiles', 1284, 'a41f…'),
    TableCount('profile_private', 1284, '9c02…'),
    TableCount('swipes_and_requests', 18342, '77de…'),
    TableCount('messages', 52910, '3b8a…'),
    TableCount('media_objects', 5410, 'e0c1…'),
    TableCount('user_consents', 5136, '12f9…'),
    TableCount('reports', 37, '5d6e…'),
    TableCount('profiles_premium', 212, 'c3b7…'),
  ];

  @override
  Future<List<RequirementStats>> requirementStats() async => [
    RequirementStats(
      key: 'occupation',
      label: 'Profession',
      level: 'optional',
      introducedBy: '20261114000000_data_completion',
      active: true,
      affectedAtIntro: 486,
      createdAt: DateTime(2026, 11, 14),
      reminderSentAt: _reminder,
      usersTotal: 1240,
      pending: 301,
      completed: 939,
      dismissed: 44,
      prompted: 470,
    ),
  ];

  @override
  Future<void> sendReminder(String key) async => _reminder = DateTime.now();

  @override
  Future<List<IntegrationStatus>> integrations({String? validate}) async {
    if (validate != null) {
      _validated[validate] = switch (validate) {
        'spotify' => (valid: true, message: 'Spotify accepted the client ID and secret.', at: DateTime.now()),
        'media_keys' => (valid: true, message: 'Active key encrypts and decrypts correctly.', at: DateTime.now()),
        _ => (valid: false, message: 'Not configured: GOOGLE_VISION_API_KEY.', at: DateTime.now()),
      };
    }
    IntegrationStatus s(String id, String label, bool req, List<String> missing, String setup) => IntegrationStatus(
      service: id,
      label: label,
      required: req,
      configured: missing.isEmpty,
      missing: missing,
      setup: setup,
      valid: _validated[id]?.valid,
      message: _validated[id]?.message,
      validatedAt: _validated[id]?.at,
    );
    return [
      s('supabase', 'Supabase (service access)', true, const [], 'Provided automatically to edge functions by Supabase.'),
      s('media_keys', 'Photo encryption keys', true, const [], 'supabase secrets set MEDIA_KEKS=... MEDIA_KEK_ACTIVE=...'),
      s(
        'spotify',
        'Spotify',
        false,
        const [],
        'Spotify dashboard → Basic Information; supabase secrets set SPOTIFY_CLIENT_ID=...',
      ),
      s('revenuecat', 'RevenueCat webhook (Fast-Track)', false, const [], 'supabase secrets set REVENUECAT_WEBHOOK_AUTH=...'),
      s('moderation', 'Image moderation (Google Vision)', false, const [
        'GOOGLE_VISION_API_KEY',
      ], 'Google Cloud → Vision API key; supabase secrets set GOOGLE_VISION_API_KEY=...'),
      s('cors', 'Allowed web origins', false, const [
        'ALLOWED_ORIGINS',
      ], 'supabase secrets set ALLOWED_ORIGINS=https://your-admin-host'),
    ];
  }

  @override
  Future<Map<String, dynamic>> securityOverview() async => {
    'open_reports': 3 - _resolved.length,
    'pending_media': 2 - _reviewed.where((r) => r.startsWith('m')).length,
    'events_24h': {'login_failed': 14, 'rate_limited': 3, 'contact_info_blocked': 9},
  };

  @override
  Future<List<ReportItem>> openReports() async => [
    for (final (i, r) in const ['spam_or_scam', 'harassment', 'fake_profile'].indexed)
      if (!_resolved.contains('r$i'))
        ReportItem(
          id: 'r$i',
          reportedId: '7f3a9c1e-0000-4000-8000-00000000000$i',
          reason: r,
          hasEvidence: i == 1,
          reportCount: i + 1,
          createdAt: DateTime.now().subtract(Duration(hours: 3 * (i + 1))),
        ),
  ];

  @override
  Future<Map<String, dynamic>> openReportEvidence(String reportId, String reason) async => {
    'details': 'Sample report text.',
    'evidence': {
      'messages': ['(sample) shared by the reporter'],
    },
  };

  @override
  Future<void> resolveReport(String reportId, {required bool actioned, required String resolution}) async =>
      _resolved.add(reportId);

  @override
  Map<String, String> get mediaHeaders => const {};

  @override
  Future<List<MediaItem>> pendingMedia() async => [
    for (final id in const ['m1', 'm2'])
      if (!_reviewed.contains(id)) MediaItem(id: id, ownerId: 'sample-user', kind: 'photo', url: ''),
  ];

  @override
  Future<void> reviewMedia(String id, {required bool approve}) async => _reviewed.add(id);

  @override
  Future<List<VerificationQueueItem>> verificationQueue() async => [
    if (!_reviewed.contains('v1'))
      VerificationQueueItem(
        requestId: 'v1',
        userId: 'sample-user',
        name: 'Sample user',
        pose: 'Touch your nose with your right index finger',
        submittedAt: DateTime.now().subtract(const Duration(minutes: 40)),
      ),
  ];

  @override
  Future<void> reviewVerification(String requestId, {required bool approve}) async => _reviewed.add(requestId);
}
