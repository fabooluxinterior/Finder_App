import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finder_app/core/errors.dart';
import 'package:finder_app/data/backend.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/features/chat/media_editor_screen.dart';
import 'package:finder_app/features/chat/scheduled_provider.dart';
import 'package:finder_app/models/message.dart';
import 'package:finder_app/models/scheduled_message.dart';
import 'package:finder_app/providers.dart';
import 'package:finder_app/security/secure_kv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int n) => Uint8List.fromList(List.filled(n, 7));

Future<(DemoBackend, String)> _chat() async {
  final b = DemoBackend();
  await b.verifyOtp(OtpChannel.email, 'asha@example.com', '123456');
  await b.setDob(DateTime(1998, 3, 3));
  await b.acknowledgeStandards('2026-11-11');
  await b.createProfile(
    fullName: 'Asha Menon',
    city: 'Kochi',
    details: const ProfilePatch({
      ProfilePatch.gender: 'woman',
      ProfilePatch.bio: 'Filter coffee and long walks by the sea.',
      ProfilePatch.prefGenders: ['man'],
      ProfilePatch.interestTags: ['Hiking', 'Chess', 'Poetry', 'Baking', 'Cycling'],
      ProfilePatch.prompts: [
        {'prompt_id': 'p1', 'answer': 'Evening chai at Fort Kochi'},
        {'prompt_id': 'p4', 'answer': 'Sunrise, appam, nap'},
      ],
    }),
  );
  for (var i = 0; i < 4; i++) {
    await b.uploadPhoto(_bytes(1000 + i), mime: 'image/webp');
  }
  await b.completeOnboarding();
  return (b, (await b.connections()).first.profile.id);
}

Future<Uint8List> _png(int w, int h) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = Colors.teal);
  final img = await rec.endRecording().toImage(w, h);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

void main() {
  test('a scheduled message round-trips and is due only at its time', () {
    final at = DateTime(2026, 11, 20, 21);
    final m = ScheduledMessage(id: 'a', peerId: 'p', sendAt: at, createdAt: DateTime(2026, 11, 17), text: 'Good night');
    final back = ScheduledMessage.fromJson(m.toJson());
    expect((back.id, back.peerId, back.text, back.sendAt, back.hasImage), ('a', 'p', 'Good night', at, false));
    expect(back.due(at.subtract(const Duration(minutes: 1))), isFalse);
    expect(back.due(at), isTrue);
  });

  test('scheduled: waits until its time, sends once, can be rescheduled or deleted, and offline keeps it', () async {
    final (b, peer) = await _chat();
    final kv = MemorySecureKv();
    final c = ProviderContainer(overrides: [backendProvider.overrideWithValue(b), secureKvProvider.overrideWithValue(kv)]);
    addTearDown(c.dispose);
    c.listen(authUserProvider, (_, _) {});
    c.listen(scheduledProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final n = c.read(scheduledProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await n.scheduleText(peer, 'Later', DateTime.now().add(const Duration(hours: 2)));
    await n.flushDue();
    expect((await b.watchMessages(peer).first).where((m) => m.content == 'Later'), isEmpty, reason: 'not before its time');
    expect(c.read(scheduledProvider), hasLength(1));

    final id = c.read(scheduledProvider).single.id;
    await n.reschedule(id, DateTime.now().subtract(const Duration(seconds: 1)));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await n.flushDue();
    expect((await b.watchMessages(peer).first).where((m) => m.content == 'Later'), hasLength(1), reason: 'sent at its time');
    expect(c.read(scheduledProvider), isEmpty);

    await n.scheduleText(peer, 'Never mind', DateTime.now().add(const Duration(days: 1)));
    await n.remove(c.read(scheduledProvider).single.id);
    expect(c.read(scheduledProvider), isEmpty);
    expect(kv.map.keys.where((k) => k.startsWith('vouby_scheduled_v1_')).length, 1, reason: 'list persisted (empty)');

    // A photo is kept in encrypted storage until it is sent, and removed with the entry.
    await n.schedulePhoto(peer, _bytes(500), 10, 10, DateTime.now().add(const Duration(days: 1)));
    final pid = c.read(scheduledProvider).single.id;
    expect(await n.imageOf(pid), isNotNull);
    await n.remove(pid);
    expect(await n.imageOf(pid), isNull);
  });

  test('scheduled: offline keeps it for later; a refusal is marked instead of retrying forever', () async {
    final (b, peer) = await _chat();
    final failing = _Flaky(b);
    final c = ProviderContainer(
      overrides: [backendProvider.overrideWithValue(failing), secureKvProvider.overrideWithValue(MemorySecureKv())],
    );
    addTearDown(c.dispose);
    c.listen(authUserProvider, (_, _) {});
    c.listen(scheduledProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final n = c.read(scheduledProvider.notifier);
    await n.scheduleText(peer, 'Hello later', DateTime.now().subtract(const Duration(seconds: 1)));

    failing.error = const AppException(AppErrorCode.network, 'offline');
    await n.flushDue();
    expect(c.read(scheduledProvider).single.error, isNull, reason: 'offline: stays, tried again later');

    failing.error = const AppException(AppErrorCode.subscriptionRequired, 'Fast-Track needed');
    await n.flushDue();
    expect(c.read(scheduledProvider).single.error, 'Needs Fast-Track to send');
    final calls = failing.calls;
    await n.flushDue();
    expect(failing.calls, calls, reason: 'a refused message is not retried until it is rescheduled');

    failing.error = null;
    await n.reschedule(c.read(scheduledProvider).single.id, DateTime.now().subtract(const Duration(seconds: 1)));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(c.read(scheduledProvider), isEmpty, reason: 'rescheduled, then sent');
  });

  testWidgets('media editor: preview opens, pencil/text/crop tools exist, and Send returns a picture', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final png = (await t.runAsync(() => _png(400, 300)))!;
    EditedMedia? result;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await Navigator.push<EditedMedia>(
                context,
                MaterialPageRoute(builder: (_) => MediaEditorScreen(bytes: png)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Pencil'), findsOneWidget);
    expect(find.byTooltip('Text'), findsOneWidget);
    expect(find.byTooltip('Crop'), findsOneWidget);

    // Draw a stroke.
    await t.tap(find.byTooltip('Pencil'));
    await t.pump();
    await t.dragFrom(const Offset(200, 400), const Offset(80, 40));
    await t.pump();
    expect(find.byTooltip('Undo'), findsOneWidget);

    // Crop.
    await t.tap(find.byTooltip('Crop'));
    await t.pump();
    expect(find.text('Apply crop'), findsOneWidget);
    await t.tap(find.text('Apply crop'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 400));

    // Send once.
    await t.tap(find.byTooltip('Send (hold to send later)'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await t.pump(const Duration(milliseconds: 400));
    expect(result, isNotNull);
    expect(result!.sendAt, isNull);
    expect(result!.bytes.length, greaterThan(100));
  });
}

class _Flaky extends DemoBackend {
  _Flaky(DemoBackend inner) : _inner = inner;
  final DemoBackend _inner;
  AppException? error;
  int calls = 0;

  @override
  String? get currentUserId => _inner.currentUserId;
  @override
  Stream<String?> authChanges() => _inner.authChanges();
  @override
  Future<void> sendText(String peerId, String text, {ReplyRef? replyTo}) async {
    calls++;
    final e = error;
    if (e != null) throw e;
    return _inner.sendText(peerId, text);
  }
}
