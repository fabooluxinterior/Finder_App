import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../core/config.dart';

class MediaService {
  /// Upload size cap. The server re-encodes every photo to an 800×800 WebP
  /// (≤100 KB) after validation and moderation, so the client only needs to
  /// send a reasonably sized JPEG.
  static const maxUploadBytes = 2 * 1024 * 1024;
  static const _uploadSide = 1600;

  final _picker = ImagePicker();

  /// Picks a photo and compresses it to a JPEG (≤1600 px, EXIF dropped)
  /// for upload. Client-side checks are a convenience: the server validates
  /// the real file type, strips metadata, moderates and re-encodes anyway.
  Future<Uint8List?> pickCompressedPhoto() => _pick(ImageSource.gallery);

  /// Picks a photo and returns the original bytes (JPEG, PNG, HEIC or WebP),
  /// for [ImageOptimizer] to convert into a ≤100 KB WebP on the device.
  Future<Uint8List?> pickOriginalPhoto({bool camera = false}) async {
    final file = await _picker.pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, requestFullMetadata: false);
    return file?.readAsBytes();
  }

  /// Live front-camera capture for selfie verification. There is deliberately
  /// no gallery fallback: the photo must be taken now, with the requested pose.
  Future<Uint8List?> takeSelfie() => _pick(ImageSource.camera, camera: CameraDevice.front);

  Future<Uint8List?> _pick(ImageSource source, {CameraDevice camera = CameraDevice.rear}) async {
    final file = await _picker.pickImage(
      source: source,
      preferredCameraDevice: camera,
      maxWidth: _uploadSide.toDouble(),
      maxHeight: _uploadSide.toDouble(),
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final raw = await file.readAsBytes();
    if (kIsWeb) {
      // Browsers already re-encode via image_picker; the server does the rest.
      if (raw.lengthInBytes > maxUploadBytes) throw StateError('Photo is larger than 2 MB. Try another one.');
      return raw;
    }
    for (var quality = 85; quality >= 50; quality -= 10) {
      final out = await FlutterImageCompress.compressWithList(
        raw,
        minWidth: _uploadSide,
        minHeight: _uploadSide,
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (out.lengthInBytes <= maxUploadBytes) return out;
    }
    throw StateError('Photo is too large. Try another one.');
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
  // Created on first use, so opening a chat doesn't touch the microphone plugin.
  AudioRecorder? _rec;
  AudioRecorder get _recorder => _rec ??= AudioRecorder();
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
        // The phone's noise suppression and echo cancelling can chop speech into pieces; leave them
        // off and let a gentle automatic gain keep quiet voices audible.
        noiseSuppress: false,
        echoCancel: false,
        autoGain: true,
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
    await _rec?.dispose();
  }
}
