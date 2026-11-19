import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'image_optimizer.dart';

/// Browser: decode with createImageBitmap (applies EXIF orientation), draw
/// into an HTML5 canvas at the target size, export as WebP.
class PlatformImageEncoder {
  const PlatformImageEncoder();

  Future<web.ImageBitmap> _bitmap(Uint8List input, ImageFormat format) async {
    final blob = web.Blob([input.toJS].toJS, web.BlobPropertyBag(type: _mime(format)));
    try {
      return await web.window.createImageBitmap(blob).toDart;
    } catch (_) {
      throw ImageOptimizeException(
        format == ImageFormat.heic
            ? 'This browser can’t open HEIC photos. Choose a JPEG or PNG, or use the Vouby app.'
            : 'That photo couldn’t be opened. Try another one.',
      );
    }
  }

  static String _mime(ImageFormat f) => switch (f) {
    ImageFormat.jpeg => 'image/jpeg',
    ImageFormat.png => 'image/png',
    ImageFormat.webp => 'image/webp',
    ImageFormat.heic => 'image/heic',
    ImageFormat.gif => 'image/gif',
    ImageFormat.bmp => 'image/bmp',
    ImageFormat.avif => 'image/avif',
    ImageFormat.other => '',
  };

  Future<SourceSize> decodeSize(Uint8List input, ImageFormat format) async {
    final b = await _bitmap(input, format);
    final s = SourceSize(b.width, b.height);
    b.close();
    return s;
  }

  Future<EncodedImage> encode(
    Uint8List input,
    ImageFormat format,
    SourceSize source, {
    required int width,
    required int height,
    required int quality,
  }) async {
    final bitmap = await _bitmap(input, format);
    final canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    ctx
      ..imageSmoothingEnabled = true
      ..imageSmoothingQuality = 'high'
      ..drawImage(bitmap, 0, 0, width, height);
    bitmap.close();

    Future<web.Blob?> export(String type) {
      final c = Completer<web.Blob?>();
      canvas.toBlob(((web.Blob? b) => c.complete(b)).toJS, type, (quality / 100).toJS);
      return c.future;
    }

    var blob = await export('image/webp');
    var mime = 'image/webp';
    // Browsers without a WebP encoder silently return PNG: fall back to JPEG
    // (the server converts it to WebP).
    if (blob == null || blob.type != 'image/webp') {
      blob = await export('image/jpeg');
      mime = 'image/jpeg';
    }
    if (blob == null) throw const ImageOptimizeException('That photo couldn’t be processed. Try another one.');
    final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
    canvas.width = 0; // release the backing store
    return EncodedImage(bytes, mime);
  }
}
