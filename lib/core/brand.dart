import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'svg_path.dart';
import 'theme.dart';

/// The Vouby identity: a speech bubble with a cursive v cut out as one
/// continuous line, plus the "vouby." wordmark. Shapes come straight from the
/// design source (64×64 and 24×24 grids).
class VoubyPaths {
  static final bubble = parseSvgPath('M32 5a24 24 0 0 1 9.6 46L30.2 61.4a1.6 1.6 0 0 1-2.7-.7L25.6 52A24 24 0 0 1 32 5z');

  /// Large sizes: fine pen.
  static final line = parseSvgPath(
    'M19.5 22c2 7 6 15.5 10 16.5c4 0 9.5-9 11-16c1-5-3.5-7-5.5-3.8c-2.4 3.8 2.6 7.3 9 4.8c4-1.5 7.5-4 12-5',
  );

  /// Below ~48 px the pen gets heavier and the loop opens up.
  static final lineSmall = parseSvgPath(
    'M17.5 20.5c2.4 8 6.4 18 11.4 18.8c4.8.2 9.4-9.6 11.6-17.8c1.4-6-5.2-9.2-8.2-4.6c-3 4.8 3.4 9 11.2 6c4-1.6 7-3.6 11.5-4.6',
  );
}

/// The bubble mark. [progress] < 1 draws the v partially (opening animation).
class VoubyMark extends StatelessWidget {
  const VoubyMark({super.key, this.size = 40, this.color, this.progress = 1});
  final double size;
  final Color? color;
  final double progress;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _MarkPainter(color ?? context.fc.accent, size < 48, progress)),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color, this.small, this.progress);
  final Color color;
  final bool small;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    canvas.save();
    canvas.scale(s);
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 64, 64), Paint());
    canvas.drawPath(VoubyPaths.bubble, Paint()..color = color);
    var line = small ? VoubyPaths.lineSmall : VoubyPaths.line;
    if (progress < 1) {
      final m = line.computeMetrics().first;
      line = m.extractPath(0, m.length * progress.clamp(0, 1));
    }
    if (progress > 0) {
      canvas.drawPath(
        line,
        Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.stroke
          ..strokeWidth = small ? 6.4 : 3.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color || old.progress != progress || old.small != small;
}

/// "vouby." with an orange full stop, optionally led by the mark.
class VoubyWordmark extends StatelessWidget {
  const VoubyWordmark({super.key, this.size = 28, this.mark = true, this.markColor});
  final double size;
  final bool mark;
  final Color? markColor;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (mark) ...[VoubyMark(size: size * 0.95, color: markColor ?? c.ink), SizedBox(width: size * 0.25)],
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'vouby'),
              TextSpan(
                text: '.',
                style: TextStyle(color: c.accent),
              ),
            ],
          ),
          semanticsLabel: 'Vouby',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: size,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: -size * 0.05,
            color: c.ink,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- icons

/// Line icons drawn with the logo's pen: 24 px grid, 2 px stroke, round
/// caps and joins.
class VIcons {
  static const back = 'M15 5l-7 7 7 7';
  static const close = 'M6 6l12 12M18 6 6 18';
  static const more = 'M4.5 12a1 1 0 1 0 2 0a1 1 0 1 0-2 0M11 12a1 1 0 1 0 2 0a1 1 0 1 0-2 0M17.5 12a1 1 0 1 0 2 0a1 1 0 1 0-2 0';
  static const share = 'M12 15V3.5M7.5 8 12 3.5 16.5 8M5 13v5a3 3 0 0 0 3 3h8a3 3 0 0 0 3-3v-5';
  static const plus = 'M12 5v14M5 12h14';
  static const send = 'M20.5 3.5 10.5 13.5M20.5 3.5l-6.5 17-3.5-7-7-3.5z';
  static const settings =
      'M4 7h9M18 7h2M4 17h2M11 17h9M13 7a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0M6 17a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0';
  static const arrowRight = 'M5 12h14M13 6l6 6-6 6';
  static const done = 'M5 12.5l4.5 4.5L19 7';
  static const report = 'M12 3.5l9 16H3zM12 10v4M12 17h.01';
  static const voice = 'M9 6a3 3 0 0 1 6 0v5a3 3 0 0 1-6 0zM5 11a7 7 0 0 0 14 0M12 18v3';
  static const photo =
      'M6 4h12a3 3 0 0 1 3 3v10a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3zM7.5 9.5a1.8 1.8 0 1 0 3.6 0a1.8 1.8 0 1 0-3.6 0M21 15.5l-5-5-10 9.5';
  static const photos = 'M3.5 7h17v13h-17zM3.5 16l5-5 5 5 3-3 4 4';
  static const invite = 'M5 8a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0M2 20a6.5 6.5 0 0 1 13 0M19 8v6M16 11h6';
  static const profile = 'M8 8a4 4 0 1 0 8 0a4 4 0 1 0-8 0M4 21a8 8 0 0 1 16 0';
  static const chat = 'M12 3.5a8.5 8.5 0 0 1 3.4 16.3L11.3 22.3a.6.6 0 0 1-.9-.4l-.6-2.6A8.5 8.5 0 0 1 12 3.5z';
  static const chatV = 'M9 10.2c.6 2 1.6 4 2.8 4.2 1.2 0 2.5-2.3 3.2-4.6';
  static const cards =
      'M10 3h8a3 3 0 0 1 3 3v10a3 3 0 0 1-3 3M6 6h8a3 3 0 0 1 3 3v9a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3V9a3 3 0 0 1 3-3z';
}

final _pathCache = <String, Path>{};
Path _cached(String d) => _pathCache.putIfAbsent(d, () => parseSvgPath(d));

class VIcon extends StatelessWidget {
  const VIcon(this.d, {super.key, this.size = 24, this.color, this.stroke = 2, this.fill = false});
  final String d;
  final double size;
  final Color? color;
  final double stroke;
  final bool fill;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _IconPainter([_cached(d)], color ?? IconTheme.of(context).color ?? context.fc.ink, stroke, fill)),
  );
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.paths, this.color, this.stroke, this.fill);
  final List<Path> paths;
  final Color color;
  final double stroke;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final p = Paint()
      ..color = color
      ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final path in paths) {
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.color != color || old.paths != paths;
}

enum TabKind { discover, suggestions, requests, chats, you }

/// Tab-bar icons: outline when idle; when active they fill in and cut their
/// detail out, like the mark. The Chats tab becomes the logo itself.
class TabIcon extends StatelessWidget {
  const TabIcon({super.key, required this.kind, required this.active, required this.color, this.size = 26, this.cutout});

  /// Colour of the shapes cut out of a filled icon (the page background).
  final Color? cutout;
  final TabKind kind;
  int get index => switch (kind) {
    TabKind.discover => 0,
    TabKind.requests => 1,
    TabKind.chats => 2,
    TabKind.you => 3,
    TabKind.suggestions => 4,
  };
  final bool active;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _TabPainter(index, active, color, cutout ?? const Color(0xFF0B0B0C))),
    );
  }
}

class _TabPainter extends CustomPainter {
  _TabPainter(this.index, this.active, this.color, this.cutout);
  final int index;
  final bool active;
  final Color color;
  final Color cutout;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    switch (index) {
      case 0: // Discover: two stacked cards
        final back = RRect.fromRectAndRadius(const Rect.fromLTWH(7, 3, 14, 16), const Radius.circular(3));
        final front = RRect.fromRectAndRadius(const Rect.fromLTWH(3, 6, 14, 15), const Radius.circular(3));
        canvas.drawRRect(back, stroke);
        if (active) {
          canvas.drawRRect(front, fill);
        } else {
          canvas.drawRRect(front, Paint()..color = cutout);
          canvas.drawRRect(front, stroke);
        }
      case 1: // Requests: person with a plus
        if (active) {
          canvas.drawCircle(const Offset(8.5, 8), 4, fill);
          canvas.drawPath(_cached('M1.5 20.5a7 7 0 0 1 14 0z'), fill);
          canvas.drawPath(_cached('M19 8v6M16 11h6'), stroke..strokeWidth = 2.2);
        } else {
          canvas.drawPath(_cached('M5 8a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0M2 20a6.5 6.5 0 0 1 13 0M19 8v6M16 11h6'), stroke);
        }
      case 2: // Chats: the same bubble with the v, outlined or filled (v cut out)
        if (active) {
          canvas.drawPath(_cached(VIcons.chat), fill);
          canvas.drawPath(
            _cached(VIcons.chatV),
            Paint()
              ..color = cutout
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
        } else {
          canvas.drawPath(_cached(VIcons.chat), stroke);
          canvas.drawPath(_cached(VIcons.chatV), stroke);
        }
      case 4: // Suggestions: compass (needle cut out when active)
        if (active) {
          canvas.drawCircle(const Offset(12, 12), 10, fill);
          canvas.drawPath(
            _cached('M15.5 8.5l-2 5-5 2 2-5z'),
            Paint()
              ..color = cutout
              ..style = PaintingStyle.fill,
          );
        } else {
          canvas.drawPath(_cached('M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M15.5 8.5l-2 5-5 2 2-5z'), stroke);
        }
      case 3: // You
        if (active) {
          canvas.drawCircle(const Offset(12, 8), 4.5, fill);
          canvas.drawPath(_cached('M3.5 21.5a8.5 8.5 0 0 1 17 0z'), fill);
        } else {
          canvas.drawPath(_cached(VIcons.profile), stroke);
        }
    }
  }

  @override
  bool shouldRepaint(_TabPainter old) => old.active != active || old.color != color || old.index != index || old.cutout != cutout;
}

/// Blue scalloped verified tick.
class VerifiedTick extends StatelessWidget {
  const VerifiedTick({super.key, this.size = 20});
  final double size;

  static final _seal = parseSvgPath(
    'M12 1.5l2.6 1.9 3.2-.1 1 3 2.6 1.9-1 3.1 1 3.1-2.6 1.9-1 3-3.2-.1L12 22.5l-2.6-1.9-3.2.1-1-3-2.6-1.9 1-3.1-1-3.1 2.6-1.9 1-3 3.2.1z',
  );
  static final _tick = parseSvgPath('M8 12.2l2.7 2.7L16.2 9.4');

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Verified',
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _TickPainter()),
    ),
  );
}

class _TickPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    canvas.drawPath(VerifiedTick._seal, Paint()..color = const Color(0xFF2E7CF6));
    canvas.drawPath(
      VerifiedTick._tick,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) => false;
}

/// Lightning bolt for Fast-Track.
class BoltIcon extends StatelessWidget {
  const BoltIcon({super.key, this.size = 16, this.color});
  final double size;
  final Color? color;
  static const d = 'M13.5 2 5 13.5h6l-1.5 8.5L18 10.5h-6z';

  @override
  Widget build(BuildContext context) => VIcon(d, size: size, color: color ?? context.fc.gold, fill: true);
}

// ------------------------------------------------------------------ motion

/// Opening animation: the bubble pops, the line writes the v, the wordmark
/// letters rise in and the dot drops. Rests on its final frame with reduced
/// motion. [onDone] fires once the sequence has played.
class VoubySplash extends StatefulWidget {
  const VoubySplash({super.key, this.onDone, this.loop = false});
  final VoidCallback? onDone;
  final bool loop;

  @override
  State<VoubySplash> createState() => _VoubySplashState();
}

class _VoubySplashState extends State<VoubySplash> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone?.call());
    } else {
      _c.forward().whenComplete(() {
        widget.onDone?.call();
        if (widget.loop && mounted) _c.repeat(min: 0.62, max: 1, period: const Duration(milliseconds: 1800), reverse: true);
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _seg(double a, double b, [Curve curve = Curves.linear]) => curve.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Semantics(
      label: 'Vouby is opening',
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final pop = _seg(0, 0.28, Curves.easeOutBack);
          final write = _seg(0.12, 0.62, const Cubic(0.6, 0, 0.3, 1));
          final squish = _c.value > 0.62 && _c.value < 0.74 ? math.sin((_c.value - 0.62) / 0.12 * math.pi) * 0.06 : 0.0;
          final ring = _seg(0.6, 0.95, Curves.easeOut);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 190,
                height: 170,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (ring > 0 && ring < 1)
                      Transform.scale(
                        scale: 0.8 + ring * 0.9,
                        child: Opacity(
                          opacity: (1 - ring) * 0.9,
                          child: Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: c.accent, width: 2),
                            ),
                          ),
                        ),
                      ),
                    Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..scaleByDouble(pop * (1 + squish), pop * (1 - squish * 0.8), 1, 1)
                        ..rotateZ((1 - pop) * -0.35),
                      child: Opacity(
                        opacity: pop.clamp(0, 1),
                        child: VoubyMark(size: 150, progress: write),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              _Letters(t: _c.value),
            ],
          );
        },
      ),
    );
  }
}

class _Letters extends StatelessWidget {
  const _Letters({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    const style = TextStyle(fontFamily: 'Geist', fontSize: 60, height: 1, fontWeight: FontWeight.w800);
    double seg(double a, double b, Curve curve) => curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 5; i++)
            Builder(
              builder: (_) {
                final p = seg(0.42 + i * 0.035, 0.66 + i * 0.035, Curves.easeOutBack);
                return Opacity(
                  opacity: p.clamp(0, 1),
                  child: Transform.translate(
                    offset: Offset(0, (1 - p) * 22),
                    child: Text('vouby'[i], style: style.copyWith(color: c.ink, letterSpacing: -3)),
                  ),
                );
              },
            ),
          Builder(
            builder: (_) {
              final p = seg(0.66, 0.84, Curves.easeOutBack);
              return Opacity(
                opacity: p.clamp(0, 1),
                child: Transform.translate(
                  offset: Offset(0, (1 - p) * -50),
                  child: Text('.', style: style.copyWith(color: c.accent)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Typing indicator: three dots that rise in turn.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.color});
  final Color? color;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.fc.ink;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Builder(
              builder: (_) {
                final phase = ((_c.value - i * 0.125) % 1.0);
                final up = phase < 0.6 ? math.sin(phase / 0.6 * math.pi) : 0.0;
                return Transform.translate(
                  offset: Offset(0, -4 * up),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.45 + 0.55 * up),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
