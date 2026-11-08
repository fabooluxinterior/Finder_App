import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/config.dart';
import '../core/errors.dart';
import '../core/sanitizer.dart';
import '../models/follow_request.dart';
import '../models/message.dart';
import '../models/profile.dart';
import '../models/profile_catalog.dart';
import '../models/profile_completion.dart';
import '../models/security.dart';
import 'backend.dart';
import 'memory_images.dart';

/// Fully offline backend used when no Supabase credentials are supplied.
/// Mirrors the server rules (limits, RLS visibility, mutual consent) so the
/// demo behaves like production.
class DemoBackend implements FinderBackend {
  /// [persist]: remember the session and your own profile on this device
  /// (shared preferences / browser storage), so closing the app or going
  /// back never means signing in and setting up again.
  DemoBackend({this.persist = false}) {
    _seed();
  }

  final bool persist;
  static const _stateKey = 'vouby_demo_state_v1';

  static const _uuid = Uuid();
  static const meId = 'me';

  final _rand = Random(7);
  final _auth = StreamController<String?>.broadcast();
  final _social = StreamController<void>.broadcast();
  final _threads = <String, List<ChatMessage>>{};
  final _threadCtl = <String, StreamController<List<ChatMessage>>>{};

  String? _uid;
  bool premium = false;

  PublicProfile? _me;
  final PrivateProfile _myPrivate = PrivateProfile.empty;

  final _people = <String, _Seed>{};

  /// (sender, receiver) -> row
  final _swipes = <(String, String), _Swipe>{};

  // ---------------------------------------------------------------- auth ----

  @override
  String? get currentUserId => _uid;

  @override
  Stream<String?> authChanges() async* {
    yield _uid;
    yield* _auth.stream;
  }

  @override
  Future<void> sendOtp(OtpChannel channel, String target) async {
    await _latency();
  }

  @override
  Future<void> verifyOtp(OtpChannel channel, String target, String code) async {
    await _latency();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const AppException(AppErrorCode.unknown, 'Enter the 6-digit code (any digits work in demo).');
    }
    _uid = meId;
    _auth.add(_uid);
    _persist();
  }

  @override
  Future<void> signOut() async {
    _uid = null;
    _auth.add(null);
    if (persist) {
      try {
        await (await SharedPreferences.getInstance()).remove(_stateKey);
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------- profile ----

  @override
  Future<PublicProfile?> myProfile() async => _me?.copyWith(isPremium: premium);

  @override
  Future<PrivateProfile> myPrivateProfile() async => _myPrivate;

  // ---------------------------------------------------------- persistence ----

  /// Loads the saved session (demo builds only). Call before runApp.
  Future<void> restore() async {
    if (!persist) return;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_stateKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _consentVersion = m['consent'] as String?;
      _dob = m['dob'] == null ? null : DateTime.parse(m['dob'] as String);
      _standardsAck = (m['standards'] as bool?) ?? false;
      premium = (m['premium'] as bool?) ?? false;
      _verification = VerificationStatus.values.firstWhere(
        (v) => v.name == m['verification'],
        orElse: () => VerificationStatus.none,
      );
      _photos
        ..clear()
        ..addAll([
          for (final p in (m['photos'] as List? ?? const []).cast<Map<String, dynamic>>())
            PhotoSlot(mediaId: p['id'] as String, url: MemoryImages.put(base64Decode(p['bytes'] as String))),
        ]);
      final music = m['music'] as Map<String, dynamic>?;
      if (music != null) {
        _music = MusicState(
          status: MusicStatus.active,
          syncedAt: DateTime.tryParse(music['synced'] as String? ?? ''),
          artists: [
            for (final a in (music['artists'] as List).cast<Map<String, dynamic>>())
              MusicArtist.fromJson(a).copyWith(visible: (a['visible'] as bool?) ?? true),
          ],
        );
      }
      final me = m['me'] as Map<String, dynamic>?;
      if (me != null) {
        _me = _rescore(
          PublicProfile.fromProfileRow({...me, 'photo_urls': _photos.map((p) => p.url).toList()})
              .copyWith(isPremium: premium, isVerified: _verification == VerificationStatus.approved),
        );
      }
      if (m['uid'] == meId) _uid = meId;
    } catch (_) {
      // Corrupt or old state: start fresh.
    }
  }

  bool _saving = false;
  bool _dirty = false;

  /// Writes the session in the background (coalesces bursts of changes).
  void _persist() {
    if (!persist) return;
    _dirty = true;
    if (_saving) return;
    _saving = true;
    Future<void>(() async {
      try {
        while (_dirty) {
          _dirty = false;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_stateKey, jsonEncode(_snapshot()));
        }
      } catch (_) {
      } finally {
        _saving = false;
      }
    });
  }

  Map<String, Object?> _snapshot() {
    final me = _me;
    return {
      'uid': _uid,
      'consent': _consentVersion,
      'dob': _dob?.toIso8601String(),
      'standards': _standardsAck,
      'premium': premium,
      'verification': _verification.name,
      'photos': [
        for (final p in _photos)
          if (MemoryImages.get(p.url) case final bytes?) {'id': p.mediaId, 'bytes': base64Encode(bytes)},
      ],
      'music': _music.connected
          ? {
              'synced': _music.syncedAt?.toIso8601String(),
              'artists': [
                for (final a in _music.artists) {...a.toJson(), 'visible': a.visible},
              ],
            }
          : null,
      'me': me == null
          ? null
          : {
              'id': me.id,
              'full_name': me.fullName,
              'age': me.age,
              'city': me.city,
              'bio': me.bio,
              'prompts': [
                for (final p in me.prompts) {...p.toJson(), 'question': p.question},
              ],
              'interest_tags': me.interestTags,
              'occupation': me.occupation,
              'education': me.education,
              'height_cm': me.heightCm,
              'gender': me.gender,
              'pronouns': me.pronouns,
              'languages': me.languages,
              'lifestyle_attributes': me.lifestyle,
              'music_top_artists': [for (final a in me.topArtists) a.toJson()],
              'music_linked': me.musicLinked,
              'onboarding_stage': me.onboardingStage,
              'is_onboarded': me.isOnboarded,
            },
    };
  }

  // ------------------------------------------------------ profile builder ----

  bool _standardsAck = false;
  final _photos = <PhotoSlot>[];
  var _music = MusicState.disconnected;

  PublicProfile _rescore(PublicProfile p) => p.copyWith(
    completionScore: ProfileCompletion.compute(
      photos: p.photos.length,
      occupation: p.occupation,
      education: p.education,
      lifestyleCount: p.lifestyle.length,
      languages: p.languages.length,
      tags: p.interestTags.length,
      bio: p.bio,
      prompts: p.prompts.length,
      music: p.musicLinked,
    ),
  );

  void _setMe(PublicProfile p) {
    _me = _rescore(p);
    _persist();
  }

  @override
  Future<void> acknowledgeStandards(String version) async {
    await _latency();
    _standardsAck = true;
    _persist();
  }

  void _validate(ProfilePatch patch) {
    for (final k in [ProfilePatch.bio, ProfilePatch.occupation, ProfilePatch.education, ProfilePatch.fullName]) {
      final v = patch.fields[k];
      if (v is String && ContactSanitizer.containsContactInfo(v)) {
        throw const AppException(AppErrorCode.contactInfo, 'Phone numbers, @handles and links are not allowed.');
      }
    }
    final prompts = patch.fields[ProfilePatch.prompts];
    if (prompts is List) {
      for (final e in prompts.cast<Map<String, Object?>>()) {
        final answer = (e['answer'] as String? ?? '').trim();
        if (answer.isEmpty || answer.length > promptAnswerMax) {
          throw const AppException(AppErrorCode.invalidInput, 'Answers are 1 to 150 characters');
        }
        if (ContactSanitizer.containsContactInfo(answer)) {
          throw const AppException(AppErrorCode.contactInfo, 'Answers can’t include phone numbers, handles or links');
        }
      }
    }
  }

  PublicProfile _apply(PublicProfile p, ProfilePatch patch) {
    final f = patch.fields;
    T? v<T>(String k) => f[k] as T?;
    return p.copyWith(
      fullName: v<String>(ProfilePatch.fullName),
      city: v<String>(ProfilePatch.city),
      bio: v<String>(ProfilePatch.bio),
      occupation: v<String>(ProfilePatch.occupation),
      clearOccupation: f.containsKey(ProfilePatch.occupation) && f[ProfilePatch.occupation] == null,
      education: v<String>(ProfilePatch.education),
      clearEducation: f.containsKey(ProfilePatch.education) && f[ProfilePatch.education] == null,
      heightCm: v<int>(ProfilePatch.heightCm),
      clearHeight: f.containsKey(ProfilePatch.heightCm) && f[ProfilePatch.heightCm] == null,
      gender: v<String>(ProfilePatch.gender),
      pronouns: v<String>(ProfilePatch.pronouns),
      clearPronouns: f.containsKey(ProfilePatch.pronouns) && f[ProfilePatch.pronouns] == null,
      languages: (f[ProfilePatch.languages] as List?)?.cast<String>(),
      lifestyle: (f[ProfilePatch.lifestyle] as Map?)?.cast<String, String>(),
      interestTags: (f[ProfilePatch.interestTags] as List?)?.cast<String>(),
      prompts: (f[ProfilePatch.prompts] as List?)?.cast<Map<String, Object?>>().map((e) {
        final id = e['prompt_id'] as String;
        return ProfilePrompt(promptId: id, question: promptById(id)!.question, answer: (e['answer'] as String).trim());
      }).toList(),
      onboardingStage: v<int>(ProfilePatch.onboardingStage),
    );
  }

  @override
  Future<void> createProfile({required String fullName, required String city, required ProfilePatch details}) async {
    await _latency();
    if (_dob == null) throw const AppException(AppErrorCode.dobRequired, 'Add your date of birth first.');
    _validate(details);
    final base =
        _me ??
        PublicProfile(
          id: meId,
          fullName: fullName,
          age: _ageFrom(_dob!),
          city: city,
          bio: '',
          primaryPhoto: null,
          isPremium: premium,
          isVerified: _verification == VerificationStatus.approved,
        );
    _setMe(_apply(base.copyWith(fullName: fullName, city: city), details));
  }

  @override
  Future<void> updateProfile(ProfilePatch patch) async {
    await _latency();
    final me = _me;
    if (me == null) throw const AppException(AppErrorCode.unknown, 'Create your profile first.');
    _validate(patch);
    _setMe(_apply(me, patch));
  }

  @override
  Future<void> completeOnboarding() async {
    await _latency();
    final me = _me;
    if (me == null) throw const AppException(AppErrorCode.unknown, 'Create your profile first.');
    final missing = [
      if (!_standardsAck) 'community_standards',
      if (_dob == null) 'birthdate',
      if (me.gender == null) 'gender',
      if (me.photos.length < photosMin) 'photos',
      if (me.interestTags.length < interestsMin) 'interests',
      if (me.prompts.length < promptsMin) 'prompts',
    ];
    if (missing.isNotEmpty) {
      throw AppException(AppErrorCode.onboardingIncomplete, 'Profile incomplete: ${missing.join(', ')}');
    }
    _setMe(me.copyWith(isOnboarded: true, onboardingStage: 8));
  }

  void _syncPhotos() {
    final me = _me;
    if (me != null) _setMe(me.copyWith(photos: [for (final p in _photos) p.url]));
  }

  @override
  Future<List<PhotoSlot>> photoSlots() async => List.of(_photos);

  @override
  Future<ImageUploadStatus> uploadPhoto(Uint8List bytes, {required String mime, String? replaces}) async {
    await _latency();
    if (bytes.lengthInBytes > 100 * 1024) {
      throw const AppException(AppErrorCode.imageRejected, 'Photos must be optimised below 100 KB before upload.');
    }
    final slot = PhotoSlot(mediaId: _uuid.v4(), url: MemoryImages.put(bytes));
    final i = replaces == null ? -1 : _photos.indexWhere((p) => p.mediaId == replaces);
    if (i >= 0) {
      MemoryImages.remove(_photos[i].url); // storage hygiene, as on the server
      _photos[i] = slot;
    } else {
      if (_photos.length >= maxPhotoSlots) throw const AppException(AppErrorCode.photoSlotsFull, 'All 6 photo slots are full.');
      _photos.add(slot);
    }
    _syncPhotos();
    return ImageUploadStatus.approved;
  }

  @override
  Future<void> removePhoto(String mediaId) async {
    await _latency();
    final i = _photos.indexWhere((p) => p.mediaId == mediaId);
    if (i < 0) throw const AppException(AppErrorCode.unknown, 'Photo not found');
    MemoryImages.remove(_photos.removeAt(i).url);
    _syncPhotos();
  }

  @override
  Future<void> reorderPhotos(List<String> mediaIds) async {
    final current = {for (final p in _photos) p.mediaId: p};
    if (mediaIds.length != current.length || !mediaIds.every(current.containsKey) || mediaIds.toSet().length != mediaIds.length) {
      throw const AppException(AppErrorCode.invalidInput, 'Order must contain exactly your current photos');
    }
    _photos
      ..clear()
      ..addAll(mediaIds.map((id) => current[id]!));
    _syncPhotos();
  }

  PublicProfile _withAffinity(PublicProfile p) {
    final mine = _me;
    final myArtists = {for (final a in mine?.topArtists ?? const <MusicArtist>[]) a.id};
    final myTags = {...?mine?.interestTags};
    return p.copyWith(
      sharedArtistIds: [
        for (final a in p.topArtists)
          if (myArtists.contains(a.id)) a.id,
      ],
      sharedInterestCount: p.interestTags.where(myTags.contains).length,
    );
  }

  @override
  Future<PublicProfile> profileCard(String userId) async {
    if (userId == meId) return (await myProfile())!;
    final s = _people[userId];
    if (s == null) throw const AppException(AppErrorCode.notConnected, 'This profile isn’t available.');
    return _withAffinity(s.profile);
  }

  @override
  Future<SwipeOutcome> replyToPrompt(String targetId, String promptId, String text) async {
    final t = text.trim();
    if (t.isEmpty || t.length > promptAnswerMax) {
      throw const AppException(AppErrorCode.invalidInput, 'Replies are 1 to 150 characters');
    }
    if (ContactSanitizer.containsContactInfo(t)) {
      throw const AppException(AppErrorCode.contactInfo, 'Replies can’t include phone numbers, handles or links');
    }
    final seed = _people[targetId];
    if (seed == null || !seed.profile.prompts.any((p) => p.promptId == promptId)) {
      throw const AppException(AppErrorCode.unknown, 'That prompt is no longer on their profile');
    }
    final outcome = await swipe(targetId, follow: true);
    if (outcome == SwipeOutcome.matched) {
      await sendText(targetId, t);
    } else {
      _swipes[(meId, targetId)]
        ?..introPromptId = promptId
        ..introText = t;
    }
    return outcome;
  }

  // -------------------------------------------------------------- music ----

  static const _demoArtists = [
    MusicArtist(id: 'demoSushinShyam01', name: 'Sushin Shyam', genres: ['malayalam indie', 'film score']),
    MusicArtist(id: 'demoWhenChaiMet01', name: 'When Chai Met Toast', genres: ['indian indie', 'folk pop']),
    MusicArtist(id: 'demoPrateekKuhad1', name: 'Prateek Kuhad', genres: ['indian singer-songwriter']),
    MusicArtist(id: 'demoARRahman00001', name: 'A. R. Rahman', genres: ['filmi', 'tamil']),
    MusicArtist(id: 'demoThaikkudam001', name: 'Thaikkudam Bridge', genres: ['malayalam rock', 'fusion']),
    MusicArtist(id: 'demoHanumankind01', name: 'Hanumankind', genres: ['indian hip hop']),
    MusicArtist(id: 'demoAnirudhRavi01', name: 'Anirudh Ravichander', genres: ['tamil pop', 'filmi']),
    MusicArtist(id: 'demoShreyaGhosh01', name: 'Shreya Ghoshal', genres: ['filmi']),
  ];

  void _publishMusic() {
    final me = _me;
    if (me == null) return;
    _setMe(me.copyWith(musicLinked: _music.connected, topArtists: _music.artists.where((a) => a.visible).toList()));
  }

  @override
  Future<MusicState> musicState() async => _music;

  /// No Spotify in the offline demo: connecting imports a sample list.
  @override
  Future<Uri> musicAuthorizeUrl() async {
    await _latency();
    _music = MusicState(status: MusicStatus.active, artists: _demoArtists, syncedAt: DateTime.now());
    _publishMusic();
    return Uri.parse('vouby-demo://music-connected');
  }

  @override
  Future<MusicSyncResult> syncMusic({bool force = false}) async =>
      _music.connected ? MusicSyncResult.cached : MusicSyncResult.disconnected;

  @override
  Future<void> setArtistVisibility(String artistId, {required bool visible}) async {
    if (!_music.artists.any((a) => a.id == artistId)) throw const AppException(AppErrorCode.unknown, 'Artist not found');
    _music = MusicState(
      status: _music.status,
      syncedAt: _music.syncedAt,
      artists: [for (final a in _music.artists) a.id == artistId ? a.copyWith(visible: visible) : a],
    );
    _publishMusic();
  }

  @override
  Future<void> disconnectMusic() async {
    await _latency();
    _music = MusicState.disconnected;
    _publishMusic();
  }

  @override
  Future<PrivateProfile> privateProfileOf(String userId) async {
    if (userId == meId) return _myPrivate;
    // Open profiles: every signed-in user sees the full gallery and interests.
    final s = _people[userId]!;
    return PrivateProfile(interests: s.profile.interestTags, gallery: s.profile.photos.skip(1).toList());
  }

  // ---------------------------------------------------------------- deck ----

  @override
  Future<List<PublicProfile>> fetchFeed() async {
    await _latency();
    final now = DateTime.now();
    final myCity = _me?.city.toLowerCase();
    final list = _people.values.where((s) {
      if (_hiddenPendingReview.contains(s.profile.id)) return false;
      final mine = _swipes[(meId, s.profile.id)];
      if (mine != null &&
          !(mine.action == 'pass' && now.difference(mine.createdAt) > const Duration(days: AppConfig.passHideDays))) {
        return false;
      }
      final theirs = _swipes[(s.profile.id, meId)];
      return theirs == null || theirs.action == 'follow_requested';
    }).toList();

    int rank(_Seed s) {
      final sameCity = s.profile.city.toLowerCase() == myCity;
      if (s.profile.isPremium && sameCity) return 0; // Kerala City Boost
      if (sameCity) return 1;
      if (_swipes[(s.profile.id, meId)] != null) return 2;
      return 3;
    }

    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list.map((s) => _withAffinity(s.profile)).toList();
  }

  @override
  Future<SwipeOutcome> swipe(String targetId, {required bool follow}) async {
    final existing = _swipes[(meId, targetId)];
    if (existing != null && existing.action == 'pass') _swipes.remove((meId, targetId));

    if (!follow) {
      _swipes[(meId, targetId)] = _Swipe(meId, targetId, 'pass');
      return SwipeOutcome.passed;
    }

    final reverse = _swipes[(targetId, meId)];
    if (reverse != null && reverse.action == 'follow_requested') {
      reverse.action = 'accepted';
      reverse.respondedAt = DateTime.now();
      _social.add(null);
      return SwipeOutcome.matched;
    }

    final row = _Swipe(meId, targetId, 'follow_requested');
    _swipes[(meId, targetId)] = row;

    // Simulate the other person reviewing the request.
    final seed = _people[targetId];
    if (seed != null && seed.acceptsFollows) {
      Timer(Duration(seconds: 4 + _rand.nextInt(4)), () {
        if (row.action != 'follow_requested') return;
        row.action = 'accepted';
        row.respondedAt = DateTime.now();
        _social.add(null);
        _scheduleReply(targetId, delay: const Duration(seconds: 3), opener: true);
      });
    }
    return SwipeOutcome.requested;
  }

  // ------------------------------------------------------------ requests ----

  @override
  Future<IncomingRequests> incomingRequests() async {
    await _latency();
    final pending = _swipes.values.where((s) => s.receiver == meId && s.action == 'follow_requested').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return IncomingRequests(
      count: pending.length,
      // Same rule as the RLS policy: identities only for Fast-Track members.
      requests: premium
          ? [
              for (final s in pending)
                FollowRequest(
                  id: s.id,
                  sender: _withAffinity(_people[s.sender]!.profile),
                  createdAt: s.createdAt,
                  introPromptId: s.introPromptId,
                  introText: s.introText,
                ),
            ]
          : const [],
    );
  }

  @override
  Future<void> respondToRequest(String requestId, {required bool accept}) async {
    if (!premium) throw const AppException(AppErrorCode.subscriptionRequired, 'Seeing requests is part of Fast-Track');
    final row = _swipes.values.firstWhere(
      (s) => s.id == requestId && s.receiver == meId && s.action == 'follow_requested',
      orElse: () => throw const AppException(AppErrorCode.unknown, 'Request not found'),
    );
    row.action = accept ? 'accepted' : 'rejected';
    row.respondedAt = DateTime.now();
    _social.add(null);
    if (accept) _scheduleReply(row.sender, delay: const Duration(seconds: 2), opener: true);
  }

  @override
  Future<List<Connection>> connections() async {
    final rows = _swipes.values.where((s) => s.action == 'accepted' && (s.sender == meId || s.receiver == meId)).toList()
      ..sort((a, b) => (b.respondedAt ?? b.createdAt).compareTo(a.respondedAt ?? a.createdAt));
    return [
      for (final r in rows)
        () {
          final peer = r.sender == meId ? r.receiver : r.sender;
          final thread = _threads[peer] ?? const [];
          final last = thread.isEmpty ? null : thread.last;
          return Connection(
            profile: _people[peer]!.profile,
            connectedAt: r.respondedAt ?? r.createdAt,
            lastMessage: last == null ? null : (last.isVoice ? '🎤 Voice note' : last.content),
            unread: thread.where((m) => m.receiverId == meId && !m.isRead).length,
            introPromptId: r.introPromptId,
            introText: r.introText,
            introFromMe: r.sender == meId,
          );
        }(),
    ];
  }

  @override
  Stream<void> socialChanges() => _social.stream;

  @override
  Future<bool> serverPremium() async => premium;

  void setPremium(bool value) {
    premium = value;
    _persist();
    _social.add(null);
  }

  // ---------------------------------------------------------------- chat ----

  @override
  Stream<List<ChatMessage>> watchMessages(String peerId) {
    final ctl = _threadCtl.putIfAbsent(peerId, () => StreamController.broadcast());
    return Stream.multi((listener) {
      listener.add(List.unmodifiable(_threads[peerId] ?? const []));
      final sub = ctl.stream.listen(listener.add);
      listener.onCancel = sub.cancel;
    });
  }

  void _push(String peerId, ChatMessage m) {
    (_threads[peerId] ??= []).add(m);
    _threadCtl[peerId]?.add(List.unmodifiable(_threads[peerId]!));
    _social.add(null);
  }

  @override
  Future<void> sendText(String peerId, String text) async {
    if (!premium) throw const AppException(AppErrorCode.subscriptionRequired, 'Messaging is part of Fast-Track');
    if (!_connected(meId, peerId)) {
      throw const AppException(AppErrorCode.notConnected, 'Chat unlocks once the follow request is accepted.');
    }
    _push(peerId, _msg(meId, peerId, content: text));
    _scheduleReply(peerId);
  }

  @override
  Future<void> sendVoice(String peerId, Uint8List aacBytes, {String? localPath, Duration duration = Duration.zero}) async {
    if (!premium) throw const AppException(AppErrorCode.subscriptionRequired, 'Messaging is part of Fast-Track');
    if (!_connected(meId, peerId)) {
      throw const AppException(AppErrorCode.notConnected, 'Chat unlocks once the follow request is accepted.');
    }
    _push(peerId, _msg(meId, peerId, audio: localPath ?? ''));
    _scheduleReply(peerId, voiceReaction: true);
  }

  @override
  Future<void> markThreadRead(String peerId) async {
    final t = _threads[peerId];
    if (t == null) return;
    var changed = false;
    for (var i = 0; i < t.length; i++) {
      final m = t[i];
      if (m.receiverId == meId && !m.isRead) {
        t[i] = ChatMessage(
          id: m.id,
          senderId: m.senderId,
          receiverId: m.receiverId,
          content: m.content,
          localAudioPath: m.localAudioPath,
          isRead: true,
          createdAt: m.createdAt,
        );
        changed = true;
      }
    }
    if (changed) {
      _threadCtl[peerId]?.add(List.unmodifiable(t));
      _social.add(null);
    }
  }

  @override
  bool get isEndToEndEncrypted => false;

  @override
  Future<VoicePlayback> voicePlayback(ChatMessage message) async => VoicePlayback.url(message.localAudioPath ?? '');

  @override
  Future<String?> safetyNumber(String peerId) async => null;

  void _endConnection(String peerId) {
    for (final key in [(meId, peerId), (peerId, meId)]) {
      final row = _swipes[key];
      if (row != null && row.action == 'accepted') row.action = 'rejected';
    }
    _threads.remove(peerId);
    _social.add(null);
  }

  @override
  Future<void> unmatch(String peerId) async => _endConnection(peerId);

  @override
  Future<void> blockUser(String peerId) async {
    _endConnection(peerId);
    _swipes.remove((peerId, meId));
    _swipes[(meId, peerId)] = _Swipe(meId, peerId, 'rejected');
    _social.add(null);
  }

  @override
  Future<void> report(
    String peerId,
    ReportReason reason, {
    String? details,
    List<ChatMessage> evidence = const [],
    bool block = true,
  }) async {
    await _latency();
    // Same rule as the server: "Appears under 18" hides the profile from
    // discovery until a moderator reviews it.
    if (reason == ReportReason.underage) _hiddenPendingReview.add(peerId);
    if (block) await blockUser(peerId);
  }

  final _hiddenPendingReview = <String>{};

  // ------------------------------------------------------ consent & age ----

  String? _consentVersion;
  DateTime? _dob;

  static int _ageFrom(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
    return age;
  }

  @override
  Future<String?> acceptedPolicyVersion() async => _consentVersion;

  @override
  Future<void> recordConsent(String version) async {
    _consentVersion = version;
    _persist();
  }

  @override
  Future<bool> hasDob() async => _dob != null;

  @override
  Future<int> setDob(DateTime dob) async {
    await _latency();
    if (_dob != null) throw const AppException(AppErrorCode.dobLocked, 'Your date of birth can’t be changed.');
    final age = _ageFrom(dob);
    if (dob.isAfter(DateTime.now()) || age > 100) throw const AppException(AppErrorCode.unknown, 'Enter a valid date of birth.');
    if (age < AppConfig.minimumAge) {
      throw const AppException(AppErrorCode.underage, 'Vouby is only for people aged 18 and over.');
    }
    _dob = dob;
    _persist();
    return age;
  }

  // -------------------------------------------------------- verification ----

  var _verification = VerificationStatus.none;
  static const _poses = [
    'Touch your nose with your right index finger',
    'Give a thumbs up with your left hand',
    'Make a peace sign next to your right cheek',
    'Cover your left eye with your left hand',
  ];

  @override
  Future<VerificationStatus> verificationStatus() async => _verification;

  @override
  Future<VerificationStart> startVerification() async {
    await _latency();
    if (_verification == VerificationStatus.pending) {
      throw const AppException(AppErrorCode.verificationPending, 'Your verification is being reviewed.');
    }
    return VerificationStart(requestId: _uuid.v4(), pose: _poses[_rand.nextInt(_poses.length)]);
  }

  @override
  Future<void> submitVerificationSelfie(String requestId, Uint8List jpeg) async {
    await _latency();
    _verification = VerificationStatus.pending;
    // Demo has no staff: approve after a short delay so the badge can be seen.
    Timer(const Duration(seconds: 5), () {
      _verification = VerificationStatus.approved;
      _me = _me?.copyWith(isVerified: true);
      _persist();
      _social.add(null);
    });
  }

  @override
  Future<List<VerificationItem>> verificationQueue() async => const [];

  @override
  Future<void> reviewVerification(String requestId, {required bool approve}) async {}

  final _demoSessionStart = DateTime.now();

  @override
  Future<List<SessionInfo>> sessions() async => [
    SessionInfo(
      id: 's1',
      createdAt: _demoSessionStart,
      lastActive: DateTime.now(),
      userAgent: 'This device',
      isCurrent: true,
      aal: _mfaVerified ? 'aal2' : 'aal1',
    ),
  ];

  @override
  Future<void> revokeSession(String sessionId) async {}

  @override
  Future<void> signOutOtherSessions() async {}

  @override
  Future<List<DeviceInfo>> devices() async => [
    DeviceInfo(
      id: 'd1',
      label: 'Android phone',
      platform: 'android',
      createdAt: _demoSessionStart,
      lastSeen: DateTime.now(),
      isThisDevice: true,
    ),
  ];

  @override
  Future<void> revokeDevice(String deviceId) async {}

  bool _mfaVerified = false;
  String? _mfaFactor;

  @override
  Future<MfaState> mfaState() async => MfaState(
    verifiedFactorIds: [if (_mfaVerified && _mfaFactor != null) _mfaFactor!],
    sessionIsAal2: _mfaVerified,
    needsChallenge: false,
  );

  @override
  Future<TotpEnrollment> enrollTotp() async {
    _mfaFactor = 'demo-factor';
    return const TotpEnrollment(
      factorId: 'demo-factor',
      secret: 'DEMODEMODEMODEMO',
      uri: 'otpauth://totp/Vouby:demo?secret=DEMODEMODEMODEMO&issuer=Vouby',
    );
  }

  @override
  Future<void> verifyTotp(String factorId, String code) async {
    await _latency();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const AppException(AppErrorCode.mfaRequired, 'Enter the 6-digit code (any digits work in demo).');
    }
    _mfaVerified = true;
  }

  @override
  Future<void> removeTotp(String factorId) async {
    _mfaVerified = false;
    _mfaFactor = null;
  }

  @override
  Future<void> deleteAccount() async {
    await _latency();
    _me = null;
    await signOut();
  }

  @override
  Future<String?> staffRole() async => null;

  @override
  Future<Map<String, dynamic>> securityOverview() async =>
      throw const AppException(AppErrorCode.unknown, 'Not available in demo');

  @override
  Future<List<ReportSummary>> openReports() async => const [];

  @override
  Future<Map<String, dynamic>> openReportEvidence(String reportId, String accessReason) async => const {};

  @override
  Future<void> resolveReport(String reportId, {required bool actioned, required String resolution}) async {}

  @override
  Future<List<PendingMedia>> pendingMedia() async => const [];

  @override
  Future<void> reviewMedia(String mediaId, {required bool approve}) async {}

  // ------------------------------------------------------------- helpers ----

  bool _connected(String a, String b) => _swipes[(a, b)]?.action == 'accepted' || _swipes[(b, a)]?.action == 'accepted';

  ChatMessage _msg(String from, String to, {String? content, String? audio, DateTime? at}) => ChatMessage(
    id: _uuid.v4(),
    senderId: from,
    receiverId: to,
    content: content,
    localAudioPath: audio,
    isRead: false,
    createdAt: at ?? DateTime.now(),
  );

  static const _openers = ['Hey! Thanks for the follow 😊', 'Hii, nice to connect here!', 'Heyy, your profile made me smile 🙂'];
  static const _replies = [
    'Haha that’s so true 😄',
    'Same here! Have you been to the new café near Marine Drive?',
    'Ooh tell me more',
    'I’m free this weekend actually',
    'That sounds fun!',
    'Wait, really? 😂',
    'What kind of music are you into?',
  ];

  void _scheduleReply(String peerId, {Duration? delay, bool opener = false, bool voiceReaction = false}) {
    Timer(delay ?? Duration(milliseconds: 1600 + _rand.nextInt(1800)), () {
      if (!_connected(meId, peerId)) return;
      final text = opener
          ? _openers[_rand.nextInt(_openers.length)]
          : voiceReaction
          ? 'Aww I love your voice 🙈'
          : _replies[_rand.nextInt(_replies.length)];
      _push(peerId, _msg(peerId, meId, content: text));
    });
  }

  Future<void> _latency() => Future.delayed(Duration(milliseconds: 250 + _rand.nextInt(250)));

  void _seed() {
    final seeds = <_Seed>[
      _Seed(
        'Ananya Menon',
        24,
        'Kochi',
        'Filter coffee, Fort Kochi sunsets and too many plants 🌿',
        ['Photography', 'Kathakali', 'Cafés', 'Indie music'],
        premium: true,
        accepts: true,
      ),
      _Seed('Arjun Nair', 27, 'Kochi', 'Product designer. Weekend trekker. Will judge your biryani spot.', [
        'Trekking',
        'Design',
        'Football',
        'Biryani',
      ], accepts: true),
      _Seed(
        'Meera Pillai',
        23,
        'Thiruvananthapuram',
        'Med student who still finds time for Carnatic music 🎶',
        ['Music', 'Reading', 'Beaches'],
        accepts: false,
        verified: false,
      ),
      _Seed('Rahul Krishnan', 26, 'Kozhikode', 'Halwa connoisseur. Beach runs at 6am. Ask me about F1.', [
        'Running',
        'F1',
        'Food',
      ], accepts: true),
      _Seed(
        'Diya Thomas',
        25,
        'Kochi',
        'Marketing by day, salsa by night 💃',
        ['Dance', 'Travel', 'Brunch'],
        premium: true,
        accepts: true,
      ),
      _Seed(
        'Nikhil Varma',
        28,
        'Thrissur',
        'Pooram every year. Engineer, amateur chef, dog dad 🐕',
        ['Cooking', 'Dogs', 'Festivals'],
        accepts: false,
        verified: false,
      ),
      _Seed('Sneha Joseph', 22, 'Kottayam', 'Literature grad. Rain + books + chai = perfect day.', [
        'Books',
        'Poetry',
        'Chai',
      ], accepts: true),
      _Seed('Aditya Shenoy', 29, 'Kochi', 'Startup founder. Ocean kayaker. Terrible at small talk, great at deep talk.', [
        'Kayaking',
        'Startups',
        'Podcasts',
      ], accepts: true),
      _Seed('Fathima Rasheed', 24, 'Kozhikode', 'Architecture student 🏛️ Sketching old Calicut streets.', [
        'Sketching',
        'Heritage',
        'Film',
      ], accepts: true),
      _Seed(
        'Vishnu Prasad',
        25,
        'Thiruvananthapuram',
        'Cricket, coding and coconut everything.',
        ['Cricket', 'Gaming', 'Coding'],
        accepts: false,
        verified: false,
      ),
      _Seed('Lakshmi Iyer', 26, 'Palakkad', 'Bharatanatyam dancer & UX writer. Looking for good conversations.', [
        'Dance',
        'Writing',
        'Yoga',
      ], accepts: true),
      _Seed('Kiran George', 27, 'Alappuzha', 'Houseboat sunsets & backwater cycling 🚲', [
        'Cycling',
        'Photography',
        'Nature',
      ], accepts: true),
    ];
    for (final s in seeds) {
      _people[s.profile.id] = s;
    }

    final now = DateTime.now();
    // Incoming follow requests (the "Who Requested You" tab).
    _swipes[(
      seeds[4].profile.id,
      meId,
    )] = _Swipe(seeds[4].profile.id, meId, 'follow_requested', now.subtract(const Duration(hours: 2)))
      ..introPromptId = 'p1'
      ..introText = 'Okay but which café? I need names.';
    _swipes[(seeds[6].profile.id, meId)] = _Swipe(
      seeds[6].profile.id,
      meId,
      'follow_requested',
      now.subtract(const Duration(hours: 5)),
    );
    _swipes[(seeds[9].profile.id, meId)] = _Swipe(
      seeds[9].profile.id,
      meId,
      'follow_requested',
      now.subtract(const Duration(days: 1)),
    );

    // One existing mutual connection with history so chat is explorable immediately.
    final a = seeds[0].profile.id;
    _swipes[(meId, a)] = _Swipe(meId, a, 'accepted', now.subtract(const Duration(days: 1)))
      ..respondedAt = now.subtract(const Duration(hours: 20));
    _threads[a] = [
      _msg(a, meId, content: 'Hey! Thanks for the follow 😊', at: now.subtract(const Duration(hours: 19))),
      _msg(meId, a, content: 'Hi Ananya! Loved your sunset pics', at: now.subtract(const Duration(hours: 18))),
      _msg(a, meId, content: 'Haha thank you! Have you tried Kashi Art Café?', at: now.subtract(const Duration(minutes: 30))),
    ];
  }
}

class _Seed {
  _Seed(
    String name,
    int age,
    String city,
    String bio,
    List<String> interests, {
    bool premium = false,
    required bool accepts,
    bool verified = true,
  }) : acceptsFollows = accepts,
       profile = _build(name, age, city, bio, interests, premium, verified);

  static PublicProfile _build(
    String name,
    int age,
    String city,
    String bio,
    List<String> interests,
    bool premium,
    bool verified,
  ) {
    final first = name.split(' ').first;
    final key = first.toLowerCase();
    final x = _demoDetails[key] ?? const _Details();
    final photos = [
      'asset:assets/demo/p_$key.jpg',
      for (var i = 0; i < 5; i++) 'asset:assets/demo/g_${(name.length * 3 + i * 5) % 12}.jpg',
    ];
    return PublicProfile(
      id: 'u_$key',
      fullName: name,
      age: age,
      city: city,
      bio: bio,
      primaryPhoto: photos.first,
      isPremium: premium,
      isVerified: verified,
      photoCount: photos.length,
      photos: photos,
      interestTags: [...interests, ...x.moreTags],
      occupation: x.occupation,
      education: x.education,
      heightCm: x.height,
      gender: x.gender,
      pronouns: x.pronouns,
      languages: x.languages,
      lifestyle: x.lifestyle,
      prompts: [
        for (final (id, answer) in x.prompts) ProfilePrompt(promptId: id, question: promptById(id)!.question, answer: answer),
      ],
      topArtists: [
        for (final a in DemoBackend._demoArtists)
          if (x.artists.contains(a.name)) a,
      ],
      musicLinked: x.artists.isNotEmpty,
      isOnboarded: true,
    );
  }

  final PublicProfile profile;
  final bool acceptsFollows;
}

class _Details {
  const _Details({
    this.occupation,
    this.education,
    this.height,
    this.gender,
    this.pronouns,
    this.lifestyle = const {},
    this.prompts = const [],
    this.artists = const [],
    this.moreTags = const [],
  });
  final String? occupation;
  final String? education;
  final int? height;
  final String? gender;
  final String? pronouns;
  final List<String> languages = const ['Malayalam', 'English'];
  final Map<String, String> lifestyle;
  final List<(String, String)> prompts;
  final List<String> artists;
  final List<String> moreTags;
}

const _demoDetails = <String, _Details>{
  'ananya': _Details(
    occupation: 'Photographer',
    education: 'St. Teresa’s College',
    height: 162,
    gender: 'woman',
    pronouns: 'she/her',
    lifestyle: {'intention': 'long_term', 'activity': 'sometimes', 'drinking': 'socially', 'zodiac': 'libra'},
    prompts: [
      ('p1', 'The 6 pm light on the Fort Kochi ferry. I’ve photographed it a hundred times.'),
      ('p6', 'Cafés in Mattancherry that still let you sit for three hours.'),
    ],
    artists: ['When Chai Met Toast', 'Prateek Kuhad', 'Sushin Shyam'],
    moreTags: ['Filter coffee'],
  ),
  'arjun': _Details(
    occupation: 'Product designer',
    education: 'NID Ahmedabad',
    height: 178,
    gender: 'man',
    pronouns: 'he/him',
    lifestyle: {'intention': 'long_term_open', 'activity': 'often', 'drinking': 'socially', 'smoking': 'never'},
    prompts: [
      ('p2', 'Kozhikode biryani beats Thalassery biryani. Fight me, politely.'),
      ('p8', 'Finishing a trek before the group that left an hour earlier.'),
    ],
    artists: ['Thaikkudam Bridge', 'A. R. Rahman', 'Hanumankind'],
  ),
  'meera': _Details(
    occupation: 'Medical student',
    education: 'Government Medical College',
    height: 158,
    gender: 'woman',
    lifestyle: {'intention': 'figuring_out', 'drinking': 'never', 'smoking': 'never', 'zodiac': 'virgo'},
    prompts: [('p9', 'Veena. Grade 3 and my neighbours are very patient.'), ('p13', 'You ask a follow-up question.')],
    artists: ['Shreya Ghoshal', 'A. R. Rahman'],
  ),
  'rahul': _Details(
    occupation: 'Data analyst',
    education: 'NIT Calicut',
    height: 175,
    gender: 'man',
    lifestyle: {'intention': 'long_term', 'activity': 'daily', 'drinking': 'sober'},
    prompts: [
      ('p10', 'Formula 1 tyre strategy. Ask me why Monaco is a parade.'),
      ('p4', 'Beach run at 6, halwa on Mittai Theruvu at 11, nap till 4.'),
    ],
    artists: ['Anirudh Ravichander', 'Hanumankind'],
  ),
  'diya': _Details(
    occupation: 'Marketing lead',
    education: 'MBA, Kochi',
    height: 163,
    gender: 'woman',
    pronouns: 'she/her',
    lifestyle: {'intention': 'long_term', 'activity': 'often', 'drinking': 'socially', 'zodiac': 'leo', 'culture': 'malayali'},
    prompts: [
      ('p4', 'Fort Kochi at sunrise, appam for breakfast, then a nap I won’t apologise for.'),
      ('p11', 'You text back with full sentences and actually make the plan.'),
      ('p16', 'I’ve danced on a stage in Lisbon. I can whistle with two fingers. I like early mornings.'),
    ],
    artists: ['Sushin Shyam', 'Prateek Kuhad', 'When Chai Met Toast', 'A. R. Rahman'],
  ),
  'nikhil': _Details(
    occupation: 'Civil engineer',
    education: 'GEC Thrissur',
    height: 180,
    gender: 'man',
    lifestyle: {'intention': 'long_term', 'drinking': 'socially'},
    prompts: [
      ('p15', 'The year I tried to cook sadya for 30 people. There was a fire. A small one.'),
      ('p12', 'Bring your dog. Mine will do the rest.'),
    ],
    artists: ['Thaikkudam Bridge'],
  ),
  'sneha': _Details(
    occupation: 'Copy editor',
    education: 'CMS College Kottayam',
    height: 160,
    gender: 'woman',
    pronouns: 'she/her',
    lifestyle: {'intention': 'long_term', 'activity': 'rarely', 'drinking': 'never', 'zodiac': 'pisces'},
    prompts: [
      ('p6', 'Malayalam novels that should be translated. I have a list of eleven.'),
      ('p1', 'Rain on the tin roof at my grandmother’s place, plus chai.'),
    ],
    artists: ['Prateek Kuhad', 'Shreya Ghoshal'],
  ),
  'aditya': _Details(
    occupation: 'Founder',
    education: 'IIT Madras',
    height: 183,
    gender: 'man',
    lifestyle: {'intention': 'long_term_open', 'activity': 'daily', 'drinking': 'socially'},
    prompts: [
      ('p14', 'Small talk is a skill, not a waste of time. I’m bad at it anyway.'),
      ('p5', 'Kayaking the Kumbalangi backwaters at full moon.'),
    ],
    artists: ['Hanumankind', 'Sushin Shyam'],
  ),
  'fathima': _Details(
    occupation: 'Architecture student',
    education: 'NIT Calicut',
    height: 157,
    gender: 'woman',
    lifestyle: {'intention': 'figuring_out', 'drinking': 'never', 'smoking': 'never'},
    prompts: [
      ('p10', 'Calicut’s old warehouse roofs. The tiles have stamps from 1880s factories.'),
      ('p3', 'Finding a 1930s building plan at a raddi shop last Tuesday.'),
    ],
    artists: ['A. R. Rahman', 'When Chai Met Toast'],
  ),
  'vishnu': _Details(
    occupation: 'Software engineer',
    education: 'CET Trivandrum',
    height: 172,
    gender: 'man',
    lifestyle: {'activity': 'sometimes', 'drinking': 'socially'},
    prompts: [('p8', 'Gully cricket. I keep score in a notebook.'), ('p2', 'Pineapple belongs in pulissery and on pizza.')],
    artists: ['Anirudh Ravichander'],
  ),
  'lakshmi': _Details(
    occupation: 'UX writer',
    education: 'Kalakshetra',
    height: 165,
    gender: 'woman',
    pronouns: 'she/her',
    lifestyle: {'intention': 'long_term', 'activity': 'daily', 'drinking': 'never', 'zodiac': 'cancer'},
    prompts: [('p7', '“Will turn your grocery list into a poem.” – my roommate'), ('p13', 'You’re kind to auto drivers.')],
    artists: ['Shreya Ghoshal', 'Prateek Kuhad'],
  ),
  'kiran': _Details(
    occupation: 'Travel guide',
    education: 'SD College Alappuzha',
    height: 176,
    gender: 'man',
    lifestyle: {'intention': 'short_term_open', 'activity': 'daily'},
    prompts: [('p5', 'Cycling the full Vembanad loop in one day.'), ('p6', 'Houseboats that don’t blast music.')],
    artists: ['Thaikkudam Bridge', 'When Chai Met Toast'],
  ),
};

class _Swipe {
  _Swipe(this.sender, this.receiver, this.action, [DateTime? at]) : id = const Uuid().v4(), createdAt = at ?? DateTime.now();

  final String id;
  final String sender;
  final String receiver;
  String action;
  final DateTime createdAt;
  DateTime? respondedAt;
  String? introPromptId;
  String? introText;
}
