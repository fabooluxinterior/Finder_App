import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/backend.dart';
import 'data/media_service.dart';
import 'data/local_notifier.dart';
import 'data/purchases_service.dart';
import 'data/push_service.dart';
import 'models/access.dart';
import 'models/follow_request.dart';
import 'models/message.dart';
import 'models/profile.dart';
import 'models/profile_update.dart';

/// Overridden in main() with the Supabase or demo implementation.
final backendProvider = Provider<FinderBackend>((ref) => throw UnimplementedError());
final purchasesProvider = Provider<PurchasesService>((ref) => throw UnimplementedError());
final mediaProvider = Provider<MediaService>((ref) => MediaService());

final authUserProvider = StreamProvider<String?>((ref) => ref.watch(backendProvider).authChanges());

final myProfileProvider = FutureProvider<PublicProfile?>((ref) async {
  final uid = ref.watch(authUserProvider).value;
  if (uid == null) return null;
  return ref.watch(backendProvider).myProfile();
});

final myPrivateProfileProvider = FutureProvider<PrivateProfile>((ref) async {
  ref.watch(myProfileProvider);
  return ref.watch(backendProvider).myPrivateProfile();
});

/// Ticks whenever requests, connections or incoming messages change.
final socialTickProvider = StreamProvider<int>((ref) async* {
  final uid = ref.watch(authUserProvider).value;
  if (uid == null) return;
  var n = 0;
  yield n;
  await for (final _ in ref.watch(backendProvider).socialChanges()) {
    yield ++n;
  }
});

/// Fast-Track / trial access: the server decides (paid plan or free trial); a
/// RevenueCat entitlement only adds to it, and its failures are ignored.
class PremiumNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final uid = ref.watch(authUserProvider).value;
    if (uid == null) return false;
    final purchases = ref.watch(purchasesProvider);
    // Billing problems (for example no store key in this build) must never hide
    // the access the server has granted (paid plan or free trial).
    try {
      await purchases.identify(uid);
    } catch (_) {}
    final results = await Future.wait([
      purchases.isFastTrackActive().catchError((_) => false),
      ref.watch(backendProvider).serverPremium().catchError((_) => false),
    ]);
    return results.any((v) => v);
  }

  Future<bool> purchase() async {
    final ok = await ref.read(purchasesProvider).purchaseFastTrack();
    if (ok) _unlock();
    return ok;
  }

  Future<bool> restore() async {
    final ok = await ref.read(purchasesProvider).restore();
    if (ok) _unlock();
    return ok;
  }

  void _unlock() {
    state = const AsyncData(true);
    ref.invalidate(incomingRequestsProvider);
  }
}

final premiumProvider = AsyncNotifierProvider<PremiumNotifier, bool>(PremiumNotifier.new);

/// 'demo' while the server's demo-payment window is open (closed testing), else 'live'.
final paymentsModeProvider = FutureProvider<String>((ref) async {
  final uid = ref.watch(authUserProvider).value;
  if (uid == null) return 'live';
  try {
    return await ref.watch(backendProvider).paymentsMode();
  } catch (_) {
    return 'live';
  }
});

bool isPremium(WidgetRef ref) => ref.watch(premiumProvider).value ?? false;

final feedProvider = FutureProvider<List<PublicProfile>>((ref) async {
  ref.watch(authUserProvider);
  return ref.watch(backendProvider).fetchFeed();
});

final incomingRequestsProvider = FutureProvider<IncomingRequests>((ref) async {
  ref.watch(socialTickProvider);
  ref.watch(premiumProvider);
  return ref.watch(backendProvider).incomingRequests();
});

final connectionsProvider = FutureProvider<List<Connection>>((ref) async {
  ref.watch(socialTickProvider);
  return ref.watch(backendProvider).connections();
});

final privateProfileProvider = FutureProvider.family<PrivateProfile, String>((ref, userId) async {
  ref.watch(socialTickProvider);
  return ref.watch(backendProvider).privateProfileOf(userId);
});

final messagesProvider = StreamProvider.autoDispose.family<List<ChatMessage>, String>(
  (ref, peerId) => ref.watch(backendProvider).watchMessages(peerId),
);

/// The owner's photo slots (in order, including uploads still in review).
final photoSlotsProvider = FutureProvider<List<PhotoSlot>>((ref) async {
  ref.watch(myProfileProvider);
  return ref.watch(backendProvider).photoSlots();
});

/// The owner's music connection. Cached for the session; the server caches
/// the Spotify import for 12 h, so swipes and feeds never hit Spotify.
final musicStateProvider = FutureProvider<MusicState>((ref) async {
  ref.watch(authUserProvider);
  return ref.watch(backendProvider).musicState();
});

/// Full profile cards (with shared artists/interests), kept for the session
/// so reopening a profile doesn't refetch.
final profileCardProvider = FutureProvider.family<PublicProfile, String>((ref, userId) async {
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(minutes: 10), link.close);
  return ref.watch(backendProvider).profileCard(userId);
});

/// Profile details introduced after launch that this user is missing. Refreshes
/// whenever the profile changes (saving a detail removes it).
final profileUpdatesProvider = FutureProvider<List<ProfileUpdate>>((ref) async {
  final me = await ref.watch(myProfileProvider.future);
  if (me == null || !me.isOnboarded) return const [];
  try {
    return await ref.watch(backendProvider).profileUpdates();
  } catch (_) {
    return const []; // never block the app on this
  }
});

/// Plan, trial dates and due reminders, from the server. Refreshes with
/// social changes and purchases.
final accessStatusProvider = FutureProvider<AccessStatus>((ref) async {
  final uid = ref.watch(authUserProvider).value;
  if (uid == null) return const AccessStatus();
  ref.watch(socialTickProvider);
  ref.watch(premiumProvider);
  try {
    return await ref.watch(backendProvider).accessStatus();
  } catch (_) {
    return const AccessStatus();
  }
});

final pushServiceProvider = Provider<PushService>((ref) => const NoopPush());

/// Notification-bar alerts raised by the app itself (no Firebase needed).
final localNotifierProvider = Provider<LocalNotifier>((ref) => const NoopLocalNotifier());

/// The chat the user is looking at right now (no alert for messages in it).
class OpenChatNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void open(String? peerId) => state = peerId;
  void closeIf(String peerId) {
    if (state == peerId) state = null;
  }
}

final openChatProvider = NotifierProvider<OpenChatNotifier, String?>(OpenChatNotifier.new);

/// Whether this phone should show popup notifications (default on; the user can switch it off).
class PushEnabledNotifier extends AsyncNotifier<bool> {
  static const _key = 'push_enabled';
  @override
  Future<bool> build() async => (await SharedPreferences.getInstance()).getBool(_key) ?? true;

  Future<void> set(bool on) async {
    final push = ref.read(pushServiceProvider);
    final backend = ref.read(backendProvider);
    await (await SharedPreferences.getInstance()).setBool(_key, on);
    state = AsyncData(on);
    if (!push.available) return;
    if (on) {
      await start();
    } else {
      final token = await push.currentToken();
      if (token != null) await backend.unregisterPushToken(token).catchError((_) {});
      await push.deleteToken();
    }
  }

  /// Registers this phone for popups (asks permission the first time). Never throws.
  Future<void> start() async {
    final push = ref.read(pushServiceProvider);
    if (!push.available || ref.read(authUserProvider).value == null) return;
    if (!(state.value ?? await future)) return;
    try {
      final token = await push.requestToken();
      if (token != null) await ref.read(backendProvider).registerPushToken(token);
    } catch (_) {}
  }
}

final pushEnabledProvider = AsyncNotifierProvider<PushEnabledNotifier, bool>(PushEnabledNotifier.new);

/// In-app notices (trial reminders, ticket updates, moderation notices).
final notificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  final uid = ref.watch(authUserProvider).value;
  if (uid == null) return const [];
  ref.watch(socialTickProvider);
  ref.watch(accessStatusProvider);
  try {
    return await ref.watch(backendProvider).notifications();
  } catch (_) {
    return const [];
  }
});
