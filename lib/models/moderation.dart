import 'security.dart';

/// Staff decisions on a report (public.mod_decide_report).
enum ModDecision {
  review,
  verified,
  falseReport,
  dismissed,
  warningIssued,
  restricted,
  suspended,
  banned,
  contentRemoved,
  resolved,
}

extension ModDecisionX on ModDecision {
  String get wire => switch (this) {
    ModDecision.review => 'review',
    ModDecision.verified => 'verified',
    ModDecision.falseReport => 'false_report',
    ModDecision.dismissed => 'dismissed',
    ModDecision.warningIssued => 'warning_issued',
    ModDecision.restricted => 'restricted',
    ModDecision.suspended => 'suspended',
    ModDecision.banned => 'banned',
    ModDecision.contentRemoved => 'content_removed',
    ModDecision.resolved => 'resolved',
  };
  String get label => switch (this) {
    ModDecision.review => 'Under review',
    ModDecision.verified => 'Verified',
    ModDecision.falseReport => 'False report',
    ModDecision.dismissed => 'Dismissed',
    ModDecision.warningIssued => 'Warning issued',
    ModDecision.restricted => 'Restricted',
    ModDecision.suspended => 'Suspended',
    ModDecision.banned => 'Banned',
    ModDecision.contentRemoved => 'Content removed',
    ModDecision.resolved => 'Resolved',
  };

  /// The account restriction this decision applies (null: none).
  String? get restriction => switch (this) {
    ModDecision.warningIssued => 'warning',
    ModDecision.restricted => 'restricted',
    ModDecision.suspended => 'suspended',
    ModDecision.banned => 'banned',
    _ => null,
  };
  static ModDecision? fromWire(String? w) => ModDecision.values.where((d) => d.wire == w).firstOrNull;
}

class StaffReport {
  const StaffReport({
    required this.id,
    required this.reportNo,
    required this.reporterId,
    required this.reportedId,
    required this.reason,
    required this.createdAt,
    required this.status,
    this.details,
    this.contentRef,
    this.hasEvidence = false,
    this.evidenceFiles = 0,
    this.reportCount = 1,
    this.reporterFalseReports = 0,
    this.decision,
  });
  final String id;
  final String reportNo;
  final String reporterId;
  final String reportedId;
  final ReportReason reason;
  final String? details;
  final String? contentRef;
  final bool hasEvidence;
  final int evidenceFiles;
  final int reportCount;
  final int reporterFalseReports;
  final DateTime createdAt;
  final String status;
  final ModDecision? decision;

  factory StaffReport.fromJson(Map<String, dynamic> m) => StaffReport(
    id: m['id'] as String,
    reportNo: (m['report_no'] as String?) ?? '—',
    reporterId: m['reporter_id'] as String,
    reportedId: m['reported_id'] as String,
    reason: ReportReasonX.fromWire(m['reason'] as String),
    details: m['details'] as String?,
    contentRef: m['content_ref'] as String?,
    hasEvidence: (m['has_evidence'] as bool?) ?? false,
    evidenceFiles: (m['evidence_files'] as num?)?.toInt() ?? 0,
    reportCount: (m['report_count'] as num?)?.toInt() ?? 1,
    reporterFalseReports: (m['reporter_false_reports'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    status: m['status'] as String,
    decision: ModDecisionX.fromWire(m['decision'] as String?),
  );
}

class EvidenceItem {
  const EvidenceItem({required this.id, required this.kind, this.messageRef, required this.createdAt});
  final String id;
  final String kind;
  final String? messageRef;
  final DateTime createdAt;
}

/// What the reporter chose to share (built on their device, previewed and
/// confirmed before sending).
class ReportEvidence {
  const ReportEvidence({this.texts = const [], this.images = const []});

  /// Selected text messages: {id, from_me, at, text}.
  final List<Map<String, Object?>> texts;

  /// Selected photos, decrypted on the reporter's device: (message id, bytes).
  final List<(String, List<int>)> images;

  bool get isEmpty => texts.isEmpty && images.isEmpty;
}
