import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide OtpChannel;
import 'package:uuid/uuid.dart';

import '../core/config.dart';
import '../core/errors.dart';
import '../core/media_auth.dart';
import '../models/access.dart';
import '../models/follow_request.dart';
import '../models/message.dart';
import '../models/moderation.dart';
import '../models/profile.dart';
import '../models/profile_update.dart';
import '../models/security.dart';
import '../models/suggestion.dart';
import '../models/support.dart';
import '../security/e2ee_engine.dart';
import '../security/message_vault.dart';
import '../security/secure_kv.dart';
import 'backend.dart';
import 'supabase_key_directory.dart';

class SupabaseBackend implements FinderBackend {
  SupabaseBackend(this._db, {required SecureKv kv})
    : _kv = kv,
      _vault = MessageVault(kv),
      _engine = E2eeEngine(
        directory: SupabaseKeyDirectory(_db),
        kv: kv,
        platform: kIsWeb ? 'web' : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'),
        label: kIsWeb ? 'Web browser' : (defaultTargetPlatform == TargetPlatform.iOS ? 'iPhone' : 'Android phone'),
      ) {
    MediaAuth.baseUrl = '${AppConfig.supabaseUrl}/functions/v1/media/';
    MediaAuth.headers = () => {
      'Authorization': 'Bearer ${_db.auth.currentSession?.accessToken ?? ''}',
      'apikey': AppConfig.supabaseAnonKey,
    };
  }

  final SupabaseClient _db;
  final SecureKv _kv;
  final MessageVault _vault;
  final E2eeEngine _engine;
  static const _uuid = Uuid();

  String get _me {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw const AppException(AppErrorCode.unknown, 'Not signed in');
    return id;
  }

  @override
  String? get currentUserId => _db.auth.currentUser?.id;

  @override
  bool get isEndToEndEncrypted => true;

  @override
  Stream<String?> authChanges() async* {
    yield currentUserId;
    yield* _db.auth.onAuthStateChange.map((s) => s.session?.user.id).distinct();
  }

  static String _mediaUrl(String id) => '${AppConfig.supabaseUrl}/functions/v1/media/$id';

  // ---------------------------------------------------------------- auth ----

  @override
  Future<void> sendOtp(OtpChannel channel, String target) => _guard(() async {
    if (channel == OtpChannel.email) {
      await _db.auth.signInWithOtp(email: target, shouldCreateUser: true);
    } else {
      await _db.auth.signInWithOtp(phone: target, shouldCreateUser: true);
    }
  });

  @override
  Future<void> verifyOtp(OtpChannel channel, String target, String code) => _guard(() async {
    if (channel == OtpChannel.email) {
      await _db.auth.verifyOTP(email: target, token: code, type: OtpType.email);
    } else {
      await _db.auth.verifyOTP(phone: target, token: code, type: OtpType.sms);
    }
  });

  /// Secure logout: revoke this device's encryption identity, end the
  /// server session, and wipe keys plus decrypted history from this device.
  @override
  Future<void> signOut() async {
    try {
      await _ready();
      await _db.rpc('revoke_device', params: {'p_device': _engine.deviceId});
    } catch (_) {
      /* MFA-gated or offline: the device can still be removed later from another session */
    }
    await _stopInbox();
    await _db.auth.signOut();
    await _engine.wipe();
    await _kv.deleteAll();
    _readyFor = null;
  }

  // --------------------------------------------------------------- crypto ----

  String? _readyFor;
  Future<void>? _readying;

  /// Creates/loads this device's E2EE identity and starts the inbox.
  Future<void> _ready() {
    final me = _me;
    if (_readyFor == me) return Future.value();
    return _readying ??= () async {
      try {
        await _engine.ensureReady(me);
        _readyFor = me;
        await _startInbox();
      } finally {
        _readying = null;
      }
    }();
  }

  RealtimeChannel? _inbox;
  final _threads = <String, StreamController<List<ChatMessage>>>{};
  final _social = StreamController<void>.broadcast();
  Future<void> _draining = Future.value();

  Future<void> _startInbox() async {
    await _stopInbox();
    final me = _me;
    _inbox = _db.channel('inbox:${_engine.deviceId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'message_envelopes',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'recipient_device_id', value: _engine.deviceId),
        callback: (_) => _drain(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'sender_id', value: me),
        callback: (p) => _onReadReceipt(p.newRecord),
      )
      ..subscribe();
    unawaited(_drain());
  }

  Future<void> _stopInbox() async {
    if (_inbox != null) await _db.removeChannel(_inbox!);
    _inbox = null;
  }

  /// Fetches, decrypts, stores and acknowledges envelopes for this device.
  Future<void> _drain() => _draining = _draining
      .then((_) async {
        final me = _me;
        final rows = await _db
            .from('message_envelopes')
            .select(
              'message_id, message_type, ciphertext, messages!inner(id, sender_id, receiver_id, sender_device_id, created_at, is_read)',
            )
            .eq('recipient_device_id', _engine.deviceId)
            .order('created_at')
            .limit(100);
        if (rows.isEmpty) return;
        final acked = <String>[];
        final touched = <String>{};
        for (final r in rows) {
          final m = r['messages'] as Map<String, dynamic>;
          final sender = m['sender_id'] as String;
          final peer = sender == me ? m['receiver_id'] as String : sender;
          final createdAt = DateTime.parse(m['created_at'] as String).toLocal();
          ChatMessage msg;
          try {
            final plain = await _engine.decrypt(
              senderDeviceId: m['sender_device_id'] as String,
              type: (r['message_type'] as num).toInt(),
              ciphertext: r['ciphertext'] as String,
            );
            final p = SecurePayload.decode(plain);
            if (!await _vault.markSeen(me, sender, p.clientId)) {
              acked.add(r['message_id'] as String);
              continue; // duplicate / replayed payload
            }
            msg = ChatMessage(
              id: m['id'] as String,
              senderId: sender,
              receiverId: m['receiver_id'] as String,
              content: p.text,
              voice: p.voice,
              image: p.image,
              isRead: m['is_read'] as bool? ?? false,
              createdAt: createdAt,
            );
          } catch (_) {
            msg = ChatMessage(
              id: m['id'] as String,
              senderId: sender,
              receiverId: m['receiver_id'] as String,
              content: '⚠️ This message couldn’t be decrypted on this device.',
              isRead: true,
              createdAt: createdAt,
            );
          }
          final list = await _vault.upsert(me, peer, msg);
          _threads[peer]?.add(list);
          touched.add(peer);
          acked.add(r['message_id'] as String);
        }
        await _db.rpc('ack_envelopes', params: {'p_device': _engine.deviceId, 'p_message_ids': acked});
        _social.add(null);
        if (rows.length == 100) unawaited(_drain());
      })
      .catchError((_) {});

  Future<void> _onReadReceipt(Map<String, dynamic> row) async {
    if (row['is_read'] != true) return;
    final me = _me;
    final peer = row['receiver_id'] as String;
    final id = row['id'] as String;
    final list = await _vault.update(me, peer, (m) => m.id == id ? m.copyWith(isRead: true) : m);
    _threads[peer]?.add(list);
  }

  // ------------------------------------------------------------- profile ----

  @override
  Future<PublicProfile?> myProfile() => _guard(() async {
    final row = await _db.from('profiles').select().eq('id', _me).maybeSingle();
    if (row == null) return null;
    return PublicProfile.fromProfileRow(row, resolve: _mediaUrl);
  });

  @override
  Future<PrivateProfile> myPrivateProfile() => privateProfileOf(_me);

  @override
  Future<void> acknowledgeStandards(String version) =>
      _guard(() => _db.rpc('acknowledge_standards', params: {'p_version': version}));

  @override
  Future<void> createProfile({required String fullName, required String city, required ProfilePatch details}) => _guard(() async {
    final me = _me;
    final exists = await _db.from('profiles').select('id').eq('id', me).maybeSingle();
    final fields = {ProfilePatch.fullName: fullName, ProfilePatch.city: city, ...details.fields};
    if (exists == null) {
      // Age is computed server-side from the (locked) date of birth.
      await _db.from('profiles').insert({'id': me, ...fields});
    } else {
      await _db.from('profiles').update(fields).eq('id', me);
    }
    unawaited(_ready().catchError((_) {}));
  });

  @override
  Future<void> updateProfile(ProfilePatch patch) => _guard(() async {
    if (patch.fields.isEmpty) return;
    await _db.from('profiles').update(patch.fields).eq('id', _me);
  });

  @override
  Future<void> completeOnboarding() => _guard(() => _db.rpc('complete_onboarding'));

  @override
  Future<List<PhotoSlot>> photoSlots() => _guard(() async {
    final rows = (await _db.rpc('my_photo_slots') as List).cast<Map<String, dynamic>>();
    return [
      for (final r in rows)
        PhotoSlot(mediaId: r['media_id'] as String, url: _mediaUrl(r['media_id'] as String), pending: r['status'] == 'pending'),
    ];
  });

  @override
  Future<ImageUploadStatus> uploadPhoto(Uint8List bytes, {required String mime, String? replaces}) =>
      _guard(() => _uploadPhoto(bytes, 'photo', mime: mime, replaces: replaces));

  @override
  Future<void> removePhoto(String mediaId) => _guard(() async {
    try {
      // Deletes the stored object immediately (storage hygiene).
      await _db.functions.invoke('photo-remove', body: {'media_id': mediaId});
    } on FunctionException {
      throw const AppException(AppErrorCode.unknown, 'That photo couldn’t be removed. Try again.');
    }
  });

  @override
  Future<void> reorderPhotos(List<String> mediaIds) => _guard(() => _db.rpc('reorder_photos', params: {'p_order': mediaIds}));

  @override
  Future<PublicProfile> profileCard(String userId) => _guard(() async {
    final rows = (await _db.rpc('get_profile_card', params: {'p_id': userId}) as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) throw const AppException(AppErrorCode.notConnected, 'This profile isn’t available.');
    return PublicProfile.fromFeedRow(rows.first, resolve: _mediaUrl);
  });

  @override
  Future<SwipeOutcome> replyToPrompt(String targetId, String promptId, String text) => _guard(() async {
    final result =
        await _db.rpc('send_prompt_reply', params: {'p_receiver': targetId, 'p_prompt_id': promptId, 'p_text': text}) as String;
    if (result == 'matched') {
      // Already mutual: the reply becomes a real (end-to-end encrypted) message.
      try {
        await sendText(targetId, text);
      } catch (_) {}
      return SwipeOutcome.matched;
    }
    return SwipeOutcome.requested;
  });

  // --------------------------------------------------------- suggestions ----

  @override
  Future<List<Suggestion>> suggestions({String section = 'main', int limit = 10, List<String> exclude = const []}) =>
      _guard(() async {
        final rows = (await _db.rpc(
          'get_suggestions',
          params: {'p_section': section, 'p_limit': limit, 'p_exclude': exclude},
        ) as List).cast<Map<String, dynamic>>();
        return [
          for (final r in rows)
            Suggestion(
              profile: PublicProfile.fromFeedRow(r, resolve: _mediaUrl),
              compatibility: (r['compatibility'] as num).toInt(),
              reasons: ((r['reasons'] as List?) ?? const [])
                  .map((e) => SuggestionReason.fromJson((e as Map).cast<String, dynamic>()))
                  .toList(),
              section: r['section'] as String? ?? section,
            ),
        ];
      });

  @override
  Future<SuggestionStatus> suggestionStatus() => _guard(() async {
    final r = ((await _db.rpc('suggestion_status') as List).first as Map).cast<String, dynamic>();
    return SuggestionStatus(
      dailyLimit: (r['daily_limit'] as num).toInt(),
      shownToday: (r['shown_today'] as num).toInt(),
      remaining: (r['remaining'] as num).toInt(),
      resetsAt: r['resets_at'] == null ? null : DateTime.parse(r['resets_at'] as String).toLocal(),
    );
  });

  // ----------------------------------------------------- profile updates ----

  @override
  Future<List<ProfileUpdate>> profileUpdates() => _guard(() async {
    final rows = await _db.rpc('my_profile_updates') as List;
    return [for (final r in rows) ProfileUpdate.fromJson((r as Map).cast<String, dynamic>())];
  });

  @override
  Future<void> markProfileUpdateSeen(String key) =>
      _guard(() async => await _db.rpc('mark_profile_update_seen', params: {'p_key': key}));

  @override
  Future<void> dismissProfileUpdate(String key) =>
      _guard(() async => await _db.rpc('dismiss_profile_update', params: {'p_key': key}));

  // ------------------------------------------------------------- music ----

  @override
  Future<MusicState> musicState() => _guard(() async {
    final rows = (await _db.rpc('my_music') as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return MusicState.disconnected;
    final r = rows.first;
    return MusicState(
      status: r['status'] == 'reauth_required' ? MusicStatus.reauthRequired : MusicStatus.active,
      artists: ((r['artists'] as List?) ?? const [])
          .map((e) => MusicArtist.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      syncedAt: r['synced_at'] == null ? null : DateTime.parse(r['synced_at'] as String).toLocal(),
      topTracks: ((r['top_tracks'] as List?) ?? const [])
          .map((e) => MusicTrack.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      recentTracks: ((r['recent_tracks'] as List?) ?? const [])
          .map((e) => MusicTrack.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      showTopTracks: (r['show_top_tracks'] as bool?) ?? true,
      showRecent: (r['show_recent'] as bool?) ?? true,
      recentScope: (r['recent_scope'] as bool?) ?? false,
    );
  });

  @override
  Future<Uri> musicAuthorizeUrl() => _guard(() async {
    try {
      final res = await _db.functions.invoke('music-connect', body: const {});
      return Uri.parse((res.data as Map)['url'] as String);
    } on FunctionException catch (e) {
      throw AppException(
        e.status == 429 ? AppErrorCode.rateLimited : AppErrorCode.unknown,
        e.status == 503 ? 'Spotify isn’t available right now.' : 'Couldn’t start Spotify. Try again.',
      );
    }
  });

  @override
  Future<MusicSyncResult> syncMusic({bool force = false}) => _guard(() async {
    try {
      final res = await _db.functions.invoke('music-sync', body: {'action': 'sync', 'force': force});
      return switch ((res.data as Map)['status']) {
        'synced' => MusicSyncResult.synced,
        'reauth_required' => MusicSyncResult.reauthRequired,
        'disconnected' => MusicSyncResult.disconnected,
        _ => MusicSyncResult.cached,
      };
    } on FunctionException {
      return MusicSyncResult.cached; // keep showing the stored list
    }
  });

  @override
  Future<void> setArtistVisibility(String artistId, {required bool visible}) =>
      _guard(() => _db.rpc('set_music_artist_visibility', params: {'p_artist_id': artistId, 'p_visible': visible}));

  @override
  Future<void> setMusicSectionVisibility(String section, {required bool visible}) =>
      _guard(() => _db.rpc('set_music_section_visibility', params: {'p_section': section, 'p_visible': visible}));

  @override
  Future<void> disconnectMusic() => _guard(() async {
    await _db.functions.invoke('music-sync', body: {'action': 'disconnect'});
  });

  /// Upload to quarantine, then the server validates, strips metadata,
  /// moderates, encrypts and publishes. The original is deleted.
  Future<ImageUploadStatus> _uploadPhoto(
    Uint8List bytes,
    String kind, {
    String? requestId,
    String mime = 'image/jpeg',
    String? replaces,
  }) async {
    final ext = switch (mime) {
      'image/webp' => 'webp',
      'image/png' => 'png',
      _ => 'jpg',
    };
    final path = '$_me/${_uuid.v4()}.$ext';
    await _db.storage
        .from('uploads_quarantine')
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime, upsert: false));
    try {
      final res = await _db.functions.invoke(
        'process-image',
        body: {'path': path, 'kind': kind, 'request_id': ?requestId, 'replaces': ?replaces},
      );
      final status = (res.data as Map)['status'];
      return status == 'approved' ? ImageUploadStatus.approved : ImageUploadStatus.pending;
    } on FunctionException catch (e) {
      final details = e.details is Map ? (e.details as Map)['message'] as String? : null;
      throw AppException(
        e.status == 429
            ? AppErrorCode.rateLimited
            : e.status == 409
            ? AppErrorCode.photoSlotsFull
            : AppErrorCode.imageRejected,
        details ?? 'This photo couldn’t be uploaded.',
      );
    }
  }

  // ------------------------------------------------------- consent & age ----

  @override
  Future<String?> acceptedPolicyVersion() => _guard(() async => await _db.rpc('accepted_policy_version') as String?);

  @override
  Future<void> recordConsent(String version) => _guard(() => _db.rpc('record_consent', params: {'p_version': version}));

  @override
  Future<bool> hasDob() => _guard(() async => await _db.rpc('has_dob') as bool);

  @override
  Future<int> setDob(DateTime dob) => _guard(() async {
    final iso =
        '${dob.year.toString().padLeft(4, '0')}-${dob.month.toString().padLeft(2, '0')}-${dob.day.toString().padLeft(2, '0')}';
    return (await _db.rpc('set_dob', params: {'p_dob': iso}) as num).toInt();
  });

  // -------------------------------------------------------- verification ----

  @override
  Future<VerificationStatus> verificationStatus() => _guard(() async {
    final s = await _db.rpc('my_verification_status') as String;
    return VerificationStatus.values.firstWhere((v) => v.name == s, orElse: () => VerificationStatus.none);
  });

  @override
  Future<VerificationStart> startVerification() => _guard(() async {
    final rows = await _db.rpc('start_verification') as List;
    final r = (rows.first as Map).cast<String, dynamic>();
    return VerificationStart(requestId: r['request_id'] as String, pose: r['pose'] as String);
  });

  @override
  Future<void> submitVerificationSelfie(String requestId, Uint8List jpeg) =>
      _guard(() => _uploadPhoto(jpeg, 'selfie', requestId: requestId));

  @override
  Future<PrivateProfile> privateProfileOf(String userId) => _guard(() async {
    final row = await _db.from('profile_private').select().eq('id', userId).maybeSingle();
    if (row == null) return PrivateProfile.empty;
    return PrivateProfile(
      interests: ((row['interests'] as List?) ?? const []).cast<String>(),
      gallery: ((row['gallery_urls'] as List?) ?? const []).cast<String>().map(_mediaUrl).toList(),
    );
  });

  // ---------------------------------------------------------------- deck ----

  @override
  Future<List<PublicProfile>> fetchFeed() => _guard(() async {
    final rows = await _db.rpc('get_feed', params: {'p_limit': 20}) as List;
    return rows.cast<Map<String, dynamic>>().map((r) => PublicProfile.fromFeedRow(r, resolve: _mediaUrl)).toList();
  });

  @override
  Future<SwipeOutcome> swipe(String targetId, {required bool follow}) => _guard(() async {
    final result = await _db.rpc(
      'swipe_profile',
      params: {'p_target': targetId, 'p_action': follow ? 'follow_requested' : 'pass'},
    ) as String;
    return switch (result) {
      'matched' => SwipeOutcome.matched,
      'requested' => SwipeOutcome.requested,
      _ => SwipeOutcome.passed,
    };
  });

  // ------------------------------------------------------------ requests ----

  static const _senderJoin = 'sender:profiles!swipes_and_requests_sender_id_fkey(*)';
  static const _receiverJoin = 'receiver:profiles!swipes_and_requests_receiver_id_fkey(*)';

  @override
  Future<IncomingRequests> incomingRequests() => _guard(() async {
    final count = (await _db.rpc('incoming_request_count') as num).toInt();
    final rows = await _db
        .from('swipes_and_requests')
        .select('id, created_at, intro_prompt_id, intro_text, $_senderJoin')
        .eq('receiver_id', _me)
        .eq('action', 'follow_requested')
        .order('created_at', ascending: false);
    return IncomingRequests(
      count: count,
      requests: [
        for (final r in rows)
          if (r['sender'] != null)
            FollowRequest(
              id: r['id'] as String,
              sender: PublicProfile.fromProfileRow(r['sender'] as Map<String, dynamic>, resolve: _mediaUrl),
              createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
              introPromptId: r['intro_prompt_id'] as String?,
              introText: r['intro_text'] as String?,
            ),
      ],
    );
  });

  @override
  Future<void> respondToRequest(String requestId, {required bool accept}) =>
      _guard(() => _db.rpc('respond_to_request', params: {'p_request_id': requestId, 'p_accept': accept}));

  @override
  Future<List<Connection>> connections() => _guard(() async {
    final me = _me;
    final rows = await _db
        .from('swipes_and_requests')
        .select('created_at, responded_at, sender_id, intro_prompt_id, intro_text, $_senderJoin, $_receiverJoin')
        .eq('action', 'accepted')
        .or('sender_id.eq.$me,receiver_id.eq.$me')
        .order('responded_at', ascending: false);

    final out = <Connection>[];
    for (final r in rows) {
      final peerRow = (r['sender_id'] == me ? r['receiver'] : r['sender']) as Map<String, dynamic>?;
      if (peerRow == null) continue; // blocked: profile hidden by RLS
      final peer = PublicProfile.fromProfileRow(peerRow, resolve: _mediaUrl);
      final thread = await _vault.load(me, peer.id);
      final last = thread.isEmpty ? null : thread.last;
      out.add(
        Connection(
          profile: peer,
          connectedAt: DateTime.parse((r['responded_at'] ?? r['created_at']) as String).toLocal(),
          lastMessage: last == null ? null : (last.isVoice ? '🎤 Voice note' : last.content),
          unread: thread.where((m) => m.receiverId == me && !m.isRead).length,
          introPromptId: r['intro_prompt_id'] as String?,
          introText: r['intro_text'] as String?,
          introFromMe: r['sender_id'] == me,
        ),
      );
    }
    return out;
  });

  @override
  Stream<void> socialChanges() {
    final controller = StreamController<void>.broadcast();
    final me = currentUserId;
    if (me == null) return controller.stream;
    final channel = _db.channel('social:$me');
    for (final column in ['sender_id', 'receiver_id']) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'swipes_and_requests',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: column, value: me),
        callback: (_) => controller.add(null),
      );
    }
    channel.subscribe();
    final sub = _social.stream.listen(controller.add);
    unawaited(_ready().catchError((_) {}));
    controller.onCancel = () async {
      await sub.cancel();
      await _db.removeChannel(channel);
    };
    return controller.stream;
  }

  @override
  Future<bool> serverPremium() async => (await accessStatus()).hasChatAccess;

  // -------------------------------------------------------------- access ----

  @override
  Future<AccessStatus> accessStatus() => _guard(() async {
    final rows = await _db.rpc('my_access_status') as List;
    if (rows.isEmpty) return const AccessStatus();
    return AccessStatus.fromJson((rows.first as Map).cast<String, dynamic>());
  });

  @override
  Future<void> markAccessNoticeSeen(String kind) =>
      _guard(() async => await _db.rpc('mark_access_notice_seen', params: {'p_kind': kind}));

  @override
  Future<List<AppNotification>> notifications() => _guard(() async {
    final rows = await _db.from('user_notifications').select().order('created_at', ascending: false).limit(50);
    return [for (final r in rows) AppNotification.fromJson(r)];
  });

  @override
  Future<void> markNotificationsRead() => _guard(() async => await _db.rpc('mark_notifications_read'));

  @override
  Future<AccountRestriction?> myRestriction() => _guard(() async {
    final rows = await _db.rpc('my_restriction') as List;
    if (rows.isEmpty) return null;
    final r = (rows.first as Map).cast<String, dynamic>();
    return AccountRestriction(
      kind: r['kind'] as String,
      reason: r['reason'] as String,
      until: DateTime.tryParse(r['until'] as String? ?? '')?.toLocal(),
    );
  });

  // ------------------------------------------------------------- support ----

  @override
  Future<String?> supportEmail() => _guard(() async => await _db.rpc('my_support_email') as String?);

  @override
  Future<SupportTicket> submitSupportTicket({
    required SupportCategory category,
    required String subject,
    required String description,
    Uint8List? screenshotWebp,
  }) => _guard(() async {
    final problem = validateTicket(subject: subject, description: description);
    if (problem != null) throw AppException(AppErrorCode.invalidInput, problem);
    String? path;
    if (screenshotWebp != null) {
      path = '$_me/${_uuid.v4()}.webp';
      await _db.storage
          .from('support_attachments')
          .uploadBinary(path, screenshotWebp, fileOptions: const FileOptions(contentType: 'image/webp'));
    }
    final rows = await _db.rpc(
      'submit_support_ticket',
      params: {'p_category': category.wire, 'p_subject': subject, 'p_description': description, 'p_attachment_path': path},
    ) as List;
    final id = (rows.first as Map)['id'] as String;
    // Staff email (if configured). The ticket is stored either way.
    unawaited(_db.functions.invoke('support-notify', body: {'ticket_id': id}).then((_) {}, onError: (_) {}));
    final row = await _db.from('support_tickets').select().eq('id', id).single();
    return SupportTicket.fromJson(row);
  });

  @override
  Future<List<SupportTicket>> myTickets() => _guard(() async {
    final rows = await _db.from('support_tickets').select().order('created_at', ascending: false);
    return [for (final r in rows) SupportTicket.fromJson(r)];
  });

  // ---------------------------------------------------------------- chat ----

  @override
  Stream<List<ChatMessage>> watchMessages(String peerId) {
    final ctl = _threads.putIfAbsent(peerId, () => StreamController<List<ChatMessage>>.broadcast());
    return Stream.multi((listener) {
      final sub = ctl.stream.listen(listener.add, onError: listener.addError);
      () async {
        try {
          await _ready();
          listener.add(await _vault.load(_me, peerId));
          await _drain();
        } catch (e) {
          listener.addError(_map(e));
        }
      }();
      listener.onCancel = sub.cancel;
    });
  }

  Future<void> _sendPayload(String peerId, SecurePayload payload) => _guard(() async {
    await _ready();
    final envelopes = await _engine.encryptFor(peerId, payload.encode());
    final id = await _db.rpc(
      'send_message',
      params: {
        'p_receiver': peerId,
        'p_client_msg_id': payload.clientId,
        'p_sender_device': _engine.deviceId,
        'p_envelopes': envelopes.map((e) => e.toJson()).toList(),
      },
    ) as String;
    final me = _me;
    await _vault.markSeen(me, me, payload.clientId);
    final list = await _vault.upsert(
      me,
      peerId,
      ChatMessage(
        id: id,
        senderId: me,
        receiverId: peerId,
        content: payload.text,
        voice: payload.voice,
        image: payload.image,
        isRead: false,
        createdAt: payload.sentAt,
      ),
    );
    _threads[peerId]?.add(list);
    _social.add(null);
  });

  @override
  Future<void> sendText(String peerId, String text) =>
      _sendPayload(peerId, SecurePayload(clientId: _uuid.v4(), sentAt: DateTime.now(), text: text));

  @override
  Future<void> sendVoice(String peerId, Uint8List aacBytes, {String? localPath, Duration duration = Duration.zero}) =>
      _guard(() async {
        final me = _me;
        final clientId = _uuid.v4();
        final path = '${_pairKey(me, peerId)}/$clientId.bin';
        final sealed = await E2eeEngine.sealAttachment(aacBytes, 'voice:$path');
        await _db.storage
            .from('voice_notes')
            .uploadBinary(path, sealed.ciphertext, fileOptions: const FileOptions(contentType: 'application/octet-stream'));
        await _sendPayload(
          peerId,
          SecurePayload(
            clientId: clientId,
            sentAt: DateTime.now(),
            voice: VoiceRef(
              path: path,
              key: sealed.key,
              nonce: sealed.nonce,
              sha256: sealed.sha256,
              millis: duration.inMilliseconds,
            ),
          ),
        );
      });

  @override
  Future<VoicePlayback> voicePlayback(ChatMessage message) => _guard(() async {
    final v = message.voice!;
    final ciphertext = await _db.storage.from('voice_notes').download(v.path);
    final bytes = await E2eeEngine.openAttachment(
      key: v.key,
      nonce: v.nonce,
      ciphertext: ciphertext,
      sha256: v.sha256,
      aad: 'voice:${v.path}',
    );
    return VoicePlayback.bytes(bytes);
  });

  @override
  Future<void> sendImage(String peerId, Uint8List webp, {required int width, required int height}) => _guard(() async {
    final me = _me;
    final clientId = _uuid.v4();
    final path = '${_pairKey(me, peerId)}/$clientId.bin';
    final sealed = await E2eeEngine.sealAttachment(webp, 'image:$path');
    await _db.storage
        .from('chat_images')
        .uploadBinary(path, sealed.ciphertext, fileOptions: const FileOptions(contentType: 'application/octet-stream'));
    await _sendPayload(
      peerId,
      SecurePayload(
        clientId: clientId,
        sentAt: DateTime.now(),
        image: ImageRef(path: path, key: sealed.key, nonce: sealed.nonce, sha256: sealed.sha256, width: width, height: height),
      ),
    );
  });

  final _imageCache = <String, Uint8List>{};

  @override
  Future<Uint8List> imageBytes(ChatMessage message) => _guard(() async {
    final img = message.image!;
    final cached = _imageCache[img.path];
    if (cached != null) return cached;
    final ciphertext = await _db.storage.from('chat_images').download(img.path);
    final bytes = await E2eeEngine.openAttachment(
      key: img.key,
      nonce: img.nonce,
      ciphertext: ciphertext,
      sha256: img.sha256,
      aad: 'image:${img.path}',
    );
    if (_imageCache.length > 40) _imageCache.remove(_imageCache.keys.first);
    return _imageCache[img.path] = bytes;
  });

  @override
  Future<void> markThreadRead(String peerId) => _guard(() async {
    final me = _me;
    await _db.from('messages').update({'is_read': true}).eq('receiver_id', me).eq('sender_id', peerId).eq('is_read', false);
    final list = await _vault.update(me, peerId, (m) => m.receiverId == me && !m.isRead ? m.copyWith(isRead: true) : m);
    _threads[peerId]?.add(list);
    _social.add(null);
  });

  @override
  Future<String?> safetyNumber(String peerId) => _guard(() async {
    await _ready();
    return _engine.safetyNumber(peerId);
  });

  // -------------------------------------------------------------- safety ----

  @override
  Future<void> unmatch(String peerId) => _guard(() async {
    await _db.rpc('unmatch', params: {'p_peer': peerId});
    await _vault.deleteThread(_me, peerId);
    _social.add(null);
  });

  @override
  Future<void> blockUser(String peerId) => _guard(() async {
    await _db.rpc('block_user', params: {'p_peer': peerId});
    await _vault.deleteThread(_me, peerId);
    _social.add(null);
  });

  @override
  Future<void> report(
    String peerId,
    ReportReason reason, {
    String? details,
    List<ChatMessage> evidence = const [],
    bool block = true,
  }) => _guard(() async {
    await _db.rpc(
      'submit_report',
      params: {
        'p_reported': peerId,
        'p_reason': reason.wire,
        'p_details': details,
        'p_evidence': evidence.isEmpty
            ? null
            : [
                for (final m in evidence.take(20))
                  {
                    'message_id': m.id,
                    'from_reported_user': m.senderId == peerId,
                    'sent_at': m.createdAt.toUtc().toIso8601String(),
                    'text': m.isVoice ? '[voice note — not shared]' : m.content,
                  },
              ],
        'p_block': block,
      },
    );
    if (block) await _vault.deleteThread(_me, peerId);
    _social.add(null);
  });

  @override
  Future<String> reportWithEvidence(
    String peerId,
    ReportReason reason, {
    String? details,
    String? contentRef,
    ReportEvidence evidence = const ReportEvidence(),
    bool block = true,
  }) => _guard(() async {
    final rows = await _db.rpc(
      'submit_report_v2',
      params: {
        'p_reported': peerId,
        'p_reason': reason.wire,
        'p_details': details,
        'p_content_ref': contentRef,
        'p_evidence': evidence.texts.isEmpty ? null : evidence.texts.take(20).toList(),
        'p_block': block,
      },
    ) as List;
    final r = (rows.first as Map).cast<String, dynamic>();
    final reportId = r['id'] as String;
    // Photos the reporter selected, decrypted on this device, sent with consent.
    for (final (i, (messageId, bytes)) in evidence.images.take(10).indexed) {
      final path = '$reportId/$i.webp';
      await _db.storage
          .from('report_evidence')
          .uploadBinary(path, Uint8List.fromList(bytes), fileOptions: const FileOptions(contentType: 'image/webp'));
      await _db.rpc(
        'add_report_evidence',
        params: {'p_report': reportId, 'p_kind': 'image', 'p_message_ref': messageId, 'p_path': path},
      );
    }
    if (block) await _vault.deleteThread(_me, peerId);
    _social.add(null);
    return r['report_no'] as String;
  });

  // ---------------------------------------------------- account security ----

  String? get _sessionId {
    final token = _db.auth.currentSession?.accessToken;
    if (token == null) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1])))) as Map;
      return payload['session_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<SessionInfo>> sessions() => _guard(() async {
    final rows = (await _db.rpc('my_sessions') as List).cast<Map<String, dynamic>>();
    final current = _sessionId;
    return [
      for (final r in rows)
        SessionInfo(
          id: r['id'] as String,
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
          lastActive: r['updated_at'] == null ? null : DateTime.parse(r['updated_at'] as String).toLocal(),
          userAgent: r['user_agent'] as String?,
          aal: r['aal'] as String?,
          isCurrent: r['id'] == current,
        ),
    ];
  });

  @override
  Future<void> revokeSession(String sessionId) => _guard(() => _db.rpc('revoke_session', params: {'p_session': sessionId}));

  @override
  Future<void> signOutOtherSessions() => _guard(() => _db.auth.signOut(scope: SignOutScope.others));

  @override
  Future<List<DeviceInfo>> devices() => _guard(() async {
    await _ready();
    final rows = await _db
        .from('devices')
        .select('id, label, platform, created_at, last_seen_at')
        .eq('user_id', _me)
        .isFilter('revoked_at', null)
        .order('created_at');
    return [
      for (final r in rows)
        DeviceInfo(
          id: r['id'] as String,
          label: r['label'] as String,
          platform: r['platform'] as String,
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
          lastSeen: DateTime.parse(r['last_seen_at'] as String).toLocal(),
          isThisDevice: r['id'] == _engine.deviceId,
        ),
    ];
  });

  @override
  Future<void> revokeDevice(String deviceId) => _guard(() => _db.rpc('revoke_device', params: {'p_device': deviceId}));

  @override
  Future<MfaState> mfaState() => _guard(() async {
    final factors = await _db.auth.mfa.listFactors();
    final aal = _db.auth.mfa.getAuthenticatorAssuranceLevel();
    final verified = factors.totp.where((f) => f.status == FactorStatus.verified).map((f) => f.id).toList();
    final isAal2 = aal.currentLevel == AuthenticatorAssuranceLevels.aal2;
    return MfaState(verifiedFactorIds: verified, sessionIsAal2: isAal2, needsChallenge: verified.isNotEmpty && !isAal2);
  });

  @override
  Future<TotpEnrollment> enrollTotp() => _guard(() async {
    // Drop abandoned, never-verified factors first.
    final factors = await _db.auth.mfa.listFactors();
    for (final f in factors.all.where((f) => f.status == FactorStatus.unverified)) {
      await _db.auth.mfa.unenroll(f.id);
    }
    final r = await _db.auth.mfa.enroll(factorType: FactorType.totp, issuer: 'Vouby', friendlyName: 'Authenticator app');
    return TotpEnrollment(factorId: r.id, secret: r.totp!.secret, uri: r.totp!.uri);
  });

  @override
  Future<void> verifyTotp(String factorId, String code) => _guard(() async {
    await _db.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  });

  @override
  Future<void> removeTotp(String factorId) => _guard(() async {
    await _db.auth.mfa.unenroll(factorId);
  });

  @override
  Future<void> deleteAccount() => _guard(() async {
    try {
      await _db.functions.invoke('delete-account');
    } on FunctionException catch (e) {
      throw AppException(
        e.status == 403 ? AppErrorCode.mfaRequired : AppErrorCode.unknown,
        e.status == 403 ? 'Verify with your authenticator app first.' : 'Account deletion failed. Try again.',
      );
    }
    await _stopInbox();
    await _engine.wipe();
    await _kv.deleteAll();
    await _db.auth.signOut(scope: SignOutScope.local);
  });

  // ---------------------------------------------------------------- staff ----

  @override
  Future<String?> staffRole() => _guard(() async => await _db.rpc('my_staff_role') as String?);

  @override
  Future<Map<String, dynamic>> securityOverview() =>
      _guard(() async => (await _db.rpc('admin_security_overview') as Map).cast<String, dynamic>());

  @override
  Future<List<ReportSummary>> openReports() => _guard(() async {
    final rows = (await _db.rpc('mod_list_reports', params: {'p_status': 'open'}) as List).cast<Map<String, dynamic>>();
    return [
      for (final r in rows)
        ReportSummary(
          id: r['id'] as String,
          reportedId: r['reported_id'] as String,
          reason: r['reason'] as String,
          hasEvidence: r['has_evidence'] as bool,
          reportCount: (r['report_count'] as num).toInt(),
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
          status: r['status'] as String,
        ),
    ];
  });

  @override
  Future<Map<String, dynamic>> openReportEvidence(String reportId, String accessReason) => _guard(() async {
    final rows = await _db.rpc('mod_open_report', params: {'p_report': reportId, 'p_reason': accessReason}) as List;
    return (rows.first as Map).cast<String, dynamic>();
  });

  @override
  Future<void> resolveReport(String reportId, {required bool actioned, required String resolution}) => _guard(
    () => _db.rpc(
      'mod_resolve_report',
      params: {'p_report': reportId, 'p_status': actioned ? 'actioned' : 'dismissed', 'p_resolution': resolution},
    ),
  );

  @override
  Future<List<PendingMedia>> pendingMedia() => _guard(() async {
    final rows = (await _db.rpc('mod_pending_media') as List).cast<Map<String, dynamic>>();
    return [
      for (final r in rows)
        PendingMedia(
          id: r['id'] as String,
          ownerId: r['owner_id'] as String,
          kind: r['kind'] as String,
          url: _mediaUrl(r['id'] as String),
        ),
    ];
  });

  @override
  Future<void> reviewMedia(String mediaId, {required bool approve}) =>
      _guard(() => _db.rpc('mod_review_media', params: {'p_media': mediaId, 'p_approve': approve}));

  @override
  Future<List<VerificationItem>> verificationQueue() => _guard(() async {
    final rows = (await _db.rpc('mod_verification_queue') as List).cast<Map<String, dynamic>>();
    return [
      for (final r in rows)
        VerificationItem(
          requestId: r['request_id'] as String,
          userId: r['user_id'] as String,
          name: r['full_name'] as String,
          pose: r['pose'] as String,
          selfieUrl: r['selfie_media'] == null ? null : _mediaUrl(r['selfie_media'] as String),
          profileUrl: r['profile_media'] == null ? null : _mediaUrl(r['profile_media'] as String),
          submittedAt: DateTime.parse(r['submitted_at'] as String).toLocal(),
        ),
    ];
  });

  @override
  Future<void> reviewVerification(String requestId, {required bool approve}) =>
      _guard(() => _db.rpc('mod_review_verification', params: {'p_request': requestId, 'p_approve': approve}));

  @override
  Future<List<StaffReport>> staffReports({String status = 'open'}) => _guard(() async {
    final rows = await _db.rpc('mod_list_reports_v2', params: {'p_status': status}) as List;
    return [for (final r in rows) StaffReport.fromJson((r as Map).cast<String, dynamic>())];
  });

  @override
  Future<void> decideReport(String reportId, ModDecision decision, {required String note, int? days}) => _guard(
    () async => await _db.rpc(
      'mod_decide_report',
      params: {
        'p_report': reportId,
        'p_decision': decision.wire,
        'p_note': note,
        'p_restriction': decision.restriction,
        'p_days': days,
      },
    ),
  );

  @override
  Future<Map<String, dynamic>> userModerationHistory(String userId) =>
      _guard(() async => ((await _db.rpc('mod_user_history', params: {'p_user': userId})) as Map).cast<String, dynamic>());

  @override
  Future<List<EvidenceItem>> reportEvidenceFiles(String reportId) => _guard(() async {
    final rows = await _db.rpc('mod_list_evidence', params: {'p_report': reportId}) as List;
    return [
      for (final r in rows.cast<Map>())
        EvidenceItem(
          id: r['id'] as String,
          kind: r['kind'] as String,
          messageRef: r['message_ref'] as String?,
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        ),
    ];
  });

  @override
  Future<String> staffFileUrl({required String kind, required String id, String reason = 'review'}) => _guard(() async {
    final res = await _db.functions.invoke('evidence-url', body: {'kind': kind, 'id': id, 'reason': reason});
    return (res.data as Map)['url'] as String;
  });

  @override
  Future<List<SupportTicket>> staffTickets({String status = 'open'}) => _guard(() async {
    final rows = await _db.rpc('mod_list_tickets', params: {'p_status': status}) as List;
    return [for (final r in rows) SupportTicket.fromJson((r as Map).cast<String, dynamic>())];
  });

  @override
  Future<void> setTicketStatus(String ticketId, TicketStatus status, {String? note}) => _guard(
    () async => await _db.rpc('mod_set_ticket_status', params: {'p_ticket': ticketId, 'p_status': status.wire, 'p_note': note}),
  );

  // ------------------------------------------------------------- helpers ----

  static String _pairKey(String a, String b) => (a.compareTo(b) < 0) ? '${a}_$b' : '${b}_$a';

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw _map(e);
    }
  }

  /// Maps server errors to user-facing messages without leaking internals.
  static Object _map(Object e) {
    if (e is AppException) return e;
    if (e is E2eeException) return AppException(AppErrorCode.encryption, e.message);
    if (e is PostgrestException) {
      final hint = e.hint ?? '';
      return switch (hint) {
        'SUBSCRIPTION_REQUIRED' => AppException(AppErrorCode.subscriptionRequired, e.message),
        'RATE_LIMIT' => const AppException(AppErrorCode.rateLimited, 'You’re doing that too fast. Try again in a minute.'),
        'MFA_REQUIRED' => const AppException(AppErrorCode.mfaRequired, 'Verify with your authenticator app to continue.'),
        'DEVICE_LIMIT' => const AppException(
          AppErrorCode.deviceLimit,
          'You’re signed in on 5 devices. Remove one in Security settings.',
        ),
        'UNDER_18' => const AppException(AppErrorCode.underage, 'Vouby is only for people aged 18 and over.'),
        'DOB_LOCKED' => const AppException(AppErrorCode.dobLocked, 'Your date of birth can’t be changed.'),
        'DOB_REQUIRED' => const AppException(AppErrorCode.dobRequired, 'Add your date of birth first.'),
        'VERIFICATION_PENDING' => const AppException(AppErrorCode.verificationPending, 'Your verification is being reviewed.'),
        'CONTACT_INFO' => const AppException(AppErrorCode.contactInfo, 'Phone numbers, @handles and links are not allowed.'),
        'ONBOARDING_INCOMPLETE' => AppException(AppErrorCode.onboardingIncomplete, e.message),
        'PHOTO_SLOTS_FULL' => const AppException(AppErrorCode.photoSlotsFull, 'All 6 photo slots are full.'),
        'ACCOUNT_RESTRICTED' => AppException(AppErrorCode.accountRestricted, e.message),
        _ when e.code == '22023' => AppException(AppErrorCode.invalidInput, e.message),
        _ =>
          e.code == '23514' && e.message.contains('clean')
              ? const AppException(AppErrorCode.contactInfo, 'Phone numbers, @handles and links are not allowed.')
              : e.code == '42501'
              ? const AppException(AppErrorCode.notConnected, 'You can’t do that with this person.')
              : const AppException(AppErrorCode.unknown, 'Something went wrong. Try again.'),
      };
    }
    if (e is AuthException) return AppException(AppErrorCode.unknown, e.message);
    if (e is StorageException) return const AppException(AppErrorCode.unknown, 'Upload failed. Try again.');
    return const AppException(AppErrorCode.network, 'Something went wrong. Check your connection.');
  }
}
