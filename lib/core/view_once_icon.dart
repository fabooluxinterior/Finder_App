import 'dart:math' as math;

import 'package:flutter/material.dart';

/// "View once": a thin dotted circle with a small 1 inside. Filled when it is switched on.
class ViewOnceIcon extends StatelessWidget {
  const ViewOnceIcon({super.key, this.size = 24, this.color = Colors.white, this.filled = false});
  final double size;
  final Color color;

  /// A solid disc with the 1 cut out (the "on" state).
  final bool filled;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _OncePainter(color, filled));
}

class _OncePainter extends CustomPainter {
  _OncePainter(this.color, this.filled);
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final center = Offset(12 * u, 12 * u);
    final r = 9 * u;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (filled) {
      canvas.drawCircle(center, r, Paint()..color = color);
    } else {
      // Dotted ring: 14 short arcs.
      const n = 14;
      const sweep = 2 * math.pi / n;
      for (var i = 0; i < n; i++) {
        canvas.drawArc(Rect.fromCircle(center: center, radius: r), i * sweep, sweep * 0.55, false, stroke);
      }
    }
    final one = Path()
      ..moveTo(10.5 * u, 9.8 * u)
      ..lineTo(12.2 * u, 8.5 * u)
      ..lineTo(12.2 * u, 15.5 * u);
    canvas.drawPath(one, filled ? (stroke..color = const Color(0xFF111113)) : stroke);
  }

  @override
  bool shouldRepaint(covariant _OncePainter old) => old.color != color || old.filled != filled;
}
