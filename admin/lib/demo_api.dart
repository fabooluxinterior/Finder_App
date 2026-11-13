import 'dart:async';

import 'api.dart';
import 'generated/migrations.g.dart';
import 'models.dart';
import 'models_mod.dart';

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

  final _campaigns = <PushCampaign>[];

  @override
  Future<PushSendResult> sendPush({required String title, required String body, required String audience, String? phone}) async {
    if (audience == 'user') normalizeIndianPhone(phone ?? '');
    final n = switch (audience) {
      'all' => 120,
      'free' => 80,
      'plan' => 40,
      _ => 1,
    };
    _campaigns.insert(
      0,
      PushCampaign(
        id: 'c${_campaigns.length}',
        title: title,
        body: body,
        audience: audience,
        recipients: n,
        delivered: n,
        failed: 0,
        createdAt: DateTime.now(),
      ),
    );
    return PushSendResult(recipients: n, delivered: n, failed: 0, pushConfigured: true);
  }

  @override
  Future<List<PushCampaign>> pushCampaigns() async => List.unmodifiable(_campaigns);

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

  // ------------------------------------------------ dashboard sample data --
  static const _people = [
    ('Asha Menon', 27, 'Kochi', 'woman'),
    ('Rahul Nair', 29, 'Kozhikode', 'man'),
    ('Meera Pillai', 25, 'Thrissur', 'woman'),
    ('Arjun Das', 31, 'Kochi', 'man'),
    ('Nisha Joseph', 26, 'Kannur', 'woman'),
    ('Vishnu Raj', 28, 'Palakkad', 'man'),
  ];
  late final Map<String, AccountStatus> _status = {
    for (var i = 0; i < _people.length; i++)
      'u$i': const [
        AccountStatus.active,
        AccountStatus.suspended,
        AccountStatus.active,
        AccountStatus.restricted,
        AccountStatus.active,
        AccountStatus.deactivated,
      ][i],
  };
  final _reasons = <String, String>{'u1': 'Harassment in chats', 'u3': 'Spam links', 'u5': 'Requested by the user'};
  final _reportState = <String, String>{};
  final _audit = <AuditRow>[];
  final _staff = <StaffRow>[
    const StaffRow(userId: 's1', email: 'admin@vouby.example', role: 'admin'),
    const StaffRow(userId: 's2', email: 'mod@vouby.example', role: 'moderator'),
  ];

  void _log(String action, String target, String? reason) => _audit.insert(
    0,
    AuditRow(at: DateTime.now(), actor: 'admin@vouby.example', action: action, target: 'user $target', reason: reason),
  );

  @override
  Future<Overview> overview() async => Overview({
    'open_reports': _reports().where((r) => r.status == 'open').length,
    'suspended': _status.values.where((s) => s == AccountStatus.suspended || s == AccountStatus.deactivated).length,
    'restricted': _status.values.where((s) => s == AccountStatus.restricted).length,
    'banned': _status.values.where((s) => s == AccountStatus.banned).length,
    'removal_pending': _status.values.where((s) => s == AccountStatus.removalPending).length,
    'open_tickets': 2,
    'users_total': 1284,
    'users_today': 17,
    'actions_today': _audit.length,
  });

  List<ReportRow> _reports() => [
    for (final (i, r) in const ['spam_or_scam', 'harassment', 'fake_profile'].indexed)
      ReportRow(
        id: 'r$i',
        reportNo: 'RP-00${i + 1}',
        reporterId: 'u${(i + 2) % 6}',
        reportedId:
            'u${i == 0
                ? 3
                : i == 1
                ? 1
                : 4}',
        reason: r,
        details: i == 1 ? 'Kept sending unwanted messages after I said no.' : 'Looks fake.',
        evidenceFiles: i == 1 ? 2 : 0,
        hasEvidence: i == 1,
        reportCount: i + 1,
        reporterFalseReports: i == 2 ? 2 : 0,
        createdAt: DateTime.now().subtract(Duration(hours: 3 * (i + 1))),
        status: _reportState['r$i'] ?? 'open',
        decision: _reportState['r$i'],
      ),
  ];

  @override
  Future<List<ReportRow>> reports({String status = 'open'}) async => [
    for (final r in _reports())
      if (status == 'all' || (status == 'open' ? r.status == 'open' : r.status != 'open')) r,
  ];

  @override
  Future<void> decideReport(
    String reportId, {
    required String decision,
    required String note,
    String? restriction,
    int? days,
  }) async {
    if (note.trim().length < 3 && decision != 'review') throw const AdminException('Add a note explaining the decision');
    final r = _reports().firstWhere((x) => x.id == reportId);
    _reportState[reportId] = decision == 'review' ? 'open' : 'actioned';
    if (restriction != null && restriction != 'warning') {
      _status[r.reportedId] = AccountStatus.parse(restriction);
      _reasons[r.reportedId] = note;
    }
    _log('report_$decision', r.reportedId, note);
  }

  UserRow _row(String id) {
    final i = int.parse(id.substring(1));
    final p = _people[i];
    return UserRow(
      id: id,
      name: p.$1,
      age: p.$2,
      city: p.$3,
      gender: p.$4,
      verified: i.isEven,
      createdAt: DateTime.now().subtract(Duration(days: 3 + i * 9)),
      status: _status[id]!,
      reportsAgainst: i == 1 ? 3 : (i == 3 ? 1 : 0),
    );
  }

  @override
  Future<List<UserRow>> searchUsers({String? query, String? status, int offset = 0}) async {
    final q = (query ?? '').trim().toLowerCase();
    return [
      for (final id in _status.keys)
        if ((q.isEmpty || _row(id).name.toLowerCase().contains(q) || id == q) &&
            (status == null || status == 'all' || _row(id).status.name == status.replaceAll('_pending', 'Pending')))
          _row(id),
    ];
  }

  @override
  Future<UserDetail> userDetail(String id) async {
    final r = _row(id);
    return UserDetail({
      'id': id,
      'full_name': r.name,
      'age': r.age,
      'city': r.city,
      'gender': r.gender,
      'bio': 'Filter coffee and long walks by the sea.',
      'is_verified': r.verified,
      'created_at': r.createdAt.toIso8601String(),
      'photo_count': 4,
      'email': '${r.name.split(' ').first.toLowerCase()}@example.com',
      'phone': '+91 98•••• ${1000 + r.age!}',
      'status': switch (r.status) {
        AccountStatus.removalPending => 'removal_pending',
        _ => r.status.name,
      },
      'history': {
        'reports_against': r.reportsAgainst,
        'reports_upheld': r.reportsAgainst > 1 ? 1 : 0,
        'reports_made': 0,
        'false_reports_made': 0,
        'restrictions': [
          if (r.status.isLimited)
            {
              'kind': r.status.name,
              'reason': _reasons[id] ?? 'Reviewed by staff',
              'created_at': DateTime.now().toIso8601String(),
            },
        ],
        'actions': [
          for (final a in _audit.where((a) => a.target.endsWith(id)))
            {'decision': a.action, 'note': a.reason, 'created_at': a.at.toIso8601String()},
        ],
      },
      'reports': [
        for (final x in _reports())
          if (x.reportedId == id)
            {
              'id': x.id,
              'report_no': x.reportNo,
              'reason': x.reason,
              'status': x.status,
              'created_at': x.createdAt.toIso8601String(),
            },
      ],
    });
  }

  @override
  Future<AccountStatus> applyAction(String userId, String action, {required String note, int? days}) async {
    if (note.trim().length < 3) throw const AdminException('Add a note explaining the action');
    _status[userId] = switch (action) {
      'warning' => _status[userId]!,
      'restricted' => AccountStatus.restricted,
      'suspended' => AccountStatus.suspended,
      'banned' => AccountStatus.banned,
      'deactivate' => AccountStatus.deactivated,
      'remove' => AccountStatus.removalPending,
      _ => AccountStatus.active,
    };
    if (action != 'reactivate' && action != 'cancel_removal') _reasons[userId] = note;
    _log('user_$action', userId, note);
    return _status[userId]!;
  }

  @override
  Future<AccountStatus> unsuspend(String userId, {required String note}) async {
    if (note.trim().length < 3) throw const AdminException('Add a note explaining the action');
    if (_status[userId] == AccountStatus.removalPending) {
      throw const AdminException('Removal is pending: an admin must cancel it first');
    }
    _status[userId] = AccountStatus.active;
    _log('user_unsuspend', userId, note);
    return AccountStatus.active;
  }

  @override
  Future<List<RestrictedRow>> restricted({String? status}) async => [
    for (final e in _status.entries)
      if (e.value.isLimited && (status == null || status == 'all' || e.value.name == status))
        RestrictedRow(
          userId: e.key,
          name: _row(e.key).name,
          status: e.value,
          reason: _reasons[e.key],
          since: DateTime.now().subtract(const Duration(days: 2)),
          until: e.value == AccountStatus.suspended ? DateTime.now().add(const Duration(days: 5)) : null,
          by: 'mod@vouby.example',
          reportNo: e.key == 'u1' ? 'RP-002' : null,
          removalDue: e.value == AccountStatus.removalPending ? DateTime.now().add(const Duration(days: 30)) : null,
        ),
  ];

  @override
  Future<List<AuditRow>> auditLog({int offset = 0}) async => _audit;

  @override
  Future<List<StaffRow>> staff() async => _staff;

  @override
  Future<void> setStaff(String email, String? role) async {
    _staff.removeWhere((s) => s.email == email);
    if (role != null) _staff.add(StaffRow(userId: email, email: email, role: role));
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
