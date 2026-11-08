import 'dart:typed_data';

class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.createdAt,
    required this.lastActive,
    required this.userAgent,
    required this.isCurrent,
    required this.aal,
  });
  final String id;
  final DateTime createdAt;
  final DateTime? lastActive;
  final String? userAgent;
  final bool isCurrent;
  final String? aal;
}

class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.label,
    required this.platform,
    required this.createdAt,
    required this.lastSeen,
    required this.isThisDevice,
  });
  final String id;
  final String label;
  final String platform;
  final DateTime createdAt;
  final DateTime lastSeen;
  final bool isThisDevice;
}

class MfaState {
  const MfaState({required this.verifiedFactorIds, required this.sessionIsAal2, required this.needsChallenge});
  final List<String> verifiedFactorIds;
  final bool sessionIsAal2;

  /// Signed in with OTP but has MFA enrolled: must verify before using the app.
  final bool needsChallenge;
  bool get enrolled => verifiedFactorIds.isNotEmpty;
}

class TotpEnrollment {
  const TotpEnrollment({required this.factorId, required this.secret, required this.uri});
  final String factorId;
  final String secret;
  final String uri;
}

enum ReportReason { sexualContent, harassment, spamOrScam, fakeProfile, underage, maliciousLink, other }

extension ReportReasonX on ReportReason {
  String get wire => switch (this) {
    ReportReason.sexualContent => 'sexual_content',
    ReportReason.harassment => 'harassment',
    ReportReason.spamOrScam => 'spam_or_scam',
    ReportReason.fakeProfile => 'fake_profile',
    ReportReason.underage => 'underage',
    ReportReason.maliciousLink => 'malicious_link',
    ReportReason.other => 'other',
  };
  String get label => switch (this) {
    ReportReason.sexualContent => 'Sexual or explicit content',
    ReportReason.harassment => 'Harassment or threats',
    ReportReason.spamOrScam => 'Spam or scam',
    ReportReason.fakeProfile => 'Fake profile',
    ReportReason.underage => 'Appears under 18',
    ReportReason.maliciousLink => 'Malicious link',
    ReportReason.other => 'Something else',
  };
}

class ReportSummary {
  const ReportSummary({
    required this.id,
    required this.reportedId,
    required this.reason,
    required this.hasEvidence,
    required this.reportCount,
    required this.createdAt,
    required this.status,
  });
  final String id;
  final String reportedId;
  final String reason;
  final bool hasEvidence;
  final int reportCount;
  final DateTime createdAt;
  final String status;
}

class PendingMedia {
  const PendingMedia({required this.id, required this.ownerId, required this.kind, required this.url});
  final String id;
  final String ownerId;
  final String kind;
  final String url;
}

/// Decrypted voice-note bytes (production) or a local path/URL (demo).
class VoicePlayback {
  const VoicePlayback.bytes(Uint8List this.bytes) : url = null;
  const VoicePlayback.url(String this.url) : bytes = null;
  final Uint8List? bytes;
  final String? url;
}

enum ImageUploadStatus { approved, pending }

enum VerificationStatus { none, pending, approved, rejected }

class VerificationStart {
  const VerificationStart({required this.requestId, required this.pose});
  final String requestId;

  /// Server-chosen random pose the selfie must show.
  final String pose;
}

class VerificationItem {
  const VerificationItem({
    required this.requestId,
    required this.userId,
    required this.name,
    required this.pose,
    required this.selfieUrl,
    required this.profileUrl,
    required this.submittedAt,
  });
  final String requestId;
  final String userId;
  final String name;
  final String pose;
  final String? selfieUrl;
  final String? profileUrl;
  final DateTime submittedAt;
}
