import 'dart:typed_data';

import 'image_encoder_io.dart' if (dart.library.js_interop) 'image_encoder_web.dart' as platform;

/// Client-side photo optimisation: every profile photo is converted to WebP,
/// fitted inside a 1080 px box (aspect ratio kept) and compressed below
/// 100 KB *before* any upload request, so storage only ever holds small files.
/// The server still validates and strips metadata (never trusts the client).
class ImageOptimizer {
  static const maxSide = 1080;
  static const maxBytes = 100 * 1024;

  /// Quality ladder, then progressively smaller sizes if a photo is very
  /// detailed. Tried in order; the first result under [maxBytes] wins.
  static const qualities = [82, 74, 66, 58, 50, 42];
  static const scales = [1.0, 0.85, 0.72, 0.6];

  static const _encoder = platform.PlatformImageEncoder();

  /// Chat photos: any image the phone can open (JPEG, PNG, HEIC, WebP, GIF, BMP, AVIF…), any size,
  /// compressed to WebP (≤300 KB, longest side ≤1280 px). Never refuses for being small or detailed.
  static Future<OptimizedImage> optimizeForChat(Uint8List input) => optimize(
    input,
    maxBytes: 300 * 1024,
    maxSide: 1280,
    minSide: 1,
    anyFormat: true,
    scales: const [1.0, 0.85, 0.72, 0.6, 0.5, 0.4, 0.3, 0.2],
  );

  /// Optimises picked bytes (JPEG, PNG, HEIC/HEIF or WebP). Profile photos use the defaults.
  static Future<OptimizedImage> optimize(
    Uint8List input, {
    int maxBytes = ImageOptimizer.maxBytes,
    int maxSide = ImageOptimizer.maxSide,
    int minSide = 200,
    bool anyFormat = false,
    List<double> scales = ImageOptimizer.scales,
  }) async {
    final sniffed = sniff(input);
    final format = sniffed ?? (anyFormat && input.isNotEmpty ? ImageFormat.other : null); // other: let the phone try
    if (format == null) {
      throw const ImageOptimizeException('That file isn’t a photo we can use. Choose a JPEG, PNG, HEIC or WebP image.');
    }
    final SourceSize source;
    try {
      source = await _encoder.decodeSize(input, format);
    } catch (_) {
      throw const ImageOptimizeException('This phone can’t open that image. Try another one.');
    }
    if (source.width < minSide || source.height < minSide) {
      throw const ImageOptimizeException('That photo is too small. Choose one at least 200 × 200 pixels.');
    }
    final plan = planResize(source.width, source.height, side: maxSide);
    final out = await fitUnder(maxBytes, scales: scales, (quality, scale) {
      final w = (plan.width * scale).round(), h = (plan.height * scale).round();
      return _encoder.encode(input, format, source, width: w, height: h, quality: quality);
    });
    return OptimizedImage(out.bytes, out.mime, plan.width, plan.height);
  }

  /// Largest size inside the [maxSide] box with the same aspect ratio
  /// (never upscales).
  static ({int width, int height}) planResize(int width, int height, {int side = maxSide}) {
    final s = (side / (width > height ? width : height)).clamp(0.0, 1.0);
    return (width: (width * s).round().clamp(1, side), height: (height * s).round().clamp(1, side));
  }

  /// Runs [encode] down the quality ladder (and then smaller scales) until
  /// the result fits in [limit] bytes.
  static Future<EncodedImage> fitUnder(
    int limit,
    Future<EncodedImage> Function(int quality, double scale) encode, {
    List<double> scales = ImageOptimizer.scales,
  }) async {
    for (final scale in scales) {
      for (final q in qualities) {
        final r = await encode(q, scale);
        if (r.bytes.lengthInBytes <= limit) return r;
      }
    }
    throw const ImageOptimizeException('This photo is too detailed to shrink. Try another one.');
  }

  static ImageFormat? sniff(Uint8List b) {
    if (b.length < 12) return null;
    if (b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) return ImageFormat.jpeg;
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47) return ImageFormat.png;
    String ascii(int at, int n) => String.fromCharCodes(b.sublist(at, at + n));
    if (ascii(0, 4) == 'RIFF' && ascii(8, 4) == 'WEBP') return ImageFormat.webp;
    if (ascii(4, 4) == 'ftyp' && const {'heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1', 'heis'}.contains(ascii(8, 4))) {
      return ImageFormat.heic;
    }
    // Recognised for chat photos (profile photos still accept JPEG, PNG, WebP and HEIC only).
    if (ascii(0, 3) == 'GIF') return ImageFormat.gif;
    if (b[0] == 0x42 && b[1] == 0x4d) return ImageFormat.bmp;
    if (ascii(4, 4) == 'ftyp' && const {'avif', 'avis'}.contains(ascii(8, 4))) return ImageFormat.avif;
    return null;
  }
}

enum ImageFormat { jpeg, png, webp, heic, gif, bmp, avif, other }

class EncodedImage {
  const EncodedImage(this.bytes, this.mime);
  final Uint8List bytes;

  /// `image/webp`, or `image/jpeg` where the platform can't encode WebP
  /// (some Safari versions); the server converts those to WebP.
  final String mime;
}

class OptimizedImage {
  const OptimizedImage(this.bytes, this.mime, this.width, this.height);
  final Uint8List bytes;
  final String mime;
  final int width;
  final int height;

  String get extension => mime == 'image/webp' ? 'webp' : 'jpg';
}

class ImageOptimizeException implements Exception {
  const ImageOptimizeException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SourceSize {
  const SourceSize(this.width, this.height);
  final int width;
  final int height;
}
