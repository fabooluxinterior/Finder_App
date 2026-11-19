import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finder_app/core/theme.dart';
import 'package:finder_app/core/view_once_icon.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/features/chat/attach_screen.dart';
import 'package:finder_app/features/chat/attach_source.dart';
import 'package:finder_app/features/chat/media_editor_screen.dart';
import 'package:finder_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _png(int w, int h, Color c) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = c);
  final img = await rec.endRecording().toImage(w, h);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

class FakeAttachSource implements AttachSource {
  FakeAttachSource({this.allowed = true, required this.png, this.count = 30});
  final bool allowed;
  final Uint8List png;
  final int count;
  bool shot = false;
  @override
  Future<bool> init() async => allowed;
  @override
  bool get hasCamera => allowed;
  @override
  bool get hasGallery => allowed;
  @override
  bool get flashOn => false;
  @override
  bool get canFlip => true;
  @override
  Widget cameraPreview(BuildContext context) => const ColoredBox(color: Color(0xFF223344));
  @override
  Future<Uint8List?> capture() async {
    shot = true;
    return png;
  }

  @override
  Future<void> toggleFlash() async {}
  @override
  Future<void> flip() async {}
  @override
  Future<bool> requestGallery() async => allowed;
  @override
  Future<List<GalleryAlbum>> albums() async => [
    const GalleryAlbum('all', 'Recent', 30),
    const GalleryAlbum('shots', 'Screenshots', 4),
  ];
  @override
  Future<List<GalleryItem>> recent(int page, int size, {GalleryAlbum? album}) async {
    final n = album?.id == 'shots' ? 4 : count;
    return [for (var i = page * size; i < n && i < (page + 1) * size; i++) GalleryItem('${album?.id ?? 'g'}$i')];
  }

  @override
  Future<Uint8List?> thumbnail(GalleryItem item, int px) async => png;
  @override
  Future<Uint8List?> original(GalleryItem item) async => png;
  @override
  void dispose() {}
}

Widget _host(FakeAttachSource src, void Function(AttachResult?) onResult) => ProviderScope(
  overrides: [attachSourceProvider.overrideWith((ref) => src), backendProvider.overrideWithValue(DemoBackend())],
  child: MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async =>
              onResult(await Navigator.push<AttachResult>(context, MaterialPageRoute(builder: (_) => const AttachScreen()))),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('camera with a row of recent pictures; swipe up opens the gallery; pick several and send', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final png = (await t.runAsync(() => _png(40, 40, Colors.teal)))!;
    AttachResult? result;
    await t.pumpWidget(_host(FakeAttachSource(png: png), (r) => result = r));
    await t.tap(find.text('open'));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.bySemanticsLabel('Take photo'), findsOneWidget, reason: 'the camera is on screen');
    expect(find.text('Recent'), findsNothing, reason: 'the gallery header only shows when expanded');
    expect(find.bySemanticsLabel('Show all photos'), findsOneWidget);

    // Swipe the row up: the whole gallery.
    await t.fling(find.byType(ListView).first, const Offset(0, -300), 1200); // swipe up on the row of pictures
    await t.pump(const Duration(milliseconds: 100)); // the tray starts growing on the next frame
    await t.pump(const Duration(milliseconds: 600));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Recent'), findsOneWidget);
    expect(find.bySemanticsLabel('Take photo'), findsOneWidget);

    // Pick three, in order; the circles are numbered.
    final tiles = find.descendant(of: find.byType(GridView), matching: find.byType(Image));
    expect(tiles, findsWidgets);
    for (var k = 0; k < 3; k++) {
      await t.tap(tiles.at(k));
    }
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('3 selected'), findsWidgets);
    expect(find.text('3'), findsOneWidget, reason: 'numbered selection');
    await t.tap(find.text('Send'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 500));
    expect(result!.photos, hasLength(3));
    expect(result!.useSystemPicker, isFalse);
  });

  testWidgets('the gallery title is a drop-down of folders; choosing one shows its pictures', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final png = (await t.runAsync(() => _png(40, 40, Colors.teal)))!;
    await t.pumpWidget(_host(FakeAttachSource(png: png), (_) {}));
    await t.tap(find.text('open'));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 500));
    await t.fling(find.byType(ListView).first, const Offset(0, -300), 1200);
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 600));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Recent'), findsOneWidget);
    await t.tap(find.text('Recent'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Screenshots'), findsOneWidget);
    await t.tap(find.text('Screenshots'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Screenshots'), findsOneWidget, reason: 'the title now shows the folder');
    final tiles = find.descendant(of: find.byType(GridView), matching: find.byType(Image));
    expect(tiles, findsNWidgets(4));
  });

  testWidgets('tap a picture in the row to use it; the round button takes a picture', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final png = (await t.runAsync(() => _png(40, 40, Colors.teal)))!;
    AttachResult? result;
    final src = FakeAttachSource(png: png);
    await t.pumpWidget(_host(src, (r) => result = r));
    await t.tap(find.text('open'));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.bySemanticsLabel('Take photo'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 500));
    expect(src.shot, isTrue);
    expect(result!.photos, hasLength(1));

    result = null;
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.text('open'));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 500));
    await t.tapAt(t.getTopLeft(find.byType(ListView).first) + const Offset(40, 40));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 500));
    expect(result!.photos, hasLength(1), reason: 'a picture from the row is used as it is');
  });

  testWidgets('permission refused: falls back to the phone\'s own picker', (t) async {
    final png = (await t.runAsync(() => _png(8, 8, Colors.teal)))!;
    AttachResult? result;
    await t.pumpWidget(_host(FakeAttachSource(allowed: false, png: png), (r) => result = r));
    await t.tap(find.text('open'));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 500));
    expect(result!.useSystemPicker, isTrue);
  });

  testWidgets('editor: View once is a minimal icon (dotted, filled when on) and is hidden for several photos', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final png = (await t.runAsync(() => _png(300, 400, Colors.teal)))!;
    EditedMedia? out;
    Future<void> open(bool once, String? label) async {
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => out = await Navigator.push<EditedMedia>(
                context,
                MaterialPageRoute(
                  builder: (_) => MediaEditorScreen(bytes: png, allowOnce: once, positionLabel: label),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await t.tap(find.text('go'));
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pump(const Duration(milliseconds: 500));
    }

    await open(true, null);
    expect(find.byType(ViewOnceIcon), findsOneWidget);
    expect(t.widget<ViewOnceIcon>(find.byType(ViewOnceIcon)).filled, isFalse);
    await t.tap(find.byTooltip('View once'));
    await t.pump();
    expect(t.widget<ViewOnceIcon>(find.byType(ViewOnceIcon)).filled, isTrue);
    await t.tap(find.byTooltip('Send (hold to send later)').first);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await t.pump(const Duration(milliseconds: 500));
    expect(out!.once, isTrue);

    await open(false, '2 of 3');
    expect(find.byType(ViewOnceIcon), findsNothing, reason: 'view once is single-photo only');
    expect(find.text('2 of 3'), findsOneWidget);
  });
}
