import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/widgets.dart';
import '../../core/feedback.dart';

/// A short celebration when a verification is approved: the badge pops in, confetti falls, then it fades by itself.
void showVerifiedCelebration(BuildContext context) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _Celebration(onDone: () => entry.remove()));
  overlay.insert(entry);
  Fx.instance.unlock();
}

class _Celebration extends StatefulWidget {
  const _Celebration({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    })
    ..forward();
  final _rand = math.Random(7);
  late final List<_Piece> _pieces = List.generate(
    70,
    (_) => _Piece(
      _rand.nextDouble(),
      _rand.nextDouble() * 0.35,
      0.5 + _rand.nextDouble(),
      _rand.nextInt(5),
      _rand.nextDouble() * 6.28,
    ),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) {
      final t = _c.value;
      final fade = t > 0.82 ? (1 - (t - 0.82) / 0.18) : 1.0;
      final pop = Curves.elasticOut.transform((t / 0.4).clamp(0.0, 1.0));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onDone,
        child: Opacity(
          opacity: fade,
          child: Material(
            color: Colors.black.withValues(alpha: 0.55 * fade),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _ConfettiPainter(_pieces, t)),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(scale: 0.2 + 0.8 * pop, child: const VerifiedBadge(size: 96)),
                      const SizedBox(height: 18),
                      Opacity(
                        opacity: ((t - 0.15) / 0.2).clamp(0.0, 1.0),
                        child: const Text(
                          'You’re verified!',
                          style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Opacity(
                        opacity: ((t - 0.25) / 0.2).clamp(0.0, 1.0),
                        child: const Text('Ini adichu polikk 🎉', style: TextStyle(color: Colors.white70, fontSize: 16)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _Piece {
  _Piece(this.x, this.delay, this.speed, this.color, this.spin);
  final double x, delay, speed, spin;
  final int color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);
  final List<_Piece> pieces;
  final double t;
  static const _colors = [Color(0xFFFF5A3D), Color(0xFFFFC53D), Color(0xFF3DDC84), Color(0xFF3D9BFF), Color(0xFFB45CFF)];

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final k = ((t - p.delay) / 0.8).clamp(0.0, 1.0) * p.speed;
      if (k <= 0) continue;
      final x = p.x * size.width + math.sin(k * 6 + p.spin) * 18;
      final y = -20 + k * (size.height + 40);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin + k * 8);
      canvas.drawRect(const Rect.fromLTWH(-4, -2, 8, 4), Paint()..color = _colors[p.color]);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
