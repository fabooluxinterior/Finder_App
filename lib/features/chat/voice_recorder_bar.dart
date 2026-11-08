import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/phosphor.dart';

import '../../core/theme.dart';
import '../../data/media_service.dart';

/// Live recording strip: rolling amplitude waveform, timer with 45 s cap.
class VoiceRecorderBar extends StatefulWidget {
  const VoiceRecorderBar({super.key, required this.recorder, required this.onCancel, required this.onSend});

  final VoiceRecorder recorder;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  State<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<VoiceRecorderBar> {
  static const _bars = 36;
  final _levels = List<double>.filled(_bars, 0.05, growable: true);
  StreamSubscription<double>? _amp;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _amp = widget.recorder.amplitude().listen((v) {
      setState(() {
        _levels
          ..removeAt(0)
          ..add(v.clamp(0.05, 1.0));
      });
    }, onError: (_) {});
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _amp?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.recorder.elapsed;
    final secs = elapsed.inSeconds.clamp(0, AppConfig.voiceMaxSeconds);
    final remaining = AppConfig.voiceMaxSeconds - secs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Discard',
            onPressed: widget.onCancel,
            icon: const Icon(PhosphorIconsRegular.trash, color: Color(0xFFE5484D)),
          ),
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: context.fc.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: context.fc.hair),
              ),
              child: Row(
                children: [
                  const _PulsingDot(),
                  const SizedBox(width: 8),
                  Text(
                    '0:${secs.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final l in _levels)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 90),
                            width: 2.5,
                            height: 4 + 26 * l,
                            decoration: BoxDecoration(color: context.fc.accent, borderRadius: BorderRadius.circular(2)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${remaining}s', style: TextStyle(color: context.fc.muted, fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox.square(
            dimension: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 48),
                shape: const CircleBorder(),
              ),
              onPressed: widget.onSend,
              child: const Icon(PhosphorIconsFill.paperPlaneTilt, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.3, end: 1.0).animate(_c),
    child: const CircleAvatar(radius: 5, backgroundColor: Colors.redAccent),
  );
}
