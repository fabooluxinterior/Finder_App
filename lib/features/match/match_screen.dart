import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/phosphor.dart';

import '../../core/feedback.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/profile.dart';
import '../../providers.dart';
import '../chat/chat_screen.dart';
import '../paywall/paywall_sheet.dart';

/// "It's mutual" — the one moment we allow delight (rare, celebratory).
Future<void> showMatch(BuildContext context, {required PublicProfile? me, required PublicProfile them}) {
  MatchScreen.celebrated.add(them.id);
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: Motion.of(context, const Duration(milliseconds: 220)),
    reverseTransitionDuration: Motion.of(context, Motion.fast),
    pageBuilder: (_, _, _) => MatchScreen(me: me, them: them),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ));
}

class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key, required this.me, required this.them});

  /// Connections already announced by this screen (no duplicate snackbar).
  static final celebrated = <String>{};
  final PublicProfile? me;
  final PublicProfile them;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduce) {
        _c.value = 1;
      } else {
        _c.forward();
      }
      // Sound + haptic fire when the cards land (~38% into the timeline).
      Future.delayed(Duration(milliseconds: reduce ? 0 : 340), () {
        if (mounted) Fx.instance.match();
      });
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Animation<double> _seg(double a, double b, [Curve curve = Motion.easeOut]) =>
      CurvedAnimation(parent: _c, curve: Interval(a, b, curve: curve));

  Future<void> _sayHi() async {
    final nav = Navigator.of(context);
    if (!isPremium(ref)) {
      final ok = await showPaywall(context, reason: PaywallReason.messaging);
      if (!ok || !mounted) return;
    }
    nav.pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(peer: widget.them)));
  }

  @override
  Widget build(BuildContext context) {
    final c = FinderColors.dark;
    final cards = _seg(0, 0.45, const Cubic(0.34, 1.3, 0.64, 1));
    final heart = _seg(0.32, 0.62, Curves.easeOutBack);
    final text = _seg(0.45, 0.8);
    final buttons = _seg(0.6, 1);

    Widget photo(PublicProfile? p, double side) => AnimatedBuilder(
          animation: cards,
          builder: (context, child) => Transform.translate(
            offset: Offset(side * (1 - cards.value) * 220, 0),
            child: Transform.rotate(angle: side * -7 * math.pi / 180 * cards.value, child: child),
          ),
          child: Container(
            width: 150,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: c.paper, width: 4),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 50, offset: const Offset(0, 20))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: ProfilePhoto(url: p?.primaryPhoto, name: p?.fullName ?? 'You'),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: c.paper,
      body: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.2),
                radius: 0.8,
                colors: [c.accent.withValues(alpha: 0.32), c.paper.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(children: [
              const Spacer(flex: 3),
              SizedBox(
                height: 240,
                child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                  Transform.translate(offset: const Offset(-62, 0), child: photo(widget.me, -1)),
                  Transform.translate(offset: const Offset(62, 10), child: photo(widget.them, 1)),
                  Positioned(
                    bottom: 0,
                    child: ScaleTransition(
                      scale: heart,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.accent,
                          boxShadow: [BoxShadow(color: c.accent.withValues(alpha: 0.35), blurRadius: 0, spreadRadius: 8)],
                        ),
                        child: const Icon(PhosphorIconsFill.heart, color: Colors.white, size: 26),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 36),
              FadeTransition(
                opacity: text,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.2), end: Offset.zero).animate(text),
                  child: Column(children: [
                    Text('It’s mutual',
                        style: TextStyle(fontFamily: 'Geist', fontSize: 36, fontWeight: FontWeight.w600, letterSpacing: -1.4, color: c.ink)),
                    const SizedBox(height: 8),
                    Text('You and ${widget.them.firstName} follow each other.\nPrivate photos are unlocked.',
                        textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Geist', fontSize: 16, height: 1.4, color: c.ink2)),
                  ]),
                ),
              ),
              const Spacer(flex: 4),
              FadeTransition(
                opacity: buttons,
                child: Column(children: [
                  Pressable(
                    onTap: _sayHi,
                    scale: 0.97,
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(PhosphorIconsFill.chatCircle, size: 20, color: Color(0xFF0B0B0C)),
                        const SizedBox(width: 8),
                        Text('Say hi to ${widget.them.firstName}',
                            style: const TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0B0B0C))),
                      ]),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Keep discovering', style: TextStyle(fontFamily: 'Geist', color: c.ink2, fontWeight: FontWeight.w500)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
