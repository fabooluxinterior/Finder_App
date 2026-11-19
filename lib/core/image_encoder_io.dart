import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'image_optimizer.dart';

/// Android / iOS: native decoders (including HEIC) and WebP encoding via
/// flutter_image_compress. EXIF orientation is applied and metadata dropped.
class PlatformImageEncoder {
  const PlatformImageEncoder();

  Future<SourceSize> decodeSize(Uint8List input, ImageFormat format) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(input);
      final d = await ui.ImageDescriptor.encoded(buffer);
      final s = SourceSize(d.width, d.height);
      d.dispose();
      buffer.dispose();
      return s;
    } catch (_) {
      // Engine can't read this container (some HEIC files): convert first.
      final jpeg = await FlutterImageCompress.compressWithList(input, quality: 95, format: CompressFormat.jpeg);
      return decodeSize(jpeg, ImageFormat.jpeg);
    }
  }

  Future<EncodedImage> encode(
    Uint8List input,
    ImageFormat format,
    SourceSize source, {
    required int width,
    required int height,
    required int quality,
  }) async {
    // flutter_image_compress scales by min(srcW / minWidth, srcH / minHeight);
    // passing the proportional target gives exactly width × height.
    final out = await FlutterImageCompress.compressWithList(
      input,
      minWidth: width,
      minHeight: height,
      quality: quality,
      format: CompressFormat.webp,
      keepExif: false,
    );
    return EncodedImage(out, 'image/webp');
  }
}
