import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// A player set up for clear speech: the media stream at full volume, content type "speech",
/// and normal audio focus so other sounds don't cut into the voice.
AudioPlayer speechPlayer() {
  final p = AudioPlayer();
  if (!kIsWeb) {
    p
        .setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              contentType: AndroidContentType.speech,
              usageType: AndroidUsageType.media,
              audioFocus: AndroidAudioFocus.gain,
              stayAwake: true,
            ),
            iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
          ),
        )
        .catchError((_) {});
    p.setVolume(1.0).catchError((_) {});
  }
  return p;
}
