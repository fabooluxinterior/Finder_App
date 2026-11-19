import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sound + haptics, fired on the same frame as the visual they belong to
/// (apple-design §13). Reserved for meaningful moments; Pass is haptic-only
/// because it's the most frequent action. Sounds follow the phone's silent
/// mode and the in-app setting.
class Fx {
  Fx._();
  static final instance = Fx._();

  static const _prefKey = 'sounds_enabled';
  bool soundsEnabled = true;
  final _players = <String, AudioPlayer>{};

  Future<void> init() async {
    try {
      soundsEnabled = (await SharedPreferences.getInstance()).getBool(_prefKey) ?? true;
      final ctx = AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers, respectSilence: true).build();
      for (final name in ['request', 'match', 'sent', 'received', 'unlock']) {
        final p = AudioPlayer(playerId: 'fx_$name');
        await p.setAudioContext(ctx);
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setSource(AssetSource('sounds/$name.wav'));
        await p.setVolume(0.6);
        _players[name] = p;
      }
    } catch (_) {
      // Sound is optional; the visual always stands alone.
    }
  }

  Future<void> setSoundsEnabled(bool v) async {
    soundsEnabled = v;
    try {
      await (await SharedPreferences.getInstance()).setBool(_prefKey, v);
    } catch (_) {}
  }

  void _play(String name) {
    if (!soundsEnabled) return;
    final p = _players[name];
    if (p == null) return;
    p.stop().then((_) => p.resume()).catchError((_) {});
  }

  void tap() => HapticFeedback.selectionClick();
  void pass() => HapticFeedback.lightImpact();

  void request() {
    HapticFeedback.mediumImpact();
    _play('request');
  }

  void match() {
    HapticFeedback.heavyImpact();
    _play('match');
  }

  void sent() {
    HapticFeedback.lightImpact();
    _play('sent');
  }

  DateTime? _lastReceived;

  /// One sound per incoming message: the chat, the home screen and a push can all notice the same
  /// message, so calls within 1.5 s of the last one are ignored.
  void received() {
    final now = DateTime.now();
    final last = _lastReceived;
    if (last != null && now.difference(last) < const Duration(milliseconds: 1500)) return;
    _lastReceived = now;
    _play('received');
  }

  void unlock() {
    HapticFeedback.mediumImpact();
    _play('unlock');
  }
}
