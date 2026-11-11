import 'dart:typed_data';

import '../models/access.dart';
import '../models/follow_request.dart';
import '../models/message.dart';
import '../models/moderation.dart';
import '../models/profile.dart';
import '../models/profile_update.dart';
import '../models/security.dart';
import '../models/suggestion.dart';
import '../models/support.dart';

enum OtpChannel { email, phone }

/// Partial profile update. Only the keys present are written; the server
/// validates every value (catalog options, lengths, no contact details).
class ProfilePatch {
  const ProfilePatch(this.fields);
  final Map<String, Object?> fields;

  ProfilePatch merge(ProfilePatch o) => ProfilePatch({...fields, ...o.fields});

  static const fullName = 'full_name';
  static const city = 'city';
  static const bio = 'bio';
  static const occupation = 'occupation';
  static const education = 'education';
  static const heightCm = 'height_cm';
  static const gender = 'gender';
  static const pronouns = 'pronouns';
  static const languages = 'languages';
  static const lifestyle = 'lifestyle_attributes';
  static const interestTags = 'interest_tags';
  static const prompts = 'prompts';
  static const onboardingStage = 'onboarding_stage';
  static const prefAgeMin = 'pref_age_min';
  static const prefAgeMax = 'pref_age_max';
  static const prefGenders = 'pref_genders';
}

enum MusicSyncResult { synced, cached, reauthRequired, disconnected }

/// Everything the UI needs from the server. Implemented by
/// [SupabaseBackend] (production) and [DemoBackend] (offline demo).
abstract class FinderBackend {
  String? get currentUserId;
  Stream<String?> authChanges();

  Future<void> sendOtp(OtpChannel channel, String target);
  Future<void> verifyOtp(OtpChannel channel, String target, String code);

  /// The account's contact email (for notifications only; not verified, not
  /// a sign-in method). Null until one is added.
  Future<String?> contactEmail();
  Future<void> setContactEmail(String email);
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

  // Onboarding & profile builder
  /// Stage 1: community standards acknowledgement (before the profile exists).
  Future<void> acknowledgeStandards(String version);

  /// Stage 2: creates the profile row (needs the DOB first).
  Future<void> createProfile({required String fullName, required String city, required ProfilePatch details});
  Future<void> updateProfile(ProfilePatch patch);

  /// Flags the profile live; throws listing what's missing.
  Future<void> completeOnboarding();

  /// The owner's photo slots in order (including uploads in review).
  Future<List<PhotoSlot>> photoSlots();

  /// Uploads an already-optimised photo (≤100 KB WebP) into the next free
  /// slot, or in place of [replaces]. The replaced photo is deleted.
  Future<ImageUploadStatus> uploadPhoto(Uint8List bytes, {required String mime, String? replaces});
  Future<void> removePhoto(String mediaId);
  Future<void> reorderPhotos(List<String> mediaIds);

  /// Full card for one profile, with shared artists/interests vs. the viewer.
  Future<PublicProfile> profileCard(String userId);

  /// Icebreaker: a reply anchored to one of their prompt answers, sent with a
  /// follow request (chat stays locked until they accept).
  Future<SwipeOutcome> replyToPrompt(String targetId, String promptId, String text);

  // Suggestions
  /// Personalised suggestions computed on the server. [section] is 'main'
  /// ("People you might like") or 'you_may_like'. People already shown today
  /// come back first (a refresh never spends the daily allowance); [exclude]
  /// skips people already on screen when loading more.
  Future<List<Suggestion>> suggestions({String section = 'main', int limit = 10, List<String> exclude = const []});
  Future<SuggestionStatus> suggestionStatus();

  // Profile updates (details introduced after launch; only missing ones)
  Future<List<ProfileUpdate>> profileUpdates();

  /// Records that the prompt was shown (the server spaces prompts 7 days apart).
  Future<void> markProfileUpdateSeen(String key);

  /// Stops asking for an optional detail.
  Future<void> dismissProfileUpdate(String key);

  // Music connector (Spotify)
  Future<MusicState> musicState();

  /// Spotify consent page to open in the browser.
  Future<Uri> musicAuthorizeUrl();

  /// Re-imports top artists at most every 12 h (or when [force]d).
  Future<MusicSyncResult> syncMusic({bool force = false});
  Future<void> setArtistVisibility(String artistId, {required bool visible});

  /// Show or hide a whole section on the profile: 'top_tracks' or 'recent'.
  Future<void> setMusicSectionVisibility(String section, {required bool visible});
  Future<void> disconnectMusic();

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

  /// Sends a photo, end-to-end encrypted on this device (already compressed
  /// to WebP by the image optimizer). Needs chat access (Fast-Track or trial).
  Future<void> sendImage(String peerId, Uint8List webp, {required int width, required int height});

  /// Downloads and decrypts a photo message.
  Future<Uint8List> imageBytes(ChatMessage message);

  /// 60-digit number to compare in person; null when not available.
  Future<String?> safetyNumber(String peerId);

  // Safety
  Future<void> unmatch(String peerId);
  Future<void> blockUser(String peerId);

  /// [evidence] is decrypted on this device and shared only with explicit consent.
  Future<void> report(String peerId, ReportReason reason, {String? details, List<ChatMessage> evidence, bool block});

  /// Report with a content reference and only the evidence the user selected
  /// and confirmed. Returns the report number (e.g. R-7K3Q9P).
  Future<String> reportWithEvidence(
    String peerId,
    ReportReason reason, {
    String? details,
    String? contentRef,
    ReportEvidence evidence,
    bool block,
  });

  /// The user's own current restriction, if any.
  Future<AccountRestriction?> myRestriction();

  // Access: trial and subscription (decided on the server)
  Future<AccessStatus> accessStatus();
  Future<void> markAccessNoticeSeen(String kind);
  Future<List<AppNotification>> notifications();
  Future<void> markNotificationsRead();

  // Help & support
  /// Email registered on the account (shown prefilled; the server uses its own copy).
  Future<String?> supportEmail();
  Future<SupportTicket> submitSupportTicket({
    required SupportCategory category,
    required String subject,
    required String description,
    Uint8List? screenshotWebp,
  });
  Future<List<SupportTicket>> myTickets();

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
  Future<List<StaffReport>> staffReports({String status = 'open'});
  Future<void> decideReport(String reportId, ModDecision decision, {required String note, int? days});
  Future<Map<String, dynamic>> userModerationHistory(String userId);
  Future<List<EvidenceItem>> reportEvidenceFiles(String reportId);

  /// Short-lived signed URL for one evidence file or ticket screenshot (logged).
  Future<String> staffFileUrl({required String kind, required String id, String reason});
  Future<List<SupportTicket>> staffTickets({String status = 'open'});
  Future<void> setTicketStatus(String ticketId, TicketStatus status, {String? note});

  /// Fires when requests/connections change (realtime).
  Stream<void> socialChanges();

  /// Chat access from the server: paid Fast-Track (RevenueCat webhook) or
  /// an active trial.
  Future<bool> serverPremium();
}
