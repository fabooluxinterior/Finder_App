/// Account status as the server reports it.
enum AccountStatus {
  active,
  restricted,
  suspended,
  deactivated,
  banned,
  removalPending;

  static AccountStatus parse(String? s) => switch (s) {
    'restricted' => restricted,
    'suspended' => suspended,
    'deactivated' => deactivated,
    'banned' => banned,
    'removal_pending' => removalPending,
    _ => active,
  };

  String get label => switch (this) {
    active => 'Active',
    restricted => 'Restricted',
    suspended => 'Suspended',
    deactivated => 'Deactivated',
    banned => 'Banned',
    removalPending => 'Removal pending',
  };

  bool get isLimited => this != active;
}

class Overview {
  const Overview(this.m);
  final Map<String, dynamic> m;
  int n(String k) => (m[k] as num?)?.toInt() ?? 0;
}

class UserRow {
  const UserRow({
    required this.id,
    required this.name,
    required this.age,
    required this.city,
    required this.gender,
    required this.verified,
    required this.createdAt,
    required this.status,
    required this.reportsAgainst,
  });
  final String id;
  final String name;
  final int? age;
  final String? city;
  final String? gender;
  final bool verified;
  final DateTime createdAt;
  final AccountStatus status;
  final int reportsAgainst;

  factory UserRow.fromJson(Map<String, dynamic> r) => UserRow(
    id: r['id'] as String,
    name: (r['full_name'] as String?) ?? 'Unnamed',
    age: (r['age'] as num?)?.toInt(),
    city: r['city'] as String?,
    gender: r['gender'] as String?,
    verified: (r['is_verified'] as bool?) ?? false,
    createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
    status: AccountStatus.parse(r['status'] as String?),
    reportsAgainst: (r['reports_against'] as num?)?.toInt() ?? 0,
  );
}

class UserDetail {
  const UserDetail(this.m);
  final Map<String, dynamic> m;
  String get id => m['id'] as String;
  String get name => (m['full_name'] as String?) ?? 'Unnamed';
  AccountStatus get status => AccountStatus.parse(m['status'] as String?);
  Map<String, dynamic> get history => ((m['history'] as Map?) ?? const {}).cast<String, dynamic>();
  List<Map<String, dynamic>> get reports => [
    for (final r in (m['reports'] as List? ?? const [])) (r as Map).cast<String, dynamic>(),
  ];
  List<Map<String, dynamic>> get restrictions => [
    for (final r in (history['restrictions'] as List? ?? const [])) (r as Map).cast<String, dynamic>(),
  ];
  List<Map<String, dynamic>> get actions => [
    for (final r in (history['actions'] as List? ?? const [])) (r as Map).cast<String, dynamic>(),
  ];
}

class ReportRow {
  const ReportRow({
    required this.id,
    required this.reportNo,
    required this.reporterId,
    required this.reportedId,
    required this.reason,
    required this.details,
    required this.evidenceFiles,
    required this.hasEvidence,
    required this.reportCount,
    required this.reporterFalseReports,
    required this.createdAt,
    required this.status,
    required this.decision,
  });
  final String id;
  final String? reportNo;
  final String reporterId;
  final String reportedId;
  final String reason;
  final String? details;
  final int evidenceFiles;
  final bool hasEvidence;
  final int reportCount;
  final int reporterFalseReports;
  final DateTime createdAt;
  final String status;
  final String? decision;

  factory ReportRow.fromJson(Map<String, dynamic> r) => ReportRow(
    id: r['id'] as String,
    reportNo: r['report_no'] as String?,
    reporterId: r['reporter_id'] as String,
    reportedId: r['reported_id'] as String,
    reason: r['reason'] as String,
    details: r['details'] as String?,
    evidenceFiles: (r['evidence_files'] as num?)?.toInt() ?? 0,
    hasEvidence: (r['has_evidence'] as bool?) ?? false,
    reportCount: (r['report_count'] as num?)?.toInt() ?? 1,
    reporterFalseReports: (r['reporter_false_reports'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
    status: (r['status'] as String?) ?? 'open',
    decision: r['decision'] as String?,
  );
}

class RestrictedRow {
  const RestrictedRow({
    required this.userId,
    required this.name,
    required this.status,
    required this.reason,
    required this.since,
    required this.until,
    required this.by,
    required this.reportNo,
    required this.removalDue,
  });
  final String userId;
  final String name;
  final AccountStatus status;
  final String? reason;
  final DateTime? since;
  final DateTime? until;
  final String? by;
  final String? reportNo;
  final DateTime? removalDue;

  factory RestrictedRow.fromJson(Map<String, dynamic> r) => RestrictedRow(
    userId: r['user_id'] as String,
    name: (r['full_name'] as String?) ?? 'Unnamed',
    status: AccountStatus.parse(r['status'] as String?),
    reason: r['reason'] as String?,
    since: _d(r['since']),
    until: _d(r['until']),
    by: r['by_email'] as String?,
    reportNo: r['report_no'] as String?,
    removalDue: _d(r['removal_due_at']),
  );
}

class AuditRow {
  const AuditRow({required this.at, required this.actor, required this.action, required this.target, required this.reason});
  final DateTime at;
  final String? actor;
  final String action;
  final String target;
  final String? reason;

  factory AuditRow.fromJson(Map<String, dynamic> r) => AuditRow(
    at: DateTime.parse(r['created_at'] as String).toLocal(),
    actor: r['actor_email'] as String?,
    action: r['action'] as String,
    target: '${r['target_type']} ${r['target_id']}',
    reason: r['reason'] as String?,
  );
}

class StaffRow {
  const StaffRow({required this.userId, required this.email, required this.role});
  final String userId;
  final String? email;
  final String role;
  factory StaffRow.fromJson(Map<String, dynamic> r) =>
      StaffRow(userId: r['user_id'] as String, email: r['email'] as String?, role: r['role'] as String);
}

DateTime? _d(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
