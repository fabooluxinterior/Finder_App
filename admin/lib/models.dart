/// A migration file in the repository (generated list).
class RepoMigration {
  const RepoMigration({
    required this.id,
    required this.description,
    this.tables = '',
    this.columns = '',
    this.compat = '',
    this.recovery = '',
    this.userData = '',
  });
  final String id;
  final String description;
  final String tables;
  final String columns;
  final String compat;
  final String recovery;
  final String userData;
}

/// A row of public.schema_change_log (applied migrations).
class AppliedMigration {
  const AppliedMigration({
    required this.id,
    required this.description,
    required this.status,
    this.tables = const [],
    this.columnsAdded = const [],
    this.error,
    this.appliedAt,
  });
  final String id;
  final String description;
  final String status;
  final List<String> tables;
  final List<String> columnsAdded;
  final String? error;
  final DateTime? appliedAt;

  factory AppliedMigration.fromJson(Map<String, dynamic> m) => AppliedMigration(
    id: m['migration_id'] as String,
    description: (m['description'] as String?) ?? '',
    status: (m['status'] as String?) ?? 'applied',
    tables: ((m['tables'] as List?) ?? const []).cast<String>(),
    columnsAdded: ((m['columns_added'] as List?) ?? const []).cast<String>(),
    error: m['error'] as String?,
    appliedAt: DateTime.tryParse((m['applied_at'] as String?) ?? '')?.toLocal(),
  );
}

class SchemaStatus {
  const SchemaStatus({required this.changeLog, this.appliedVersions});
  final List<AppliedMigration> changeLog;

  /// Versions recorded by the Supabase CLI (supabase_migrations), if visible.
  final List<String>? appliedVersions;

  bool isApplied(String migrationId) {
    final version = migrationId.split('_').first;
    return changeLog.any((m) => m.id == migrationId) || (appliedVersions?.contains(version) ?? false);
  }
}

class TableCount {
  const TableCount(this.table, this.rows, this.checksum);
  final String table;
  final int rows;
  final String checksum;
}

class RequirementStats {
  const RequirementStats({
    required this.key,
    required this.label,
    required this.level,
    required this.introducedBy,
    required this.active,
    required this.usersTotal,
    required this.pending,
    required this.completed,
    required this.dismissed,
    required this.prompted,
    this.gatedFeature,
    this.affectedAtIntro,
    this.reminderSentAt,
    this.createdAt,
  });
  final String key;
  final String label;
  final String level;
  final String? gatedFeature;
  final String introducedBy;
  final bool active;
  final int? affectedAtIntro;
  final DateTime? reminderSentAt;
  final DateTime? createdAt;
  final int usersTotal;
  final int pending;
  final int completed;
  final int dismissed;
  final int prompted;

  double get completion => usersTotal == 0 ? 1 : completed / usersTotal;

  factory RequirementStats.fromJson(Map<String, dynamic> m) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    DateTime? d(String k) => DateTime.tryParse((m[k] as String?) ?? '')?.toLocal();
    return RequirementStats(
      key: m['key'] as String,
      label: m['label'] as String,
      level: m['level'] as String,
      gatedFeature: m['gated_feature'] as String?,
      introducedBy: (m['introduced_by'] as String?) ?? '',
      active: (m['active'] as bool?) ?? true,
      affectedAtIntro: (m['affected_at_intro'] as num?)?.toInt(),
      reminderSentAt: d('reminder_sent_at'),
      createdAt: d('created_at'),
      usersTotal: n('users_total'),
      pending: n('pending'),
      completed: n('completed'),
      dismissed: n('dismissed'),
      prompted: n('prompted'),
    );
  }
}

class IntegrationStatus {
  const IntegrationStatus({
    required this.service,
    required this.label,
    required this.required,
    required this.configured,
    required this.missing,
    required this.setup,
    this.valid,
    this.message,
    this.validatedAt,
  });
  final String service;
  final String label;
  final bool required;
  final bool configured;
  final List<String> missing;
  final String setup;
  final bool? valid;
  final String? message;
  final DateTime? validatedAt;

  factory IntegrationStatus.fromJson(Map<String, dynamic> m) => IntegrationStatus(
    service: m['service'] as String,
    label: (m['label'] as String?) ?? m['service'] as String,
    required: (m['required'] as bool?) ?? false,
    configured: (m['configured'] as bool?) ?? false,
    missing: ((m['missing'] as List?) ?? const []).cast<String>(),
    setup: (m['setup'] as String?) ?? '',
    valid: m['valid'] as bool?,
    message: m['message'] as String?,
    validatedAt: DateTime.tryParse((m['validated_at'] as String?) ?? '')?.toLocal(),
  );
}

class ReportItem {
  const ReportItem({
    required this.id,
    required this.reportedId,
    required this.reason,
    required this.hasEvidence,
    required this.reportCount,
    required this.createdAt,
  });
  final String id;
  final String reportedId;
  final String reason;
  final bool hasEvidence;
  final int reportCount;
  final DateTime createdAt;
}

class MediaItem {
  const MediaItem({required this.id, required this.ownerId, required this.kind, required this.url});
  final String id;
  final String ownerId;
  final String kind;
  final String url;
}

class VerificationQueueItem {
  const VerificationQueueItem({
    required this.requestId,
    required this.userId,
    required this.name,
    required this.pose,
    required this.submittedAt,
    this.selfieUrl,
    this.profileUrl,
  });
  final String requestId;
  final String userId;
  final String name;
  final String pose;
  final String? selfieUrl;
  final String? profileUrl;
  final DateTime submittedAt;
}

/// Who is signed in, and whether they may use the admin app.
enum StaffAccess { signedOut, needsMfa, noAccess, moderator, admin }
