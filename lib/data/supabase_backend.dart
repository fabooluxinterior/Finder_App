import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' hide OtpChannel;
import 'package:uuid/uuid.dart';

import '../core/errors.dart';
import '../models/follow_request.dart';
import '../models/message.dart';
import '../models/profile.dart';
import 'backend.dart';

class SupabaseBackend implements FinderBackend {
  SupabaseBackend(this._db);

  final SupabaseClient _db;
  static const _uuid = Uuid();
  static const _signedUrlTtl = 60 * 60;

  /// storage path -> signed URL (with expiry) to avoid re-signing every rebuild.
  final _signed = <String, (String, DateTime)>{};

  String get _me {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw const AppException(AppErrorCode.unknown, 'Not signed in');
    return id;
  }

  @override
  String? get currentUserId => _db.auth.currentUser?.id;

  @override
  Stream<String?> authChanges() async* {
    yield currentUserId;
    yield* _db.auth.onAuthStateChange.map((s) => s.session?.user.id);
  }

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

  @override
  Future<void> signOut() => _db.auth.signOut();

  // ------------------------------------------------------------- profile ----

  @override
  Future<PublicProfile?> myProfile() => _guard(() async {
        final row = await _db.from('profiles').select().eq('id', _me).maybeSingle();
        if (row == null) return null;
        final p = PublicProfile.fromProfileRow(row);
        return p.copyWith(primaryPhoto: await _sign('avatars', p.primaryPhoto));
      });

  @override
  Future<PrivateProfile> myPrivateProfile() => privateProfileOf(_me);

  @override
  Future<void> saveProfile(ProfileDraft d) => _guard(() async {
        final me = _me;
        final existing =
            await _db.from('profiles').select('avatar_urls').eq('id', me).maybeSingle();

        var avatarUrls = ((existing?['avatar_urls'] as List?) ?? const []).cast<String>();
        if (d.primaryPhotoWebp != null) {
          final path = '$me/primary/${_uuid.v4()}.webp';
          await _uploadWebp(path, d.primaryPhotoWebp!);
          if (avatarUrls.isNotEmpty) {
            await _db.storage.from('avatars').remove(avatarUrls);
          }
          avatarUrls = [path];
        }

        final fields = {
          'full_name': d.fullName,
          'age': d.age,
          'city': d.city,
          'bio': d.bio,
          'avatar_urls': avatarUrls,
        };
        if (existing == null) {
          await _db.from('profiles').insert({'id': me, ...fields});
        } else {
          await _db.from('profiles').update(fields).eq('id', me);
        }

        final priv =
            await _db.from('profile_private').select('gallery_urls').eq('id', me).maybeSingle();
        final gallery = ((priv?['gallery_urls'] as List?) ?? const []).cast<String>().toList();
        for (final bytes in d.newGalleryWebp) {
          final path = '$me/gallery/${_uuid.v4()}.webp';
          await _uploadWebp(path, bytes);
          gallery.add(path);
        }
        await _db.from('profile_private').upsert({
          'id': me,
          'interests': d.interests,
          'gallery_urls': gallery.take(9).toList(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      });

  Future<void> _uploadWebp(String path, Uint8List bytes) => _db.storage.from('avatars').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/webp', upsert: false),
      );

  @override
  Future<PrivateProfile> privateProfileOf(String userId) => _guard(() async {
        final row =
            await _db.from('profile_private').select().eq('id', userId).maybeSingle();
        if (row == null) return PrivateProfile.empty;
        final paths = ((row['gallery_urls'] as List?) ?? const []).cast<String>();
        return PrivateProfile(
          interests: ((row['interests'] as List?) ?? const []).cast<String>(),
          gallery: await _signAll('avatars', paths),
        );
      });

  // ---------------------------------------------------------------- deck ----

  @override
  Future<List<PublicProfile>> fetchFeed() => _guard(() async {
        final rows = await _db.rpc('get_feed', params: {'p_limit': 20}) as List;
        final profiles = rows.cast<Map<String, dynamic>>().map(PublicProfile.fromFeedRow).toList();
        return _withSignedPhotos(profiles);
      });

  @override
  Future<int> remainingSwipes() =>
      _guard(() async => (await _db.rpc('remaining_swipes') as num).toInt());

  @override
  Future<SwipeOutcome> swipe(String targetId, {required bool follow, String? directNote}) =>
      _guard(() async {
        final result = await _db.rpc('swipe_profile', params: {
          'p_target': targetId,
          'p_action': follow ? 'follow_requested' : 'pass',
          'p_note': directNote,
        }) as String;
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
        // RLS returns rows only for Fast-Track members; free users get the count only.
        final rows = await _db
            .from('swipes_and_requests')
            .select('id, direct_note, created_at, $_senderJoin')
            .eq('receiver_id', _me)
            .eq('action', 'follow_requested')
            .order('created_at', ascending: false);
        final senders = await _withSignedPhotos(
          rows.map((r) => PublicProfile.fromProfileRow(r['sender'] as Map<String, dynamic>)).toList(),
        );
        return IncomingRequests(
          count: count,
          requests: [
            for (var i = 0; i < rows.length; i++)
              FollowRequest(
                id: rows[i]['id'] as String,
                sender: senders[i],
                directNote: rows[i]['direct_note'] as String?,
                createdAt: DateTime.parse(rows[i]['created_at'] as String).toLocal(),
              ),
          ],
        );
      });

  @override
  Future<void> respondToRequest(String requestId, {required bool accept}) => _guard(() =>
      _db.rpc('respond_to_request', params: {'p_request_id': requestId, 'p_accept': accept}));

  @override
  Future<List<Connection>> connections() => _guard(() async {
        final me = _me;
        final rows = await _db
            .from('swipes_and_requests')
            .select('created_at, responded_at, sender_id, $_senderJoin, $_receiverJoin')
            .eq('action', 'accepted')
            .or('sender_id.eq.$me,receiver_id.eq.$me')
            .order('responded_at', ascending: false);

        final peers = await _withSignedPhotos([
          for (final r in rows)
            PublicProfile.fromProfileRow(
              (r['sender_id'] == me ? r['receiver'] : r['sender']) as Map<String, dynamic>,
            ),
        ]);

        final unreadRows =
            await _db.from('messages').select('sender_id').eq('receiver_id', me).eq('is_read', false);
        final unread = <String, int>{};
        for (final u in unreadRows) {
          final s = u['sender_id'] as String;
          unread[s] = (unread[s] ?? 0) + 1;
        }

        return [
          for (var i = 0; i < rows.length; i++)
            Connection(
              profile: peers[i],
              connectedAt: DateTime.parse(
                (rows[i]['responded_at'] ?? rows[i]['created_at']) as String,
              ).toLocal(),
              unread: unread[peers[i].id] ?? 0,
            ),
        ];
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
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'receiver_id', value: me),
      callback: (_) => controller.add(null),
    );
    channel.subscribe();
    controller.onCancel = () => _db.removeChannel(channel);
    return controller.stream;
  }

  @override
  Future<bool> serverPremium() => _guard(() async {
        final row = await _db
            .from('profiles')
            .select('is_premium, premium_expires_at')
            .eq('id', _me)
            .maybeSingle();
        if (row == null || row['is_premium'] != true) return false;
        final exp = row['premium_expires_at'] as String?;
        return exp == null || DateTime.parse(exp).isAfter(DateTime.now());
      });

  // ---------------------------------------------------------------- chat ----

  @override
  Stream<List<ChatMessage>> watchMessages(String peerId) {
    final me = _me;
    final byId = <String, ChatMessage>{};
    late final StreamController<List<ChatMessage>> controller;
    RealtimeChannel? channel;

    void emit() {
      final list = byId.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (!controller.isClosed) controller.add(list);
    }

    void upsert(Map<String, dynamic> row) {
      if (row.isEmpty) return;
      final m = ChatMessage.fromRow(row);
      final inThread = (m.senderId == me && m.receiverId == peerId) ||
          (m.senderId == peerId && m.receiverId == me);
      if (inThread) {
        byId[m.id] = m;
        emit();
      }
    }

    controller = StreamController<List<ChatMessage>>(
      onListen: () async {
        // Subscribe first so nothing sent during the history fetch is lost.
        channel = _db.channel('thread:${_pairKey(me, peerId)}:${_uuid.v4()}');
        for (final column in ['sender_id', 'receiver_id']) {
          channel!.onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: column, value: peerId),
            callback: (p) => upsert(p.newRecord),
          );
        }
        channel!.subscribe();
        try {
          final rows = await _db
              .from('messages')
              .select()
              .or('and(sender_id.eq.$me,receiver_id.eq.$peerId),and(sender_id.eq.$peerId,receiver_id.eq.$me)')
              .order('created_at')
              .limit(500);
          rows.forEach(upsert);
          emit();
        } catch (e) {
          controller.addError(_map(e));
        }
      },
      onCancel: () async {
        if (channel != null) await _db.removeChannel(channel!);
        await controller.close();
      },
    );
    _threadSinks[peerId] = upsert;
    return controller.stream;
  }

  /// Lets locally-sent messages appear instantly, before the realtime echo.
  final _threadSinks = <String, void Function(Map<String, dynamic>)>{};

  @override
  Future<void> sendText(String peerId, String text) => _guard(() async {
        final row = await _db
            .from('messages')
            .insert({'sender_id': _me, 'receiver_id': peerId, 'content': text})
            .select()
            .single();
        _threadSinks[peerId]?.call(row);
      });

  @override
  Future<void> sendVoice(String peerId, Uint8List aacBytes, {String? localPath}) => _guard(() async {
        final me = _me;
        final path = '${_pairKey(me, peerId)}/${_uuid.v4()}.m4a';
        await _db.storage.from('voice_notes').uploadBinary(
              path,
              aacBytes,
              fileOptions: const FileOptions(contentType: 'audio/mp4'),
            );
        final row = await _db
            .from('messages')
            .insert({'sender_id': me, 'receiver_id': peerId, 'audio_url': path})
            .select()
            .single();
        _threadSinks[peerId]?.call(row);
      });

  @override
  Future<void> markThreadRead(String peerId) => _guard(() => _db
      .from('messages')
      .update({'is_read': true})
      .eq('receiver_id', _me)
      .eq('sender_id', peerId)
      .eq('is_read', false));

  @override
  Future<String> playableAudioUrl(ChatMessage message) async =>
      (await _sign('voice_notes', message.audioUrl))!;

  // ------------------------------------------------------------- helpers ----

  static String _pairKey(String a, String b) => (a.compareTo(b) < 0) ? '${a}_$b' : '${b}_$a';

  Future<List<PublicProfile>> _withSignedPhotos(List<PublicProfile> profiles) async {
    final paths = profiles.map((p) => p.primaryPhoto).whereType<String>().toList();
    final urls = await _signAll('avatars', paths);
    final map = Map.fromIterables(paths, urls);
    return [for (final p in profiles) p.copyWith(primaryPhoto: map[p.primaryPhoto])];
  }

  Future<String?> _sign(String bucket, String? path) async {
    if (path == null || path.isEmpty) return null;
    return (await _signAll(bucket, [path])).first;
  }

  Future<List<String>> _signAll(String bucket, List<String> paths) async {
    final now = DateTime.now();
    final missing = paths
        .where((p) => !(_signed['$bucket/$p']?.$2.isAfter(now) ?? false))
        .toSet()
        .toList();
    if (missing.isNotEmpty) {
      final signed = await _db.storage.from(bucket).createSignedUrlsResult(missing, _signedUrlTtl);
      final expiry = now.add(const Duration(seconds: _signedUrlTtl - 120));
      for (final s in signed.whereType<SignedUrlSuccess>()) {
        _signed['$bucket/${s.path}'] = (s.signedUrl, expiry);
      }
    }
    return [for (final p in paths) _signed['$bucket/$p']?.$1 ?? ''];
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw _map(e);
    }
  }

  static Object _map(Object e) {
    if (e is AppException) return e;
    if (e is PostgrestException) {
      final hint = e.hint ?? '';
      if (hint == 'SWIPE_LIMIT' || e.message.contains('limit reached')) {
        return const AppException(AppErrorCode.swipeLimit, 'You have used your 10 free follow requests today.');
      }
      if (hint == 'PREMIUM_REQUIRED') {
        return const AppException(AppErrorCode.premiumRequired, 'This needs the Fast-Track pass.');
      }
      if (e.code == '23514' && e.message.contains('clean')) {
        return const AppException(AppErrorCode.contactInfo, 'Phone numbers, @handles and links are not allowed.');
      }
      if (e.code == '42501') {
        return const AppException(AppErrorCode.notConnected, 'Chat unlocks once the follow request is accepted.');
      }
      return AppException(AppErrorCode.unknown, e.message);
    }
    if (e is AuthException) return AppException(AppErrorCode.unknown, e.message);
    if (e is StorageException) return AppException(AppErrorCode.unknown, e.message);
    return AppException(AppErrorCode.network, 'Something went wrong. Check your connection.');
  }
}
