import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors.dart';
import '../../core/image_optimizer.dart';
import '../../data/scheduled_store.dart';
import '../../models/scheduled_message.dart';
import '../../providers.dart';

const _uuid = Uuid();

/// Messages waiting to be sent later, for the signed-in account (all chats).
class ScheduledNotifier extends Notifier<List<ScheduledMessage>> {
  ScheduledStore? _store;
  bool _flushing = false;

  @override
  List<ScheduledMessage> build() {
    final uid = ref.watch(authUserProvider).value;
    if (uid == null) return const [];
    final store = _store = ScheduledStore(ref.read(secureKvProvider), uid);
    store.load().then((l) {
      if (ref.mounted && _store == store) state = l;
    });
    return const [];
  }

  List<ScheduledMessage> forPeer(String peerId) => [
    for (final m in state)
      if (m.peerId == peerId) m,
  ]..sort((a, b) => a.sendAt.compareTo(b.sendAt));

  Future<void> _persist() async => _store?.save(state);

  /// Text (and no photo) to send at [at].
  Future<void> scheduleText(String peerId, String text, DateTime at) async {
    state = [...state, ScheduledMessage(id: _uuid.v4(), peerId: peerId, sendAt: at, createdAt: DateTime.now(), text: text)];
    await _persist();
  }

  /// A photo, already prepared for sending (resized and compressed), to send at [at].
  Future<void> schedulePhoto(String peerId, Uint8List prepared, int width, int height, DateTime at) async {
    final id = _uuid.v4();
    await _store?.putImage(id, prepared);
    state = [
      ...state,
      ScheduledMessage(
        id: id,
        peerId: peerId,
        sendAt: at,
        createdAt: DateTime.now(),
        hasImage: true,
        width: width,
        height: height,
      ),
    ];
    await _persist();
  }

  Future<Uint8List?> imageOf(String id) async => _store?.image(id);

  Future<void> remove(String id) async {
    final m = state.where((x) => x.id == id).firstOrNull;
    state = [
      for (final x in state)
        if (x.id != id) x,
    ];
    if (m?.hasImage ?? false) await _store?.deleteImage(id);
    await _persist();
  }

  Future<void> reschedule(String id, DateTime at) async {
    state = [for (final x in state) x.id == id ? x.copyWith(sendAt: at, clearError: true) : x];
    await _persist();
    unawaited(flushDue());
  }

  /// Sends everything that is due. No connection: it stays and is tried again on the next tick.
  Future<void> flushDue() async {
    if (_flushing || state.isEmpty) return;
    _flushing = true;
    try {
      final backend = ref.read(backendProvider);
      final now = DateTime.now();
      for (final m in [...state]) {
        if (!m.due(now) || m.error != null) continue;
        try {
          if (m.hasImage) {
            final bytes = await _store?.image(m.id);
            if (bytes == null) {
              await remove(m.id);
              continue;
            }
            await backend.sendImage(m.peerId, bytes, width: m.width, height: m.height);
          } else {
            await backend.sendText(m.peerId, m.text ?? '');
          }
          await remove(m.id);
        } on AppException catch (e) {
          if (e.code == AppErrorCode.network) continue; // offline: try again later
          state = [for (final x in state) x.id == m.id ? x.copyWith(error: _why(e)) : x];
          await _persist();
        } catch (_) {
          continue; // unknown/transient: try again on the next tick
        }
      }
    } finally {
      _flushing = false;
    }
  }

  static String _why(AppException e) => switch (e.code) {
    AppErrorCode.subscriptionRequired => 'Needs Fast-Track to send',
    AppErrorCode.notConnected => 'You are no longer connected',
    AppErrorCode.accountRestricted => 'Your account can’t send messages right now',
    _ => e.message,
  };
}

final scheduledProvider = NotifierProvider<ScheduledNotifier, List<ScheduledMessage>>(ScheduledNotifier.new);

/// Keeps watch while the app is open: every 15 seconds anything due is sent. Watched from the signed-in home screen.
final scheduledSenderProvider = Provider<void>((ref) {
  final timer = Timer.periodic(const Duration(seconds: 15), (_) => ref.read(scheduledProvider.notifier).flushDue());
  ref.onDispose(timer.cancel);
  // A first pass right away (e.g. after the app was closed past the send time).
  Future<void>.delayed(const Duration(seconds: 3), () {
    if (ref.mounted) ref.read(scheduledProvider.notifier).flushDue();
  });
});

/// Helper for the chat: prepares a picked picture the same way a normal send does.
Future<({Uint8List bytes, int width, int height})> prepareForChat(Uint8List raw) async {
  final img = await ImageOptimizer.optimizeForChat(raw);
  return (bytes: img.bytes, width: img.width, height: img.height);
}
