import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

/// One picture in the phone's gallery.
class GalleryItem {
  const GalleryItem(this.id, [this.handle, this.takenAt]);
  final String id;
  final Object? handle;

  /// When the picture was taken (null when unknown): used to group the gallery by day.
  final DateTime? takenAt;
}

/// A folder in the phone's gallery (Camera, Screenshots, WhatsApp Images…). The first one is "Recent": everything.
class GalleryAlbum {
  const GalleryAlbum(this.id, this.name, this.count, [this.handle]);
  final String id;
  final String name;
  final int count;
  final Object? handle;
}

/// What the attach screen needs from the phone: a live camera and the gallery. A fake replaces it in tests, and
/// when permission is refused [init] reports false so the chat falls back to the system picker.
abstract class AttachSource {
  /// Starts the camera and asks for gallery access. False when neither is usable.
  Future<bool> init();
  bool get hasCamera;
  bool get hasGallery;
  bool get flashOn;
  bool get canFlip;

  Widget cameraPreview(BuildContext context);
  Future<Uint8List?> capture();
  Future<void> toggleFlash();
  Future<void> flip();

  /// Asks for gallery access again (or opens the phone's settings when it was refused for good). True when usable.
  Future<bool> requestGallery();

  /// The gallery folders, "Recent" first.
  Future<List<GalleryAlbum>> albums();

  /// One page of pictures, newest first, from [album] (or all pictures when null).
  Future<List<GalleryItem>> recent(int page, int size, {GalleryAlbum? album});
  Future<Uint8List?> thumbnail(GalleryItem item, int px);
  Future<Uint8List?> original(GalleryItem item);

  void dispose();
}

final attachSourceProvider = Provider.autoDispose<AttachSource>((ref) {
  final s = DeviceAttachSource();
  ref.onDispose(s.dispose);
  return s;
});

/// The real camera (`camera`) and gallery (`photo_manager`).
class DeviceAttachSource implements AttachSource {
  CameraController? _cam;
  List<CameraDescription> _cams = const [];
  int _camIndex = 0;
  bool _gallery = false;
  bool _flash = false;
  AssetPathEntity? _all;

  /// Newest picture first (the phone's default order starts from the oldest).
  static final _newestFirst = FilterOptionGroup(orders: [const OrderOption()]);

  @override
  bool get hasCamera => _cam?.value.isInitialized ?? false;
  @override
  bool get hasGallery => _gallery;
  @override
  bool get flashOn => _flash;
  @override
  bool get canFlip => _cams.length > 1;

  @override
  Future<bool> init() async {
    // One permission prompt at a time: Android drops a prompt that opens while another is still showing.
    final cam = await _initCamera();
    final gal = await _initGallery();
    return cam || gal;
  }

  Future<bool> _initCamera() async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) return false;
      _camIndex = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (_camIndex < 0) _camIndex = 0;
      return await _open(_cams[_camIndex]);
    } catch (_) {
      return false; // permission refused or no camera
    }
  }

  Future<bool> _open(CameraDescription d) async {
    final old = _cam;
    final c = CameraController(d, ResolutionPreset.high, enableAudio: false);
    try {
      await c.initialize();
      await c.setFlashMode(_flash ? FlashMode.auto : FlashMode.off);
      _cam = c;
      await old?.dispose();
      return true;
    } catch (_) {
      await c.dispose();
      return false;
    }
  }

  Future<bool> _initGallery() async {
    try {
      final p = await PhotoManager.requestPermissionExtend();
      if (!p.hasAccess) return false;
      final paths = await PhotoManager.getAssetPathList(onlyAll: true, type: RequestType.image, filterOption: _newestFirst);
      if (paths.isEmpty) return false;
      _all = paths.first;
      _gallery = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget cameraPreview(BuildContext context) {
    final c = _cam;
    if (c == null || !c.value.isInitialized) return const SizedBox.shrink();
    final size = c.value.previewSize;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // The sensor reports landscape sizes: swap for a portrait phone.
          width: size == null ? 1 : size.height,
          height: size == null ? 1 : size.width,
          child: CameraPreview(c),
        ),
      ),
    );
  }

  @override
  Future<Uint8List?> capture() async {
    final c = _cam;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) return null;
    final f = await c.takePicture();
    return f.readAsBytes();
  }

  @override
  Future<void> toggleFlash() async {
    final c = _cam;
    if (c == null) return;
    _flash = !_flash;
    try {
      await c.setFlashMode(_flash ? FlashMode.always : FlashMode.off);
    } catch (_) {
      _flash = false;
    }
  }

  @override
  Future<void> flip() async {
    final c = _cam;
    if (c == null || _cams.length < 2) return;
    final wantFront = _cams[_camIndex].lensDirection == CameraLensDirection.back;
    var next = _cams.indexWhere((d) => d.lensDirection == (wantFront ? CameraLensDirection.front : CameraLensDirection.back));
    if (next < 0) next = (_camIndex + 1) % _cams.length;
    if (next == _camIndex) return;
    try {
      // Switch on the same controller: no preview is torn down while it is still on screen.
      await c.setDescription(_cams[next]);
      _camIndex = next;
      await c.setFlashMode(_flash ? FlashMode.always : FlashMode.off).catchError((_) {});
    } catch (_) {
      // Keep the camera that works.
    }
  }

  @override
  Future<bool> requestGallery() async {
    if (_gallery) return true;
    final ok = await _initGallery();
    if (!ok) await PhotoManager.openSetting();
    return ok;
  }

  @override
  Future<List<GalleryAlbum>> albums() async {
    try {
      final paths = await PhotoManager.getAssetPathList(type: RequestType.image, filterOption: _newestFirst);
      final out = <GalleryAlbum>[];
      for (final p in paths) {
        final n = await p.assetCountAsync;
        if (n == 0) continue;
        out.add(GalleryAlbum(p.id, p.isAll ? 'Recent' : p.name, n, p));
      }
      out.sort(
        (a, b) => a.name == 'Recent' ? -1 : (b.name == 'Recent' ? 1 : a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      );
      return out;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<GalleryItem>> recent(int page, int size, {GalleryAlbum? album}) async {
    final p = (album?.handle as AssetPathEntity?) ?? _all;
    if (p == null) return const [];
    final assets = await p.getAssetListPaged(page: page, size: size);
    return [for (final a in assets) GalleryItem(a.id, a, a.createDateTime)];
  }

  @override
  Future<Uint8List?> thumbnail(GalleryItem item, int px) async =>
      (item.handle as AssetEntity?)?.thumbnailDataWithSize(ThumbnailSize.square(px));

  @override
  Future<Uint8List?> original(GalleryItem item) async => (item.handle as AssetEntity?)?.originBytes;

  @override
  void dispose() {
    _cam?.dispose();
    _cam = null;
  }
}
