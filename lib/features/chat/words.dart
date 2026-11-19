import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/presence.dart';

/// One looping clock for the Words motion: a light sweeping across the letters every
/// 1.8 s and dots that count up every 1.2 s. Stands still when the phone asks to reduce motion.
class _WordsClock extends StatefulWidget {
  const _WordsClock({required this.builder});
  final Widget Function(BuildContext context, double t, bool still) builder;

  @override
  State<_WordsClock> createState() => _WordsClockState();
}

class _WordsClockState extends State<_WordsClock> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (!still && !_started) {
      _c.repeat();
      _started = true;
    } else if (still && _started) {
      _c.stop();
      _started = false;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(animation: _c, builder: (context, _) => widget.builder(context, _c.value, still));
  }
}

/// Quiet words with a light sweeping across them, then dots that count up: "typing…".
class WordsLine extends StatelessWidget {
  const WordsLine({super.key, required this.words, this.size = 12.5, this.dots = true, this.color});
  final String words;
  final double size;
  final bool dots;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final base = color ?? c.muted;
    final shine = c.ink;
    return _WordsClock(
      builder: (context, t, still) {
        final style = TextStyle(fontSize: size, height: 1.3, color: base, fontWeight: FontWeight.w500);
        final text = Text(words, style: style.copyWith(color: still ? c.ink2 : Colors.white));
        final shown = still
            ? text
            : ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (rect) {
                  final p = (t * 2) % 1.0; // 1.8 s of the 3.6 s clock
                  final x = -0.6 + p * 2.2;
                  return LinearGradient(
                    begin: Alignment(x - 0.6, 0),
                    end: Alignment(x + 0.6, 0),
                    colors: [base, shine, base],
                  ).createShader(rect);
                },
                child: text,
              );
        final n = still ? 3 : ((t * 3) % 1.0 * 4).floor(); // 0 to 3 dots every 1.2 s
        return Row(
          mainAxisSize: MainAxisSize.min,
          textBaseline: TextBaseline.alphabetic,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          children: [
            shown,
            if (dots)
              SizedBox(
                width: size * 1.2,
                child: Text('.' * n, style: style, maxLines: 1, softWrap: false),
              ),
          ],
        );
      },
    );
  }
}

/// What the other person is doing, shown under the last message. Appears with a
/// 0.18 s fade and a 5 px rise; empty (and zero height) when they are idle.
class PeerStateLine extends StatelessWidget {
  const PeerStateLine({super.key, required this.state});
  final PeerState state;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedSize(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.bottomLeft,
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: state == PeerState.idle
            ? const SizedBox(width: double.infinity, key: ValueKey('idle'))
            : Semantics(
                key: ValueKey(state),
                liveRegion: true,
                label: state.header,
                excludeSemantics: true,
                child: Container(
                  width: double.infinity,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 6),
                  child: WordsLine(words: state.words),
                ),
              ),
      ),
    );
  }
}
