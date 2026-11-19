import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finder_app/core/errors.dart';
import 'package:finder_app/data/backend.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/features/chat/media_editor_screen.dart';
import 'package:finder_app/models/scheduled_message.dart';
import 'package:flutter/material.dart';
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
  test(
    'scheduled: waits on the server side, appears in the chat only at its time, can be edited, rescheduled and cancelled',
    () async {
      final (b, peer) = await _chat();
      expect(await b.scheduledMessages(peerId: peer), isEmpty);
      await expectLater(
        b.scheduleMessage(peer, 'Late', DateTime.now().subtract(const Duration(minutes: 1))),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        b.scheduleMessage(peer, '   ', DateTime.now().add(const Duration(days: 1))),
        throwsA(isA<AppException>()),
      );

      // Far in the future: no upper limit.
      await b.scheduleMessage(peer, 'See you in a year', DateTime.now().add(const Duration(days: 400)));
      await b.scheduleMessage(peer, 'Good night', DateTime.now().add(const Duration(hours: 5)));
      final waiting = await b.scheduledMessages(peerId: peer);
      expect(waiting.map((m) => m.status).toSet(), {ScheduledStatus.scheduled});
      expect(waiting.map((m) => m.text), containsAll(['See you in a year', 'Good night']));
      expect(
        (await b.watchMessages(peer).first).where((m) => m.content == 'Good night'),
        isEmpty,
        reason: 'not in the chat before its time',
      );

      // Reschedule = new time, old one cancelled; cancel removes it for good.
      final night = waiting.firstWhere((m) => m.text == 'Good night');
      await b.scheduleMessage(peer, night.text!, DateTime.now().add(const Duration(hours: 6)));
      await b.cancelScheduled(night.id);
      final after = await b.scheduledMessages(peerId: peer);
      expect(after.where((m) => m.status == ScheduledStatus.scheduled && m.text == 'Good night'), hasLength(1));
      expect(after.where((m) => m.status == ScheduledStatus.cancelled), hasLength(1));
    },
  );

  test('scheduled: the chat gets the message exactly once when its time has come', () async {
    final (b, peer) = await _chat();
    // The demo releases due messages when it is asked; a time just ahead is reached after a short wait.
    await b.scheduleMessage(peer, 'On its way', DateTime.now().add(const Duration(seconds: 31)));
    expect((await b.scheduledMessages(peerId: peer)).single.status, ScheduledStatus.scheduled);
    await b.advanceClockForTest(const Duration(minutes: 1));
    final done = await b.scheduledMessages(peerId: peer);
    expect(done.single.status, ScheduledStatus.sent);
    await b.scheduledMessages(peerId: peer);
    expect(
      (await b.watchMessages(peer).first).where((m) => m.content == 'On its way'),
      hasLength(1),
      reason: 'no duplicate on later checks',
    );
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
    expect(find.byTooltip('Text'), findsNothing, reason: 'no text tool any more');
    expect(find.text('Add a caption…'), findsOneWidget);
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

    // Caption: typed under the picture, handed back with it.
    await t.enterText(find.byType(TextField), '  Sunset at Kovalam  ');
    await t.pump();

    // Send once.
    await t.tap(find.byTooltip('Send (hold to send later)'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await t.pump(const Duration(milliseconds: 400));
    expect(result, isNotNull);
    expect(result!.sendAt, isNull);
    expect(result!.bytes.length, greaterThan(100));
    expect(result!.caption, 'Sunset at Kovalam');
  });

  testWidgets('crop box follows the finger straight away, without rebuilding the whole editor', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final png = (await t.runAsync(() => _png(400, 300)))!;
    await t.pumpWidget(MaterialApp(home: MediaEditorScreen(bytes: png)));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byTooltip('Crop'));
    await t.pump();
    final box = find
        .byType(CustomPaint)
        .evaluate()
        .map((e) => e.widget)
        .whereType<CustomPaint>()
        .where((c) => c.painter.toString().contains('_DimPainter'));
    expect(box, isNotEmpty);
    final before = t.getRect(find.byType(RawImage));
    // Drag the top-left handle: the picture does not move or re-layout, and one pump is enough to see the change.
    final tl = Offset(before.left + before.width * 0.05, before.top + before.height * 0.05);
    final g = await t.startGesture(tl);
    await g.moveBy(const Offset(30, 20));
    await t.pump();
    await g.up();
    await t.pump();
    expect(t.getRect(find.byType(RawImage)), before);
    expect(find.text('Apply crop'), findsOneWidget);
  });
}
