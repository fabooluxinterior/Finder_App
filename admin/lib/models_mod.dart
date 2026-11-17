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

class TicketRow {
  const TicketRow({
    required this.id,
    required this.ticketNo,
    required this.userId,
    required this.userName,
    required this.category,
    required this.subject,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
    this.assignedTo,
    this.assignee,
    this.messages = 0,
    this.rating,
  });
  final String id;
  final String ticketNo;
  final String? userId;
  final String? userName;
  final String category;
  final String subject;
  final String status;
  final String priority;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? assignedTo;
  final String? assignee;
  final int messages;
  final int? rating;

  factory TicketRow.fromJson(Map<String, dynamic> r) => TicketRow(
    id: r['id'] as String,
    ticketNo: r['ticket_no'] as String,
    userId: r['user_id'] as String?,
    userName: r['user_name'] as String?,
    category: r['category'] as String,
    subject: r['subject'] as String,
    status: r['status'] as String,
    priority: (r['priority'] as String?) ?? 'normal',
    createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(r['updated_at'] as String).toLocal(),
    assignedTo: r['assigned_to'] as String?,
    assignee: r['assignee'] as String?,
    messages: (r['messages'] as num?)?.toInt() ?? 0,
    rating: (r['rating'] as num?)?.toInt(),
  );
}

class TicketMsg {
  const TicketMsg({required this.fromStaff, required this.body, required this.at});
  final bool fromStaff;
  final String body;
  final DateTime at;
  factory TicketMsg.fromJson(Map<String, dynamic> r) => TicketMsg(
    fromStaff: (r['from_staff'] as bool?) ?? false,
    body: r['body'] as String,
    at: DateTime.parse((r['at'] ?? r['created_at']) as String).toLocal(),
  );
}

/// Everything staff see on one ticket (the person, thread, internal notes, history, the chatbot conversation).
class TicketDetail {
  const TicketDetail(this.m);
  final Map<String, dynamic> m;
  Map<String, dynamic> get ticket => (m['ticket'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get user => ((m['user'] as Map?) ?? const {}).cast<String, dynamic>();
  String? get assignee => m['assignee'] as String?;
  List<TicketMsg> get thread => [
    for (final x in (m['thread'] as List? ?? const [])) TicketMsg.fromJson((x as Map).cast<String, dynamic>()),
  ];
  List<Map<String, dynamic>> get notes => [for (final x in (m['notes'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
  List<Map<String, dynamic>> get history => [
    for (final x in (m['history'] as List? ?? const [])) (x as Map).cast<String, dynamic>(),
  ];
  List<Map<String, dynamic>> get bot => [for (final x in (m['bot'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
}

class StaffPerson {
  const StaffPerson({required this.userId, required this.email, required this.role});
  final String userId;
  final String? email;
  final String role;
  factory StaffPerson.fromJson(Map<String, dynamic> r) =>
      StaffPerson(userId: r['user_id'] as String, email: r['email'] as String?, role: r['role'] as String);
}

class BotSettings {
  const BotSettings({
    required this.enabled,
    required this.welcome,
    required this.fallback,
    required this.resolvedPrompt,
    required this.ticketPrompt,
    required this.quickReplies,
  });
  final bool enabled;
  final String welcome;
  final String fallback;
  final String resolvedPrompt;
  final String ticketPrompt;
  final List<String> quickReplies;
  factory BotSettings.fromJson(Map<String, dynamic> j) => BotSettings(
    enabled: (j['enabled'] as bool?) ?? true,
    welcome: j['welcome'] as String,
    fallback: j['fallback'] as String,
    resolvedPrompt: j['resolved_prompt'] as String,
    ticketPrompt: j['ticket_prompt'] as String,
    quickReplies: [for (final q in (j['quick_replies'] as List? ?? const [])) '$q'],
  );
}

class BotReply {
  const BotReply({
    required this.id,
    required this.category,
    required this.title,
    required this.keywords,
    required this.answer,
    required this.active,
    required this.sort,
  });
  final String id;
  final String category;
  final String title;
  final List<String> keywords;
  final String answer;
  final bool active;
  final int sort;
  factory BotReply.fromJson(Map<String, dynamic> j) => BotReply(
    id: j['id'] as String,
    category: j['category'] as String,
    title: j['title'] as String,
    keywords: [for (final k in (j['keywords'] as List? ?? const [])) '$k'],
    answer: j['answer'] as String,
    active: (j['active'] as bool?) ?? true,
    sort: (j['sort'] as num?)?.toInt() ?? 0,
  );
}

class BotOverview {
  const BotOverview({required this.settings, required this.replies, required this.conversations});
  final BotSettings settings;
  final List<BotReply> replies;
  final int conversations;
}

class BotConversationRow {
  const BotConversationRow({
    required this.id,
    required this.userName,
    required this.ticketNo,
    required this.updatedAt,
    required this.messages,
  });
  final String id;
  final String? userName;
  final String? ticketNo;
  final DateTime updatedAt;
  final List<Map<String, dynamic>> messages;
  factory BotConversationRow.fromJson(Map<String, dynamic> j) => BotConversationRow(
    id: j['id'] as String,
    userName: j['user_name'] as String?,
    ticketNo: j['ticket_no'] as String?,
    updatedAt: DateTime.parse(j['updated_at'] as String).toLocal(),
    messages: [for (final m in (j['messages'] as List? ?? const [])) (m as Map).cast<String, dynamic>()],
  );
}

/// How serious a report is, for ordering the queue (the server applies the same rule).
String reportPriority(String reason) => switch (reason) {
  'underage' || 'threats' => 'urgent',
  'harassment' ||
  'abusive_messages' ||
  'scam' ||
  'spam_or_scam' ||
  'impersonation' ||
  'privacy_violation' ||
  'sexual_content' ||
  'inappropriate_images' ||
  'malicious_link' => 'high',
  _ => 'normal',
};
