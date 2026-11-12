import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/feedback.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../data/media_service.dart';
import 'words.dart';

enum _Step { recording, locked, review, cancelling }

/// The voice recording bar: two lines, thin waveform, with every moment designed:
/// recording (slide left to cancel, swipe up to lock), hands-free, review before
/// sending, cancel and send. The recorder is owned by the chat screen.
class VoiceRecorderBar extends StatefulWidget {
  const VoiceRecorderBar({
    super.key,
    required this.recorder,
    required this.onSend,
    required this.onCancel,
    required this.onTooShort,
    required this.onActive,
  });

  final VoiceRecorder recorder;

  /// The finished note, from recording or from review.
  final void Function(VoiceNote note) onSend;
  final VoidCallback onCancel;
  final VoidCallback onTooShort;

  /// True while the microphone is open (recording or hands-free); false once it is not.
  final ValueChanged<bool> onActive;

  @override
  State<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<VoiceRecorderBar> with WidgetsBindingObserver {
  static const _bars = 40;
  static const _minLength = Duration(milliseconds: 800);

  _Step _step = _Step.recording;
  final _levels = List<double>.filled(_bars, 0.05, growable: true);
  final _history = <double>[];
  StreamSubscription<double>? _amp;
  Timer? _tick;
  VoiceNote? _note;
  List<double> _reviewBars = const [];
  double _dragX = 0;
  double _dragY = 0;

  AudioPlayer? _player;
  final _playerSubs = <StreamSubscription<dynamic>>[];
  bool _playing = false;
  Duration _pos = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _amp = widget.recorder.amplitude().listen((v) {
      if (!mounted || (_step != _Step.recording && _step != _Step.locked)) return;
      final level = v.clamp(0.05, 1.0);
      _history.add(level);
      setState(() {
        _levels
          ..removeAt(0)
          ..add(level);
      });
    }, onError: (_) {});
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      if ((_step == _Step.recording || _step == _Step.locked) &&
          widget.recorder.elapsed >= const Duration(seconds: AppConfig.voiceMaxSeconds)) {
        _stopToReview(); // the 45 second limit
        return;
      }
      setState(() {});
    });
    widget.onActive(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amp?.cancel();
    _tick?.cancel();
    for (final s in _playerSubs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  /// A phone call or switching apps keeps what was recorded, for review.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && (_step == _Step.recording || _step == _Step.locked)) _stopToReview();
  }

  // ------------------------------------------------------------- actions ----

  Future<void> _sendNow() async {
    if (_step == _Step.review) {
      final n = _note;
      if (n != null) widget.onSend(n);
      return;
    }
    if (_step != _Step.recording && _step != _Step.locked) return;
    widget.onActive(false);
    final note = await widget.recorder.stop();
    if (!mounted) return;
    if (note == null || note.duration < _minLength) {
      widget.onTooShort();
      return;
    }
    widget.onSend(note);
  }

  Future<void> _stopToReview() async {
    if (_step != _Step.recording && _step != _Step.locked) return;
    widget.onActive(false);
    final note = await widget.recorder.stop();
    if (!mounted) return;
    if (note == null || note.duration < _minLength) {
      widget.onTooShort();
      return;
    }
    setState(() {
      _note = note;
      _reviewBars = _downsample(_history, _bars);
      _step = _Step.review;
    });
  }

  Future<void> _cancel() async {
    if (_step == _Step.cancelling) return;
    final wasOpen = _step == _Step.recording || _step == _Step.locked;
    Fx.instance.tap();
    widget.onActive(false);
    setState(() => _step = _Step.cancelling); // the waveform flattens and the bar slides away
    await _player?.stop();
    if (wasOpen) await widget.recorder.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (mounted) widget.onCancel();
  }

  void _lock() {
    if (_step != _Step.recording) return;
    Fx.instance.tap();
    setState(() => _step = _Step.locked);
  }

  Future<void> _togglePlay() async {
    final note = _note;
    if (note == null) return;
    if (_player == null) {
      final p = AudioPlayer();
      _player = p;
      _playerSubs
        ..add(
          p.onPlayerStateChanged.listen((s) {
            if (mounted) setState(() => _playing = s == PlayerState.playing);
          }),
        )
        ..add(
          p.onPositionChanged.listen((d) {
            if (mounted) setState(() => _pos = d);
          }),
        )
        ..add(
          p.onPlayerComplete.listen((_) {
            if (mounted) setState(() => _pos = Duration.zero);
          }),
        );
    }
    if (_playing) {
      await _player!.pause();
      return;
    }
    try {
      await _player!.play(kIsWeb || note.path.isEmpty ? BytesSource(note.bytes) : DeviceFileSource(note.path));
    } catch (_) {}
  }

  static List<double> _downsample(List<double> src, int n) {
    if (src.isEmpty) return List.filled(n, 0.2);
    return [
      for (var i = 0; i < n; i++)
        () {
          final from = (i * src.length / n).floor();
          final to = math.max(from + 1, ((i + 1) * src.length / n).floor());
          final slice = src.sublist(from, math.min(to, src.length));
          return slice.reduce((a, b) => a + b) / slice.length;
        }(),
    ];
  }

  // --------------------------------------------------------------- build ----

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final cancelling = _step == _Step.cancelling;
    final open = _step == _Step.recording || _step == _Step.locked;
    final elapsed = open ? widget.recorder.elapsed : (_note?.duration ?? Duration.zero);
    final secs = elapsed.inSeconds.clamp(0, AppConfig.voiceMaxSeconds);
    final warn = open && secs >= AppConfig.voiceMaxSeconds - 5;
    final shownSecs = _step == _Step.review && _playing ? _pos.inSeconds : secs;

    final top = switch (_step) {
      _Step.recording => const WordsLine(words: 'Recording audio'),
      _Step.locked => const WordsLine(words: 'Hands-free'),
      _Step.review => Text(
        'Review before sending',
        style: TextStyle(fontSize: 12.5, color: c.ink2, fontWeight: FontWeight.w500),
      ),
      _Step.cancelling => Text('Voice note cancelled', style: TextStyle(fontSize: 12.5, color: c.muted)),
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: open
          ? (d) {
              _dragX += d.delta.dx;
              if (_dragX < -90) {
                _dragX = 0;
                _cancel();
              }
            }
          : null,
      onHorizontalDragEnd: (_) => _dragX = 0,
      onVerticalDragUpdate: _step == _Step.recording
          ? (d) {
              _dragY += d.delta.dy;
              if (_dragY < -40) {
                _dragY = 0;
                _lock();
              }
            }
          : null,
      onVerticalDragEnd: (_) => _dragY = 0,
      child: AnimatedSlide(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
        curve: Curves.easeIn,
        offset: cancelling ? const Offset(-0.12, 0) : Offset.zero,
        child: AnimatedOpacity(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
          opacity: cancelling ? 0.0 : 1.0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Align(alignment: Alignment.centerLeft, child: top),
                    ),
                    if (_step == _Step.recording) Text('‹ Slide to cancel', style: TextStyle(fontSize: 12.5, color: c.muted)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (_step == _Step.recording)
                      const _BlinkDot()
                    else
                      _IconBtn(
                        icon: PhosphorIconsRegular.trash,
                        color: const Color(0xFFE5484D),
                        label: 'Delete voice note',
                        onTap: _cancel,
                      ),
                    if (_step == _Step.review)
                      _IconBtn(
                        icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: c.ink,
                        label: _playing ? 'Pause' : 'Play',
                        onTap: _togglePlay,
                      ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 38,
                      child: Text(
                        '${shownSecs ~/ 60}:${(shownSecs % 60).toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: warn ? c.accent : c.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _Wave(
                        bars: _bars,
                        levels: open || cancelling ? _levels : _reviewBars,
                        flat: cancelling,
                        progress: _step == _Step.review ? _progress() : null,
                        accentTail: open,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_step == _Step.locked)
                      _RoundBtn(icon: Icons.stop_rounded, filled: false, label: 'Stop and review', onTap: _stopToReview)
                    else
                      _RoundBtn(icon: PhosphorIconsFill.paperPlaneTilt, filled: true, label: 'Send voice note', onTap: _sendNow),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _progress() {
    final total = _note?.duration.inMilliseconds ?? 0;
    return total == 0 ? 0 : (_pos.inMilliseconds / total).clamp(0.0, 1.0);
  }
}

/// Thin bars (1.5 px), newest on the right; the last three are the accent colour.
class _Wave extends StatelessWidget {
  const _Wave({required this.bars, required this.levels, required this.flat, required this.accentTail, this.progress});
  final int bars;
  final List<double> levels;
  final bool flat;
  final bool accentTail;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: 30,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < bars; i++)
            AnimatedContainer(
              duration: reduce ? Duration.zero : Duration(milliseconds: flat ? 250 : 90),
              width: 1.5,
              height: flat ? 1.5 : 3 + 26 * (i < levels.length ? levels[i] : 0.05),
              decoration: BoxDecoration(
                color: progress != null
                    ? ((i / bars) < progress! ? c.accent : c.ink.withValues(alpha: 0.32))
                    : (accentTail && i >= bars - 3 ? c.accent : c.ink),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

class _BlinkDot extends StatefulWidget {
  const _BlinkDot();

  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 34,
    child: Center(
      child: FadeTransition(
        opacity: Tween(begin: 0.25, end: 1.0).animate(_c),
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: context.fc.accent, shape: BoxShape.circle),
        ),
      ),
    ),
  );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.color, required this.label, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: label,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    padding: EdgeInsets.zero,
    icon: Icon(icon, size: 20, color: color),
  );
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.filled, required this.label, required this.onTap});
  final IconData icon;
  final bool filled;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: filled ? c.accent : c.ink, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: filled ? Colors.white : c.paper),
        ),
      ),
    );
  }
}
