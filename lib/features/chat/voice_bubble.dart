import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../../data/voice_audio.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/message.dart';
import '../../providers.dart';
import 'words.dart';

/// A sent or received voice note: thin candles are the timeline (the played part turns
/// accent, tap to jump, drag to scrub), quiet words say what it is doing, and a speed chip
/// steps 1×, 1.5×, 2×. Voice notes are downloaded as ciphertext and decrypted on this device
/// just before playback; decrypted audio is held in memory only.
class VoiceBubble extends ConsumerStatefulWidget {
  const VoiceBubble({super.key, required this.message, required this.color});
  final ChatMessage message;
  final Color color;

  /// Voice notes already heard on this phone (this session).
  static final listened = <String>{};

  @override
  ConsumerState<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends ConsumerState<VoiceBubble> {
  static _VoiceBubbleState? _active; // starting one voice note pauses another
  static const _candles = 34;
  static const _rates = [1.0, 1.5, 2.0];

  final _player = speechPlayer();
  final _subs = <StreamSubscription<dynamic>>[];
  PlayerState _state = PlayerState.stopped;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _loading = false;
  bool _sourceSet = false;
  bool _failed = false;
  int _rate = 0;
  double? _scrub; // 0..1 while a finger is on the candles

  @override
  void initState() {
    super.initState();
    final ms = widget.message.voice?.millis ?? 0;
    if (ms > 0) _dur = Duration(milliseconds: ms);
    _subs
      ..add(
        _player.onPlayerStateChanged.listen((s) {
          if (mounted) setState(() => _state = s);
        }),
      )
      ..add(
        _player.onPositionChanged.listen((p) {
          if (mounted) setState(() => _pos = p);
        }),
      )
      ..add(
        _player.onDurationChanged.listen((d) {
          if (mounted) setState(() => _dur = d);
        }),
      )
      ..add(
        _player.onPlayerComplete.listen((_) {
          VoiceBubble.listened.add(widget.message.id);
          if (mounted) setState(() => _pos = Duration.zero);
        }),
      );
  }

  @override
  void dispose() {
    if (_active == this) _active = null;
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose(); // leaving the chat stops playback
    super.dispose();
  }

  bool get _playing => _state == PlayerState.playing;

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_failed) {
      setState(() {
        _failed = false;
        _sourceSet = false;
      });
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
    if (_active != null && _active != this) await _active!._player.pause();
    _active = this;
    await _player.setPlaybackRate(_rates[_rate]);
    await _player.resume();
  }

  Future<void> _cycleSpeed() async {
    setState(() => _rate = (_rate + 1) % _rates.length);
    if (_sourceSet) await _player.setPlaybackRate(_rates[_rate]);
  }

  Future<void> _seekTo(double f) async {
    if (!_sourceSet || _dur == Duration.zero) return;
    await _player.seek(Duration(milliseconds: (f * _dur.inMilliseconds).round()));
  }

  static String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final fc = context.fc;
    final ink = widget.color;
    final progress = _scrub ?? (_dur.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0));
    final heard = VoiceBubble.listened.contains(widget.message.id);

    final Widget words;
    if (_failed) {
      words = Text('Couldn’t play. Tap to retry', style: TextStyle(fontSize: 12, color: fc.accent));
    } else if (_playing) {
      words = WordsLine(words: 'playing', size: 12, color: ink.withValues(alpha: 0.7));
    } else if (_pos > Duration.zero) {
      words = Text('Paused', style: TextStyle(fontSize: 12, color: ink.withValues(alpha: 0.7)));
    } else if (heard) {
      words = Text(
        'Listened',
        style: TextStyle(fontSize: 12, color: fc.accent, fontWeight: FontWeight.w600),
      );
    } else {
      words = Text('Voice note', style: TextStyle(fontSize: 12, color: ink.withValues(alpha: 0.7)));
    }

    final seed = widget.message.id;
    return SizedBox(
      width: 232,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _failed ? _toggle : null,
                    child: Align(alignment: Alignment.centerLeft, child: words),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Playback speed',
                  child: GestureDetector(
                    onTap: _cycleSpeed,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(color: ink.withValues(alpha: 0.55), width: 1),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${_rates[_rate] == 1.5 ? '1.5' : _rates[_rate].toInt()}×',
                        style: TextStyle(fontSize: 11, color: ink.withValues(alpha: 0.8)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _fmt(
                    _scrub != null && _dur > Duration.zero
                        ? Duration(milliseconds: (_scrub! * _dur.inMilliseconds).round())
                        : (_playing || _pos > Duration.zero ? _pos : _dur),
                  ),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: ink.withValues(alpha: 0.7),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Semantics(
                button: true,
                label: _playing ? 'Pause' : 'Play',
                child: InkResponse(
                  radius: 20,
                  onTap: _loading ? null : _toggle,
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: _loading
                        ? Padding(
                            padding: const EdgeInsets.all(9),
                            child: CircularProgressIndicator(strokeWidth: 1.6, color: ink),
                          )
                        : Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 24, color: ink),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final w = box.maxWidth;
                    double frac(Offset p) => (p.dx / w).clamp(0.0, 1.0);
                    return Semantics(
                      slider: true,
                      label: 'Voice note position',
                      value: _fmt(_pos),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => _seekTo(frac(d.localPosition)),
                        onHorizontalDragStart: (d) => setState(() => _scrub = frac(d.localPosition)),
                        onHorizontalDragUpdate: (d) => setState(() => _scrub = frac(d.localPosition)),
                        onHorizontalDragEnd: (_) async {
                          final f = _scrub;
                          setState(() => _scrub = null);
                          if (f != null) await _seekTo(f);
                        },
                        child: SizedBox(
                          height: 30,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.centerLeft,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  for (var i = 0; i < _candles; i++)
                                    Container(
                                      width: 2,
                                      height: 6.0 + ((seed.codeUnitAt(i % seed.length) * (i + 3)) % 20),
                                      decoration: BoxDecoration(
                                        color: (i / _candles) < progress ? fc.accent : ink.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                ],
                              ),
                              if (_playing || _scrub != null || _pos > Duration.zero)
                                Positioned(
                                  left: (progress * w - 1).clamp(0.0, w - 1.5),
                                  top: 2,
                                  bottom: 2,
                                  child: Container(
                                    width: 1.5,
                                    decoration: BoxDecoration(color: fc.accent, borderRadius: BorderRadius.circular(2)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
