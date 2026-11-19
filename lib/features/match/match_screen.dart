import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand.dart';
import '../../core/feedback.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/profile.dart';
import '../../providers.dart';
import '../chat/chat_screen.dart';
import '../paywall/paywall_sheet.dart';

/// Connection moment — the one place we allow delight (rare, celebratory).
/// [acceptedByThem]: they accepted a request you sent.
Future<void> showMatch(
  BuildContext context, {
  required PublicProfile? me,
  required PublicProfile them,
  bool acceptedByThem = false,
}) {
  MatchScreen.celebrated.add(them.id);
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: Motion.of(context, const Duration(milliseconds: 220)),
      reverseTransitionDuration: Motion.of(context, Motion.fast),
      pageBuilder: (_, _, _) => MatchScreen(me: me, them: them, acceptedByThem: acceptedByThem),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key, required this.me, required this.them, this.acceptedByThem = false});
  final bool acceptedByThem;

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

  Animation<double> _seg(double a, double b, [Curve curve = Motion.easeOut]) => CurvedAnimation(
    parent: _c,
    curve: Interval(a, b, curve: curve),
  );

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
    final left = _seg(0, 0.55, const Cubic(0.2, 0.9, 0.25, 1.15));
    final right = _seg(0.08, 0.63, const Cubic(0.2, 0.9, 0.25, 1.15));
    final dot = _seg(0.6, 0.9, Curves.easeOutBack);
    final text = _seg(0.4, 0.8);
    final buttons = _seg(0.55, 1);
    final name = widget.them.firstName;

    Widget card(PublicProfile? p, Animation<double> a, double side, double deg) => AnimatedBuilder(
      animation: a,
      builder: (context, child) => Opacity(
        opacity: a.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(side * (1 - a.value) * 70, 0),
          child: Transform.rotate(angle: (deg + side * 18 * (1 - a.value)) * math.pi / 180, child: child),
        ),
      ),
      child: Container(
        width: 124,
        height: 164,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: c.paper, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 28, offset: Offset(0, 12))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: ProfilePhoto(url: p?.primaryPhoto, name: p?.fullName ?? 'You', decodeWidth: 300),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 210,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          Transform.translate(offset: const Offset(-52, -8), child: card(widget.me, left, -1, -9)),
                          Transform.translate(offset: const Offset(52, 0), child: card(widget.them, right, 1, 8)),
                          Positioned(
                            bottom: 0,
                            child: ScaleTransition(
                              scale: dot,
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: c.accent,
                                  border: Border.all(color: c.paper, width: 4),
                                ),
                                alignment: Alignment.center,
                                child: VoubyMark(size: 28, color: c.paper),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    FadeTransition(
                      opacity: text,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(text),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.acceptedByThem ? '$name accepted your request' : 'You and $name are connected',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Geist',
                                fontSize: 34,
                                height: 40 / 34,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1,
                                color: c.ink,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'You can chat now. Only the two of you can see this conversation.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontFamily: 'Geist', fontSize: 16, height: 1.5, color: c.ink3),
                            ),
                            if (widget.them.bio.isNotEmpty) ...[
                              const SizedBox(height: 30),
                              Container(
                                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                                decoration: BoxDecoration(
                                  color: c.surface,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: c.hair),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'An easy way in',
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 18 / 13,
                                        fontWeight: FontWeight.w600,
                                        color: c.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Ask about something in their bio: “${widget.them.bio}”',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 16, height: 23 / 16, color: c.ink),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              FadeTransition(
                opacity: buttons,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PillButton(label: 'Say hi to $name', height: 58, onTap: _sayHi),
                    const SizedBox(height: 10),
                    Pressable(
                      onTap: () => Navigator.pop(context),
                      child: SizedBox(
                        height: 48,
                        child: Center(
                          child: Text(
                            'Keep exploring',
                            style: TextStyle(fontFamily: 'Geist', fontSize: 15, color: c.ink2, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
