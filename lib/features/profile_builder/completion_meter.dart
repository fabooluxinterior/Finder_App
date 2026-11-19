import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/profile.dart';
import '../../models/profile_completion.dart';

/// Ring showing the 0–100 profile score with the next step beside it.
class CompletionMeter extends StatelessWidget {
  const CompletionMeter({super.key, required this.profile, this.onTap, this.compact = false});
  final PublicProfile profile;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final completion = ProfileCompletion.of(profile);
    final done = completion.nextStep == null;
    final ring = SizedBox.square(
      dimension: compact ? 52 : 64,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: completion.score / 100),
        duration: Motion.of(context, const Duration(milliseconds: 600)),
        curve: Motion.easeOut,
        builder: (context, v, _) => CustomPaint(
          painter: _RingPainter(v, c.accent, c.hair),
          child: Center(
            child: Text(
              '${(v * 100).round()}%',
              style: TextStyle(fontSize: compact ? 14 : 16, fontWeight: FontWeight.w700, color: c.ink),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      label: 'Profile ${completion.score}% complete. ${completion.nextStep ?? 'All done.'}',
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: c.hair),
          ),
          child: Row(
            children: [
              ring,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      done ? 'Your profile is complete' : 'Profile strength',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      completion.nextStep ?? 'Nice work. Complete profiles get more thoughtful replies.',
                      style: TextStyle(fontSize: 14, height: 1.35, color: c.ink3),
                    ),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track);
  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * value.clamp(0, 1),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}
