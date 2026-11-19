import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finder_app/features/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _png() async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 40, 60), Paint()..color = Colors.teal);
  final img = await rec.endRecording().toImage(40, 60);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

Widget _host(Uint8List png, {bool once = false}) => MaterialApp(
  home: Builder(
    builder: (c) => Scaffold(
      body: TextButton(
        onPressed: () => Navigator.push(c, chatPhotoRoute(png, once: once)),
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester t, Uint8List png, {bool once = false}) async {
  await t.pumpWidget(_host(png, once: once));
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  test('dismiss rule: a long drag or a flick closes, a short slow one does not', () {
    expect(shouldDismissPhoto(120, 0), isTrue);
    expect(shouldDismissPhoto(-120, 0), isTrue);
    expect(shouldDismissPhoto(30, 900), isTrue);
    expect(shouldDismissPhoto(-30, -900), isTrue);
    expect(shouldDismissPhoto(40, 100), isFalse);
  });

  testWidgets('full screen: no app bar or back arrow; a tap closes it quickly', (t) async {
    final png = (await t.runAsync(_png))!;
    await _open(t, png);
    expect(find.byType(ChatPhotoViewer), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    await t.tap(find.byType(ChatPhotoViewer));
    await _settle(t);
    expect(find.byType(ChatPhotoViewer), findsNothing);
  });

  testWidgets('a hard swipe up or down anywhere closes it; a short drag springs back', (t) async {
    final png = (await t.runAsync(_png))!;
    await _open(t, png);
    await t.drag(find.byType(ChatPhotoViewer), const Offset(0, 30));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(ChatPhotoViewer), findsOneWidget, reason: 'short drag springs back');
    await t.fling(find.byType(ChatPhotoViewer), const Offset(0, -200), 1500);
    await _settle(t);
    expect(find.byType(ChatPhotoViewer), findsNothing, reason: 'swipe up closes');

    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    await t.drag(find.byType(ChatPhotoViewer), const Offset(0, 220));
    await _settle(t);
    expect(find.byType(ChatPhotoViewer), findsNothing, reason: 'swipe down closes');
  });

  testWidgets('pinch zooms in; while zoomed a drag pans instead of closing and a tap does not close', (t) async {
    final png = (await t.runAsync(_png))!;
    await _open(t, png);
    final c = t.getCenter(find.byType(ChatPhotoViewer));
    final g1 = await t.startGesture(c - const Offset(20, 0), pointer: 1);
    final g2 = await t.startGesture(c + const Offset(20, 0), pointer: 2);
    await g1.moveTo(c - const Offset(90, 0));
    await g2.moveTo(c + const Offset(90, 0));
    await g1.up();
    await g2.up();
    await t.pump(const Duration(milliseconds: 200));
    final img = find.byType(Image);
    expect(t.getSize(img).width, greaterThan(300), reason: 'zoomed image is larger than the screen fit');
    await t.drag(find.byType(ChatPhotoViewer), const Offset(0, 250));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChatPhotoViewer), findsOneWidget, reason: 'dragging while zoomed pans');
    await t.tap(find.byType(ChatPhotoViewer));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(ChatPhotoViewer), findsOneWidget, reason: 'tap does nothing while zoomed');
  });

  testWidgets('view-once photo shows its line and still closes by swipe', (t) async {
    final png = (await t.runAsync(_png))!;
    await _open(t, png, once: true);
    expect(find.text('This photo disappears when you close it.'), findsOneWidget);
    await t.fling(find.byType(ChatPhotoViewer), const Offset(0, 200), 1500);
    await _settle(t);
    expect(find.byType(ChatPhotoViewer), findsNothing);
  });
}
