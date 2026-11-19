import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'models_mod.dart';

/// Everything the admin web app reads or does. Every call is authorised by the
/// database (staff role + MFA session); the app holds no secrets.
abstract class AdminApi {
  bool get isDemo => false;

  // Session
  Stream<void> authChanges();

  /// Who is signed in, for display ("+91 98765 43210").
  String? get identity;
  Future<StaffAccess> access();

  /// Staff sign in with their mobile number (the same SMS code as the Vouby
  /// app). Accounts must already exist; this never creates one.
  Future<void> sendPhoneCode(String phone);
  Future<void> verifyPhoneCode(String phone, String code);

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

  // Dashboard: overview, reports, users, restricted accounts, audit, staff
  Future<Overview> overview();
  Future<List<ReportRow>> reports({String status = 'open'});

  /// A decision on a report. [restriction]: warning, restricted, suspended, banned. [days]: null = no end date.
  Future<void> decideReport(String reportId, {required String decision, required String note, String? restriction, int? days});
  Future<List<UserRow>> searchUsers({String? query, String? status, int offset = 0});
  Future<UserDetail> userDetail(String id);

  /// warning, restricted, suspended, banned, deactivate, reactivate, remove, cancel_removal. Returns the new status.
  Future<AccountStatus> applyAction(String userId, String action, {required String note, int? days});
  Future<AccountStatus> unsuspend(String userId, {required String note});
  Future<List<RestrictedRow>> restricted({String? status});
  Future<List<AuditRow>> auditLog({int offset = 0});
  Future<List<StaffRow>> staff();

  Future<void> setStaff(String email, String? role);

  // Support tickets
  Future<Map<String, int>> ticketCounts();
  Future<List<TicketRow>> tickets({String? status, String? category, String? priority, String? query, String? assignedTo});
  Future<TicketDetail> ticketDetail(String ticketId);
  Future<void> replyTicket(String ticketId, String body);
  Future<void> addTicketNote(String ticketId, String body);
  Future<void> setTicketStatus(String ticketId, String status, {String? note});
  Future<void> setTicketPriority(String ticketId, String priority);
  Future<void> assignTicket(String ticketId, String? staffUserId);
  Future<void> escalateTicket(String ticketId, String note);
  Future<List<StaffPerson>> staffPeople();

  // Auto-reply management (admins)
  Future<BotOverview> botOverview();
  Future<void> botSaveSettings(BotSettings s);
  Future<void> botSaveReply({
    String? id,
    required String category,
    required String title,
    required List<String> keywords,
    required String answer,
    required bool active,
    int sort = 0,
  });
  Future<void> botDeleteReply(String id);
  Future<List<BotConversationRow>> botConversations();

  // Fun lines and calling (admins)
  Future<List<FunLine>> funLines();
  Future<void> saveFunLine({String? id, required String slot, required String text, required bool enabled, int sort = 0});
  Future<void> deleteFunLine(String id);
  Future<int> callDays();
  Future<void> setCallDays(int days);

  // Messaging → Notifications (admins only)
  Future<PushSendResult> sendPush({required String title, required String body, required String audience, String? phone});
  Future<List<PushCampaign>> pushCampaigns();
}

/// "98765 43210", "+91 98765-43210" or "919876543210" → "+919876543210".
/// Throws when it isn't a valid Indian mobile number (10 digits, starts 6-9).
String normalizeIndianPhone(String input) {
  var d = input.replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
  if (!RegExp(r'^[6-9]\d{9}$').hasMatch(d)) {
    throw const AdminException('Enter a valid 10-digit mobile number.');
  }
  return '+91$d';
}

/// What to show for the signed-in account.
String? formatIdentity(String? phone, String? email) {
  final d = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('91')) return '+91 ${d.substring(2, 7)} ${d.substring(7)}';
  if (d.isNotEmpty) return '+$d';
  return (email ?? '').isEmpty ? null : email;
}

/// Plain words for the sign-in errors people actually hit ("expired" usually means the wrong kind of code).
String friendlyAuthMessage(String? code, String fallback) => switch (code) {
  'otp_expired' =>
    'That code is wrong or has expired. Step 1 needs the code from the text message, not the authenticator app code. '
        'Tap “Use another number” and send a new code if it was more than a minute ago.',
  'mfa_verification_failed' =>
    'That authenticator code isn’t right. Use the current 6-digit code (it changes every 30 seconds) '
        'and make sure your phone’s date and time are set to automatic.',
  'mfa_challenge_expired' => 'That took too long. Enter the current code from your authenticator app and try again.',
  'over_sms_send_rate_limit' || 'over_request_rate_limit' => 'Too many tries. Wait a minute, then send a new code.',
  _ => fallback,
};

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
      throw AdminException(friendlyAuthMessage(e.code, e.message));
    } on FunctionException catch (e) {
      final d = e.details;
      throw AdminException(d is Map && d['message'] is String ? d['message'] as String : 'Request failed (${e.status}).');
    }
  }

  @override
  Stream<void> authChanges() => _db.auth.onAuthStateChange.map((_) {});

  @override
  String? get identity => formatIdentity(_db.auth.currentUser?.phone, _db.auth.currentUser?.email);

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
  Future<void> sendPhoneCode(String phone) =>
      _guard(() => _db.auth.signInWithOtp(phone: normalizeIndianPhone(phone), shouldCreateUser: false));

  @override
  Future<void> verifyPhoneCode(String phone, String code) =>
      _guard(() => _db.auth.verifyOTP(phone: normalizeIndianPhone(phone), token: code.trim(), type: OtpType.sms));

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
  Future<PushSendResult> sendPush({required String title, required String body, required String audience, String? phone}) =>
      _guard(() async {
        final res = await _db.functions.invoke(
          'push-send',
          body: {
            'title': title,
            'body': body,
            'audience': audience,
            'phone': ?phone == null ? null : normalizeIndianPhone(phone),
          },
        );
        final m = (res.data as Map).cast<String, dynamic>();
        return PushSendResult(
          recipients: (m['recipients'] as num?)?.toInt() ?? 0,
          delivered: (m['delivered'] as num?)?.toInt() ?? 0,
          failed: (m['failed'] as num?)?.toInt() ?? 0,
          pushConfigured: m['push_configured'] == true,
        );
      });

  @override
  Future<List<PushCampaign>> pushCampaigns() => _guard(() async {
    final rows = await _db.rpc('mod_list_push_campaigns') as List;
    return [for (final r in rows) PushCampaign.fromJson((r as Map).cast<String, dynamic>())];
  });

  @override
  Future<Overview> overview() => _guard(() async => Overview((await _db.rpc('mod_overview') as Map).cast<String, dynamic>()));

  List<Map<String, dynamic>> _rows(Object? v) => [for (final r in (v as List)) (r as Map).cast<String, dynamic>()];

  @override
  Future<List<ReportRow>> reports({String status = 'open'}) => _guard(() async {
    final rows = _rows(await _db.rpc('mod_list_reports_v2', params: {'p_status': status}));
    return [for (final r in rows) ReportRow.fromJson(r)];
  });

  @override
  Future<void> decideReport(String reportId, {required String decision, required String note, String? restriction, int? days}) =>
      _guard(
        () => _db.rpc(
          'mod_decide_report',
          params: {'p_report': reportId, 'p_decision': decision, 'p_note': note, 'p_restriction': restriction, 'p_days': days},
        ),
      );

  @override
  Future<List<UserRow>> searchUsers({String? query, String? status, int offset = 0}) => _guard(() async {
    final rows = _rows(
      await _db.rpc('mod_user_search', params: {'p_q': query, 'p_status': status, 'p_limit': 30, 'p_offset': offset}),
    );
    return [for (final r in rows) UserRow.fromJson(r)];
  });

  @override
  Future<UserDetail> userDetail(String id) =>
      _guard(() async => UserDetail((await _db.rpc('mod_user_detail', params: {'p_user': id}) as Map).cast<String, dynamic>()));

  @override
  Future<AccountStatus> applyAction(String userId, String action, {required String note, int? days}) => _guard(
    () async => AccountStatus.parse(
      await _db.rpc('mod_apply_action', params: {'p_user': userId, 'p_action': action, 'p_note': note, 'p_days': days})
          as String?,
    ),
  );

  @override
  Future<AccountStatus> unsuspend(String userId, {required String note}) => _guard(
    () async => AccountStatus.parse(await _db.rpc('mod_unsuspend_user', params: {'p_user': userId, 'p_note': note}) as String?),
  );

  @override
  Future<List<RestrictedRow>> restricted({String? status}) => _guard(() async {
    final rows = _rows(await _db.rpc('mod_list_restricted', params: {'p_kind': status}));
    return [for (final r in rows) RestrictedRow.fromJson(r)];
  });

  @override
  Future<List<AuditRow>> auditLog({int offset = 0}) => _guard(() async {
    final rows = _rows(await _db.rpc('mod_audit_log', params: {'p_limit': 50, 'p_offset': offset}));
    return [for (final r in rows) AuditRow.fromJson(r)];
  });

  @override
  Future<Map<String, int>> ticketCounts() => _guard(() async {
    final m = (await _db.rpc('mod_ticket_counts') as Map).cast<String, dynamic>();
    return {for (final e in m.entries) e.key: (e.value as num).toInt()};
  });

  @override
  Future<List<TicketRow>> tickets({String? status, String? category, String? priority, String? query, String? assignedTo}) =>
      _guard(() async {
        final rows = _rows(
          await _db.rpc(
            'mod_list_tickets_v3',
            params: {'p_status': status, 'p_category': category, 'p_priority': priority, 'p_q': query, 'p_assigned': assignedTo},
          ),
        );
        return [for (final r in rows) TicketRow.fromJson(r)];
      });

  @override
  Future<TicketDetail> ticketDetail(String ticketId) => _guard(
    () async => TicketDetail((await _db.rpc('mod_ticket_detail', params: {'p_ticket': ticketId}) as Map).cast<String, dynamic>()),
  );

  @override
  Future<void> replyTicket(String ticketId, String body) =>
      _guard(() => _db.rpc('mod_reply_ticket', params: {'p_ticket': ticketId, 'p_body': body}));

  @override
  Future<void> addTicketNote(String ticketId, String body) =>
      _guard(() => _db.rpc('mod_add_ticket_note', params: {'p_ticket': ticketId, 'p_body': body}));

  @override
  Future<void> setTicketStatus(String ticketId, String status, {String? note}) =>
      _guard(() => _db.rpc('mod_set_ticket_status_v2', params: {'p_ticket': ticketId, 'p_status': status, 'p_note': note}));

  @override
  Future<void> setTicketPriority(String ticketId, String priority) =>
      _guard(() => _db.rpc('mod_set_ticket_priority', params: {'p_ticket': ticketId, 'p_priority': priority}));

  @override
  Future<void> assignTicket(String ticketId, String? staffUserId) =>
      _guard(() => _db.rpc('mod_assign_ticket', params: {'p_ticket': ticketId, 'p_admin': staffUserId}));

  @override
  Future<void> escalateTicket(String ticketId, String note) =>
      _guard(() => _db.rpc('mod_escalate_ticket', params: {'p_ticket': ticketId, 'p_note': note}));

  @override
  Future<List<StaffPerson>> staffPeople() =>
      _guard(() async => [for (final r in _rows(await _db.rpc('mod_list_staff'))) StaffPerson.fromJson(r)]);

  @override
  Future<BotOverview> botOverview() => _guard(() async {
    final m = (await _db.rpc('admin_bot_overview') as Map).cast<String, dynamic>();
    return BotOverview(
      settings: BotSettings.fromJson((m['settings'] as Map).cast<String, dynamic>()),
      replies: [for (final r in (m['replies'] as List)) BotReply.fromJson((r as Map).cast<String, dynamic>())],
      conversations: (m['conversations'] as num).toInt(),
    );
  });

  @override
  Future<void> botSaveSettings(BotSettings s) => _guard(
    () => _db.rpc(
      'admin_bot_set_settings',
      params: {
        'p_enabled': s.enabled,
        'p_welcome': s.welcome,
        'p_fallback': s.fallback,
        'p_resolved_prompt': s.resolvedPrompt,
        'p_ticket_prompt': s.ticketPrompt,
        'p_quick_replies': s.quickReplies,
      },
    ),
  );

  @override
  Future<void> botSaveReply({
    String? id,
    required String category,
    required String title,
    required List<String> keywords,
    required String answer,
    required bool active,
    int sort = 0,
  }) => _guard(
    () => _db.rpc(
      'admin_bot_upsert_reply',
      params: {
        'p_id': id,
        'p_category': category,
        'p_title': title,
        'p_keywords': keywords,
        'p_answer': answer,
        'p_active': active,
        'p_sort': sort,
      },
    ),
  );

  @override
  Future<void> botDeleteReply(String id) => _guard(() => _db.rpc('admin_bot_delete_reply', params: {'p_id': id}));

  @override
  Future<List<FunLine>> funLines() =>
      _guard(() async => [for (final r in _rows(await _db.rpc('admin_fun_lines'))) FunLine.fromJson(r)]);

  @override
  Future<void> saveFunLine({String? id, required String slot, required String text, required bool enabled, int sort = 0}) =>
      _guard(
        () => _db.rpc(
          'admin_fun_line_save',
          params: {'p_id': id, 'p_slot': slot, 'p_text': text, 'p_enabled': enabled, 'p_sort': sort},
        ),
      );

  @override
  Future<void> deleteFunLine(String id) => _guard(() => _db.rpc('admin_fun_line_delete', params: {'p_id': id}));

  @override
  Future<int> callDays() => _guard(() async => ((await _db.rpc('call_unlock_days')) as num?)?.toInt() ?? 4);

  @override
  Future<void> setCallDays(int days) => _guard(() => _db.rpc('admin_set_call_days', params: {'p_days': days}));

  @override
  Future<List<BotConversationRow>> botConversations() =>
      _guard(() async => [for (final r in _rows(await _db.rpc('admin_bot_conversations'))) BotConversationRow.fromJson(r)]);

  @override
  Future<List<StaffRow>> staff() =>
      _guard(() async => [for (final r in _rows(await _db.rpc('admin_list_staff'))) StaffRow.fromJson(r)]);

  @override
  Future<void> setStaff(String email, String? role) =>
      _guard(() => _db.rpc('admin_set_staff', params: {'p_email': email, 'p_role': role}));

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
