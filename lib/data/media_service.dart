import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../core/config.dart';

class MediaService {
  static const maxImageBytes = 100 * 1024;
  static const _imageSide = 800;

  final _picker = ImagePicker();

  /// Picks a photo and compresses it to WebP, 800x800 bounds, quality 70,
  /// stepping quality down only if the result is still over 100 KB.
  Future<Uint8List?> pickCompressedPhoto() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600);
    if (file == null) return null;
    final raw = await file.readAsBytes();
    if (kIsWeb) return raw; // Web is demo-only; nothing is uploaded.

    for (var quality = 70; quality >= 30; quality -= 10) {
      final out = await FlutterImageCompress.compressWithList(
        raw,
        minWidth: _imageSide,
        minHeight: _imageSide,
        quality: quality,
        format: CompressFormat.webp,
      );
      if (out.lengthInBytes <= maxImageBytes) return out;
    }
    throw StateError('Photo is too detailed to compress under 100 KB. Try another one.');
  }
}

class VoiceNote {
  const VoiceNote({required this.bytes, required this.path, required this.duration});
  final Uint8List bytes;
  final String path;
  final Duration duration;
}

/// 45-second capped voice recorder: AAC-LC, mono, 32 kbps.
class VoiceRecorder {
  final _recorder = AudioRecorder();
  final _stopwatch = Stopwatch();
  Timer? _cap;

  Stream<double> amplitude() => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 90))
      // dBFS (-60..0) -> 0..1
      .map((a) => ((a.current + 60) / 60).clamp(0.0, 1.0).toDouble());

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start({required void Function() onCapReached}) async {
    var encoder = AudioEncoder.aacLc;
    if (kIsWeb && !await _recorder.isEncoderSupported(encoder)) {
      encoder = AudioEncoder.opus; // Browser demo fallback only.
    }
    final path = kIsWeb ? '' : '${(await getTemporaryDirectory()).path}/${const Uuid().v4()}.m4a';
    await _recorder.start(
      RecordConfig(
        encoder: encoder,
        bitRate: AppConfig.voiceBitRate,
        sampleRate: AppConfig.voiceSampleRate,
        numChannels: 1,
        noiseSuppress: true,
        echoCancel: true,
      ),
      path: path,
    );
    _stopwatch
      ..reset()
      ..start();
    _cap = Timer(const Duration(seconds: AppConfig.voiceMaxSeconds), onCapReached);
  }

  Duration get elapsed => _stopwatch.elapsed;

  Future<VoiceNote?> stop() async {
    _cap?.cancel();
    _stopwatch.stop();
    final path = await _recorder.stop();
    if (path == null) return null;
    final bytes = await XFile(path).readAsBytes();
    return VoiceNote(bytes: bytes, path: path, duration: _stopwatch.elapsed);
  }

  Future<void> cancel() async {
    _cap?.cancel();
    _stopwatch.stop();
    await _recorder.cancel();
  }

  Future<void> dispose() async {
    _cap?.cancel();
    await _recorder.dispose();
  }
}
