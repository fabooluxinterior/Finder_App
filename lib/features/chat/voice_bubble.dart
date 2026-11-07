import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/message.dart';
import '../../providers.dart';

/// Voice notes are downloaded as ciphertext and decrypted on this device
/// just before playback; decrypted audio is held in memory only.
class VoiceBubble extends ConsumerStatefulWidget {
  const VoiceBubble({super.key, required this.message, required this.color});
  final ChatMessage message;
  final Color color;

  @override
  ConsumerState<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends ConsumerState<VoiceBubble> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription<dynamic>>[];
  PlayerState _state = PlayerState.stopped;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _loading = false;
  bool _sourceSet = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final ms = widget.message.voice?.millis ?? 0;
    if (ms > 0) _dur = Duration(milliseconds: ms);
    _subs
      ..add(_player.onPlayerStateChanged.listen((s) => setState(() => _state = s)))
      ..add(_player.onPositionChanged.listen((p) => setState(() => _pos = p)))
      ..add(_player.onDurationChanged.listen((d) => setState(() => _dur = d)))
      ..add(_player.onPlayerComplete.listen((_) => setState(() => _pos = Duration.zero)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
      return;
    }
    if (!_sourceSet) {
      setState(() => _loading = true);
      try {
        final playback = await ref.read(backendProvider).voicePlayback(widget.message);
        if (playback.bytes != null) {
          await _player.setSource(BytesSource(playback.bytes!, mimeType: 'audio/mp4'));
        } else {
          final url = playback.url!;
          final isRemote = url.startsWith('http') || url.startsWith('blob:');
          await _player.setSource(isRemote ? UrlSource(url) : DeviceFileSource(url));
        }
        _sourceSet = true;
      } catch (_) {
        if (mounted) setState(() => _failed = true);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      if (!_sourceSet) return;
    }
    await _player.resume();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _dur.inMilliseconds == 0 ? 0.0 : _pos.inMilliseconds / _dur.inMilliseconds;
    final shown = _state == PlayerState.playing || _pos > Duration.zero ? _pos : _dur;
    final c = widget.color;
    final seed = widget.message.id;
    return SizedBox(
      width: 210,
      child: Row(children: [
        InkWell(
          customBorder: const CircleBorder(),
          onTap: _loading || _failed ? null : _toggle,
          child: CircleAvatar(
            radius: 18,
            backgroundColor: c.withValues(alpha: 0.18),
            child: _loading
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c))
                : Icon(
                    _failed
                        ? Icons.error_outline
                        : (_state == PlayerState.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    color: c),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 24; i++)
                Container(
                  width: 3,
                  height: 6.0 + ((seed.codeUnitAt(i % seed.length) * (i + 3)) % 18),
                  decoration: BoxDecoration(
                    color: (i / 24) <= progress ? c : c.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${shown.inMinutes}:${(shown.inSeconds % 60).toString().padLeft(2, '0')}',
          style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}
