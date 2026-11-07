import 'dart:typed_data';

import '../models/follow_request.dart';
import '../models/message.dart';
import '../models/profile.dart';

enum OtpChannel { email, phone }

class ProfileDraft {
  const ProfileDraft({
    required this.fullName,
    required this.age,
    required this.city,
    required this.bio,
    required this.interests,
    this.primaryPhotoWebp,
    this.newGalleryWebp = const [],
  });

  final String fullName;
  final int age;
  final String city;
  final String bio;
  final List<String> interests;

  /// Compressed WebP bytes; null keeps the current primary photo.
  final Uint8List? primaryPhotoWebp;

  /// Compressed WebP bytes appended to the locked gallery.
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

  Future<PublicProfile?> myProfile();
  Future<PrivateProfile> myPrivateProfile();
  Future<void> saveProfile(ProfileDraft draft);

  Future<List<PublicProfile>> fetchFeed();

  /// Remaining free follow requests in the rolling 24h window; -1 = unlimited.
  Future<int> remainingSwipes();
  Future<SwipeOutcome> swipe(String targetId, {required bool follow, String? directNote});

  Future<IncomingRequests> incomingRequests();
  Future<void> respondToRequest(String requestId, {required bool accept});
  Future<List<Connection>> connections();

  /// Locked gallery + interests; empty unless connected (enforced by RLS).
  Future<PrivateProfile> privateProfileOf(String userId);

  Stream<List<ChatMessage>> watchMessages(String peerId);
  Future<void> sendText(String peerId, String text);
  Future<void> sendVoice(String peerId, Uint8List aacBytes, {String? localPath});
  Future<void> markThreadRead(String peerId);
  Future<String> playableAudioUrl(ChatMessage message);

  /// Fires when requests/connections change (realtime).
  Stream<void> socialChanges();

  /// Server-side premium flag (set by the RevenueCat webhook).
  Future<bool> serverPremium();
}
