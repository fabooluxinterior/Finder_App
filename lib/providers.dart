import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/backend.dart';
import 'data/media_service.dart';
import 'data/purchases_service.dart';
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

/// Fast-Track status: RevenueCat entitlement (instant) OR server flag (webhook).
class PremiumNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final uid = ref.watch(authUserProvider).value;
    if (uid == null) return false;
    final purchases = ref.watch(purchasesProvider);
    await purchases.identify(uid);
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
