import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../core/config.dart';
import '../core/errors.dart';
import '../core/sanitizer.dart';
import '../models/follow_request.dart';
import '../models/message.dart';
import '../models/profile.dart';
import 'backend.dart';
import 'memory_images.dart';

/// Fully offline backend used when no Supabase credentials are supplied.
/// Mirrors the server rules (limits, RLS visibility, mutual consent) so the
/// demo behaves like production.
class DemoBackend implements FinderBackend {
  DemoBackend() {
    _seed();
  }

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
  PrivateProfile _myPrivate = PrivateProfile.empty;

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
  }

  @override
  Future<void> signOut() async {
    _uid = null;
    _auth.add(null);
  }

  // ------------------------------------------------------------- profile ----

  @override
  Future<PublicProfile?> myProfile() async => _me?.copyWith(isPremium: premium);

  @override
  Future<PrivateProfile> myPrivateProfile() async => _myPrivate;

  @override
  Future<void> saveProfile(ProfileDraft d) async {
    await _latency();
    if (ContactSanitizer.containsContactInfo(d.bio)) {
      throw const AppException(AppErrorCode.contactInfo, 'Phone numbers, @handles and links are not allowed.');
    }
    var photo = _me?.primaryPhoto;
    if (d.primaryPhotoWebp != null) photo = MemoryImages.put(d.primaryPhotoWebp!);
    _me = PublicProfile(
      id: meId,
      fullName: d.fullName,
      age: d.age,
      city: d.city,
      bio: d.bio,
      primaryPhoto: photo,
      isPremium: premium,
    );
    _myPrivate = PrivateProfile(
      interests: d.interests,
      gallery: [..._myPrivate.gallery, ...d.newGalleryWebp.map(MemoryImages.put)].take(9).toList(),
    );
  }

  @override
  Future<PrivateProfile> privateProfileOf(String userId) async {
    if (userId == meId) return _myPrivate;
    if (!_connected(meId, userId)) return PrivateProfile.empty;
    final s = _people[userId]!;
    return PrivateProfile(interests: s.interests, gallery: s.gallery);
  }

  // ---------------------------------------------------------------- deck ----

  @override
  Future<List<PublicProfile>> fetchFeed() async {
    await _latency();
    final now = DateTime.now();
    final myCity = _me?.city.toLowerCase();
    final list = _people.values.where((s) {
      final mine = _swipes[(meId, s.profile.id)];
      if (mine != null &&
          !(mine.action == 'pass' &&
              now.difference(mine.createdAt) > const Duration(days: AppConfig.passHideDays))) {
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
    return list.map((s) => s.profile).toList();
  }

  @override
  Future<int> remainingSwipes() async {
    if (premium) return -1;
    final since = DateTime.now().subtract(const Duration(hours: 24));
    final used = _swipes.values
        .where((s) => s.sender == meId && s.action != 'pass' && s.createdAt.isAfter(since))
        .length;
    return max(0, AppConfig.freeDailySwipes - used);
  }

  @override
  Future<SwipeOutcome> swipe(String targetId, {required bool follow, String? directNote}) async {
    final existing = _swipes[(meId, targetId)];
    if (existing != null && existing.action == 'pass') _swipes.remove((meId, targetId));

    if (!follow) {
      _swipes[(meId, targetId)] = _Swipe(meId, targetId, 'pass', null);
      return SwipeOutcome.passed;
    }

    final reverse = _swipes[(targetId, meId)];
    if (reverse != null && reverse.action == 'follow_requested') {
      reverse.action = 'accepted';
      reverse.respondedAt = DateTime.now();
      _social.add(null);
      return SwipeOutcome.matched;
    }

    if (directNote != null && !premium) {
      throw const AppException(AppErrorCode.premiumRequired, 'Direct DM Invite needs the Fast-Track pass.');
    }
    if (await remainingSwipes() == 0) {
      throw const AppException(AppErrorCode.swipeLimit, 'You have used your 10 free follow requests today.');
    }
    if (directNote != null && ContactSanitizer.containsContactInfo(directNote)) {
      throw const AppException(AppErrorCode.contactInfo, 'Phone numbers, @handles and links are not allowed.');
    }

    final row = _Swipe(meId, targetId, 'follow_requested', directNote);
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
    final pending = _swipes.values
        .where((s) => s.receiver == meId && s.action == 'follow_requested')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return IncomingRequests(
      count: pending.length,
      // Same rule as the RLS policy: identities only for Fast-Track members.
      requests: premium
          ? [
              for (final s in pending)
                FollowRequest(
                  id: s.id,
                  sender: _people[s.sender]!.profile,
                  directNote: s.note,
                  createdAt: s.createdAt,
                ),
            ]
          : const [],
    );
  }

  @override
  Future<void> respondToRequest(String requestId, {required bool accept}) async {
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
    final rows = _swipes.values
        .where((s) => s.action == 'accepted' && (s.sender == meId || s.receiver == meId))
        .toList()
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
    if (!_connected(meId, peerId)) {
      throw const AppException(AppErrorCode.notConnected, 'Chat unlocks once the follow request is accepted.');
    }
    _push(peerId, _msg(meId, peerId, content: text));
    _scheduleReply(peerId);
  }

  @override
  Future<void> sendVoice(String peerId, Uint8List aacBytes, {String? localPath}) async {
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
          audioUrl: m.audioUrl,
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
  Future<String> playableAudioUrl(ChatMessage message) async => message.audioUrl ?? '';

  // ------------------------------------------------------------- helpers ----

  bool _connected(String a, String b) =>
      _swipes[(a, b)]?.action == 'accepted' || _swipes[(b, a)]?.action == 'accepted';

  ChatMessage _msg(String from, String to, {String? content, String? audio, DateTime? at}) => ChatMessage(
        id: _uuid.v4(),
        senderId: from,
        receiverId: to,
        content: content,
        audioUrl: audio,
        isRead: false,
        createdAt: at ?? DateTime.now(),
      );

  static const _openers = [
    'Hey! Thanks for the follow 😊',
    'Hii, nice to connect here!',
    'Heyy, your profile made me smile 🙂',
  ];
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
      _Seed('Ananya Menon', 24, 'Kochi', 'Filter coffee, Fort Kochi sunsets and too many plants 🌿',
          ['Photography', 'Kathakali', 'Cafés', 'Indie music'], premium: true, accepts: true),
      _Seed('Arjun Nair', 27, 'Kochi', 'Product designer. Weekend trekker. Will judge your biryani spot.',
          ['Trekking', 'Design', 'Football', 'Biryani'], accepts: true),
      _Seed('Meera Pillai', 23, 'Thiruvananthapuram', 'Med student who still finds time for Carnatic music 🎶',
          ['Music', 'Reading', 'Beaches'], accepts: false),
      _Seed('Rahul Krishnan', 26, 'Kozhikode', 'Halwa connoisseur. Beach runs at 6am. Ask me about F1.',
          ['Running', 'F1', 'Food'], accepts: true),
      _Seed('Diya Thomas', 25, 'Kochi', 'Marketing by day, salsa by night 💃',
          ['Dance', 'Travel', 'Brunch'], premium: true, accepts: true),
      _Seed('Nikhil Varma', 28, 'Thrissur', 'Pooram every year. Engineer, amateur chef, dog dad 🐕',
          ['Cooking', 'Dogs', 'Festivals'], accepts: false),
      _Seed('Sneha Joseph', 22, 'Kottayam', 'Literature grad. Rain + books + chai = perfect day.',
          ['Books', 'Poetry', 'Chai'], accepts: true),
      _Seed('Aditya Shenoy', 29, 'Kochi', 'Startup founder. Ocean kayaker. Terrible at small talk, great at deep talk.', ['Kayaking', 'Startups', 'Podcasts'], accepts: true),
      _Seed('Fathima Rasheed', 24, 'Kozhikode', 'Architecture student 🏛️ Sketching old Calicut streets.',
          ['Sketching', 'Heritage', 'Film'], accepts: true),
      _Seed('Vishnu Prasad', 25, 'Thiruvananthapuram', 'Cricket, coding and coconut everything.',
          ['Cricket', 'Gaming', 'Coding'], accepts: false),
      _Seed('Lakshmi Iyer', 26, 'Palakkad', 'Bharatanatyam dancer & UX writer. Looking for good conversations.', ['Dance', 'Writing', 'Yoga'], accepts: true),
      _Seed('Kiran George', 27, 'Alappuzha', 'Houseboat sunsets & backwater cycling 🚲',
          ['Cycling', 'Photography', 'Nature'], accepts: true),
    ];
    for (final s in seeds) {
      _people[s.profile.id] = s;
    }

    final now = DateTime.now();
    // Incoming follow requests (the "Who Requested You" tab).
    _swipes[(seeds[4].profile.id, meId)] = _Swipe(seeds[4].profile.id, meId, 'follow_requested',
        'Your bio says Fort Kochi sunsets… I know a secret spot 🌅', now.subtract(const Duration(hours: 2)));
    _swipes[(seeds[6].profile.id, meId)] =
        _Swipe(seeds[6].profile.id, meId, 'follow_requested', null, now.subtract(const Duration(hours: 5)));
    _swipes[(seeds[9].profile.id, meId)] = _Swipe(seeds[9].profile.id, meId, 'follow_requested',
        'Cricket or football? Choose wisely 😄', now.subtract(const Duration(days: 1)));

    // One existing mutual connection with history so chat is explorable immediately.
    final a = seeds[0].profile.id;
    _swipes[(meId, a)] = _Swipe(meId, a, 'accepted', null, now.subtract(const Duration(days: 1)))
      ..respondedAt = now.subtract(const Duration(hours: 20));
    _threads[a] = [
      _msg(a, meId, content: 'Hey! Thanks for the follow 😊', at: now.subtract(const Duration(hours: 19))),
      _msg(meId, a, content: 'Hi Ananya! Loved your sunset pics', at: now.subtract(const Duration(hours: 18))),
      _msg(a, meId, content: 'Haha thank you! Have you tried Kashi Art Café?', at: now.subtract(const Duration(minutes: 30))),
    ];
  }
}

class _Seed {
  _Seed(String name, int age, String city, String bio, this.interests,
      {bool premium = false, required bool accepts})
      : acceptsFollows = accepts,
        profile = PublicProfile(
          id: 'u_${name.split(' ').first.toLowerCase()}',
          fullName: name,
          age: age,
          city: city,
          bio: bio,
          primaryPhoto: 'asset:assets/demo/p_${name.split(' ').first.toLowerCase()}.jpg',
          isPremium: premium,
        ),
        gallery = List.generate(6, (i) => 'asset:assets/demo/g_${(name.length * 3 + i * 5) % 12}.jpg');

  final PublicProfile profile;
  final List<String> interests;
  final List<String> gallery;
  final bool acceptsFollows;
}

class _Swipe {
  _Swipe(this.sender, this.receiver, this.action, this.note, [DateTime? at])
      : id = const Uuid().v4(),
        createdAt = at ?? DateTime.now();

  final String id;
  final String sender;
  final String receiver;
  String action;
  final String? note;
  final DateTime createdAt;
  DateTime? respondedAt;
}
