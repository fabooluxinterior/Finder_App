import 'dart:typed_data';

import '../models/follow_request.dart';
import '../models/message.dart';
import '../models/profile.dart';
import '../models/security.dart';

enum OtpChannel { email, phone }

class ProfileDraft {
  const ProfileDraft({
    required this.fullName,
    required this.city,
    required this.bio,
    required this.interests,
    this.primaryPhotoWebp,
    this.newGalleryWebp = const [],
  });

  final String fullName;
  final String city;
  final String bio;
  final List<String> interests;

  /// Client-compressed JPEG; the server validates, strips metadata,
  /// moderates, re-encodes to WebP and encrypts it. Null keeps the current one.
  final Uint8List? primaryPhotoWebp;

  /// Client-compressed JPEGs appended to the locked gallery (same pipeline).
  final List<Uint8List> newGalleryWebp;
}

/// Everything the UI needs from the server. Implemented by
/// [SupabaseBackend] (production) and [DemoBackend] (offline demo).
abstract class FinderBackend {
  String? get currentUserId;
  Stream<String?> authChanges();

  Future<void> sendOtp(OtpChannel channel, String target);
  Future<void> verifyOtp(OtpChannel channel, String target, String code);
  Future<void> signOut();

  // Consent & age
  /// Oldest accepted version across all policies; null if any is missing.
  Future<String?> acceptedPolicyVersion();
  Future<void> recordConsent(String version);
  Future<bool> hasDob();

  /// Stores the (locked) date of birth; returns the server-computed age.
  Future<int> setDob(DateTime dob);

  // Selfie verification
  Future<VerificationStatus> verificationStatus();
  Future<VerificationStart> startVerification();
  Future<void> submitVerificationSelfie(String requestId, Uint8List jpeg);

  Future<PublicProfile?> myProfile();
  Future<PrivateProfile> myPrivateProfile();

  /// Returns how many uploaded photos are held for manual review.
  Future<int> saveProfile(ProfileDraft draft);

  Future<List<PublicProfile>> fetchFeed();

  /// Requests are free for everyone; a mutual request is an instant match.
  Future<SwipeOutcome> swipe(String targetId, {required bool follow});

  Future<IncomingRequests> incomingRequests();
  Future<void> respondToRequest(String requestId, {required bool accept});
  Future<List<Connection>> connections();

  /// Locked gallery + interests; empty unless connected (enforced by RLS).
  Future<PrivateProfile> privateProfileOf(String userId);

  /// True when chats are end-to-end encrypted (false in offline demo mode).
  bool get isEndToEndEncrypted;

  Stream<List<ChatMessage>> watchMessages(String peerId);
  Future<void> sendText(String peerId, String text);
  Future<void> sendVoice(String peerId, Uint8List aacBytes, {String? localPath, Duration duration});
  Future<void> markThreadRead(String peerId);
  Future<VoicePlayback> voicePlayback(ChatMessage message);

  /// 60-digit number to compare in person; null when not available.
  Future<String?> safetyNumber(String peerId);

  // Safety
  Future<void> unmatch(String peerId);
  Future<void> blockUser(String peerId);

  /// [evidence] is decrypted on this device and shared only with explicit consent.
  Future<void> report(String peerId, ReportReason reason, {String? details, List<ChatMessage> evidence, bool block});

  // Account security
  Future<List<SessionInfo>> sessions();
  Future<void> revokeSession(String sessionId);
  Future<void> signOutOtherSessions();
  Future<List<DeviceInfo>> devices();
  Future<void> revokeDevice(String deviceId);
  Future<MfaState> mfaState();
  Future<TotpEnrollment> enrollTotp();
  Future<void> verifyTotp(String factorId, String code);
  Future<void> removeTotp(String factorId);
  Future<void> deleteAccount();

  // Staff (moderator / admin); every call is authorised server-side.
  Future<String?> staffRole();
  Future<Map<String, dynamic>> securityOverview();
  Future<List<ReportSummary>> openReports();
  Future<Map<String, dynamic>> openReportEvidence(String reportId, String accessReason);
  Future<void> resolveReport(String reportId, {required bool actioned, required String resolution});
  Future<List<PendingMedia>> pendingMedia();
  Future<void> reviewMedia(String mediaId, {required bool approve});
  Future<List<VerificationItem>> verificationQueue();
  Future<void> reviewVerification(String requestId, {required bool approve});

  /// Fires when requests/connections change (realtime).
  Stream<void> socialChanges();

  /// Server-side premium flag (set by the RevenueCat webhook).
  Future<bool> serverPremium();
}
