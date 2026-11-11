import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Everything the admin web app reads or does. Every call is authorised by the
/// database (staff role + MFA session); the app holds no secrets.
abstract class AdminApi {
  bool get isDemo => false;

  // Session
  Stream<void> authChanges();
  String? get email;
  Future<StaffAccess> access();
  Future<void> sendEmailCode(String email);
  Future<void> verifyEmailCode(String email, String code);

  /// Two-step verification: true if the account has an authenticator set up.
  Future<bool> hasAuthenticator();
  Future<void> verifyAuthenticator(String code);
  Future<void> signOut();

  // Settings → Database & Data Migration
  Future<SchemaStatus> schemaStatus();
  Future<List<TableCount>> dataSnapshot();
  Future<List<RequirementStats>> requirementStats();
  Future<void> sendReminder(String key);

  // Settings → Integrations & credentials
  Future<List<IntegrationStatus>> integrations({String? validate});

  // Safety
  Future<Map<String, dynamic>> securityOverview();
  Future<List<ReportItem>> openReports();
  Future<Map<String, dynamic>> openReportEvidence(String reportId, String reason);
  Future<void> resolveReport(String reportId, {required bool actioned, required String resolution});
  Future<List<MediaItem>> pendingMedia();
  Future<void> reviewMedia(String id, {required bool approve});
  Future<List<VerificationQueueItem>> verificationQueue();
  Future<void> reviewVerification(String requestId, {required bool approve});
  Map<String, String> get mediaHeaders;
}

class AdminException implements Exception {
  const AdminException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SupabaseAdminApi extends AdminApi {
  SupabaseAdminApi(this.url);
  final String url;
  SupabaseClient get _db => Supabase.instance.client;

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      throw AdminException(e.code == '42501' ? 'Not allowed. Admins need two-step verification.' : e.message);
    } on AuthException catch (e) {
      throw AdminException(e.message);
    } on FunctionException catch (e) {
      final d = e.details;
      throw AdminException(d is Map && d['message'] is String ? d['message'] as String : 'Request failed (${e.status}).');
    }
  }

  @override
  Stream<void> authChanges() => _db.auth.onAuthStateChange.map((_) {});

  @override
  String? get email => _db.auth.currentUser?.email;

  @override
  Future<StaffAccess> access() async {
    if (_db.auth.currentSession == null) return StaffAccess.signedOut;
    final role = await _guard(() async => await _db.rpc('my_staff_role') as String?);
    if (role == null) return StaffAccess.noAccess;
    final aal = _db.auth.mfa.getAuthenticatorAssuranceLevel();
    if (aal.currentLevel != AuthenticatorAssuranceLevels.aal2) return StaffAccess.needsMfa;
    return role == 'admin' ? StaffAccess.admin : StaffAccess.moderator;
  }

  @override
  Future<void> sendEmailCode(String email) => _guard(() => _db.auth.signInWithOtp(email: email.trim(), shouldCreateUser: false));

  @override
  Future<void> verifyEmailCode(String email, String code) =>
      _guard(() => _db.auth.verifyOTP(email: email.trim(), token: code.trim(), type: OtpType.email));

  @override
  Future<bool> hasAuthenticator() => _guard(() async {
    final f = await _db.auth.mfa.listFactors();
    return f.totp.any((x) => x.status == FactorStatus.verified);
  });

  @override
  Future<void> verifyAuthenticator(String code) => _guard(() async {
    final f = await _db.auth.mfa.listFactors();
    final factor = f.totp.firstWhere(
      (x) => x.status == FactorStatus.verified,
      orElse: () => throw const AdminException('Set up an authenticator in the Vouby app first.'),
    );
    await _db.auth.mfa.challengeAndVerify(factorId: factor.id, code: code.trim());
  });

  @override
  Future<void> signOut() => _db.auth.signOut();

  @override
  Future<SchemaStatus> schemaStatus() => _guard(() async {
    final m = (await _db.rpc('admin_schema_status') as Map).cast<String, dynamic>();
    return SchemaStatus(
      changeLog: [
        for (final r in (m['change_log'] as List? ?? const [])) AppliedMigration.fromJson((r as Map).cast<String, dynamic>()),
      ],
      appliedVersions: (m['applied_versions'] as List?)?.cast<String>(),
    );
  });

  @override
  Future<List<TableCount>> dataSnapshot() => _guard(() async {
    final rows = await _db.rpc('admin_data_snapshot') as List;
    return [
      for (final r in rows.cast<Map>())
        TableCount(r['table_name'] as String, (r['row_count'] as num).toInt(), r['key_checksum'] as String),
    ];
  });

  @override
  Future<List<RequirementStats>> requirementStats() => _guard(() async {
    final rows = await _db.rpc('admin_requirement_stats') as List;
    return [for (final r in rows) RequirementStats.fromJson((r as Map).cast<String, dynamic>())];
  });

  @override
  Future<void> sendReminder(String key) => _guard(() => _db.rpc('admin_remind_requirement', params: {'p_key': key}));

  @override
  Future<List<IntegrationStatus>> integrations({String? validate}) => _guard(() async {
    final res = await _db.functions.invoke(
      'admin-config-status',
      body: validate == null ? {'action': 'status'} : {'action': 'validate', 'service': validate},
    );
    final services = ((res.data as Map)['services'] as List).cast<Map>();
    return [for (final s in services) IntegrationStatus.fromJson(s.cast<String, dynamic>())];
  });

  @override
  Future<Map<String, dynamic>> securityOverview() =>
      _guard(() async => (await _db.rpc('admin_security_overview') as Map).cast<String, dynamic>());

  @override
  Future<List<ReportItem>> openReports() => _guard(() async {
    final rows = (await _db.rpc('mod_list_reports', params: {'p_status': 'open'}) as List).cast<Map>();
    return [
      for (final r in rows)
        ReportItem(
          id: r['id'] as String,
          reportedId: r['reported_id'] as String,
          reason: r['reason'] as String,
          hasEvidence: r['has_evidence'] as bool,
          reportCount: (r['report_count'] as num).toInt(),
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        ),
    ];
  });

  @override
  Future<Map<String, dynamic>> openReportEvidence(String reportId, String reason) => _guard(() async {
    final rows = await _db.rpc('mod_open_report', params: {'p_report': reportId, 'p_reason': reason}) as List;
    return (rows.first as Map).cast<String, dynamic>();
  });

  @override
  Future<void> resolveReport(String reportId, {required bool actioned, required String resolution}) => _guard(
    () => _db.rpc(
      'mod_resolve_report',
      params: {'p_report': reportId, 'p_status': actioned ? 'actioned' : 'dismissed', 'p_resolution': resolution},
    ),
  );

  String _media(String id) => '$url/functions/v1/media/$id';

  @override
  Map<String, String> get mediaHeaders => {'Authorization': 'Bearer ${_db.auth.currentSession?.accessToken ?? ''}'};

  @override
  Future<List<MediaItem>> pendingMedia() => _guard(() async {
    final rows = (await _db.rpc('mod_pending_media') as List).cast<Map>();
    return [
      for (final r in rows)
        MediaItem(
          id: r['id'] as String,
          ownerId: r['owner_id'] as String,
          kind: r['kind'] as String,
          url: _media(r['id'] as String),
        ),
    ];
  });

  @override
  Future<void> reviewMedia(String id, {required bool approve}) =>
      _guard(() => _db.rpc('mod_review_media', params: {'p_media': id, 'p_approve': approve}));

  @override
  Future<List<VerificationQueueItem>> verificationQueue() => _guard(() async {
    final rows = (await _db.rpc('mod_verification_queue') as List).cast<Map>();
    return [
      for (final r in rows)
        VerificationQueueItem(
          requestId: r['request_id'] as String,
          userId: r['user_id'] as String,
          name: r['full_name'] as String,
          pose: r['pose'] as String,
          selfieUrl: r['selfie_media'] == null ? null : _media(r['selfie_media'] as String),
          profileUrl: r['profile_media'] == null ? null : _media(r['profile_media'] as String),
          submittedAt: DateTime.parse(r['submitted_at'] as String).toLocal(),
        ),
    ];
  });

  @override
  Future<void> reviewVerification(String requestId, {required bool approve}) =>
      _guard(() => _db.rpc('mod_review_verification', params: {'p_request': requestId, 'p_approve': approve}));
}
