import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

/// One picture in the phone's gallery.
class GalleryItem {
  const GalleryItem(this.id, [this.handle]);
  final String id;
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

  Future<List<GalleryItem>> recent(int page, int size);
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
    final results = await Future.wait([_initCamera(), _initGallery()]);
    return results.any((ok) => ok);
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
      final paths = await PhotoManager.getAssetPathList(onlyAll: true, type: RequestType.image);
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
    if (_cams.length < 2) return;
    _camIndex = (_camIndex + 1) % _cams.length;
    await _open(_cams[_camIndex]);
  }

  @override
  Future<List<GalleryItem>> recent(int page, int size) async {
    final p = _all;
    if (p == null) return const [];
    final assets = await p.getAssetListPaged(page: page, size: size);
    return [for (final a in assets) GalleryItem(a.id, a)];
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
