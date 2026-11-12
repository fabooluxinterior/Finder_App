import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';

import '../../core/brand.dart';
import '../../core/errors.dart';
import '../../core/feedback.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/follow_request.dart';
import '../../models/profile.dart';
import '../../providers.dart';
import '../match/match_screen.dart';
import '../paywall/paywall_sheet.dart';
import '../profile/profile_detail_screen.dart';
import 'profile_card.dart';
import '../profile_builder/icebreaker_sheet.dart';

class DeckScreen extends ConsumerStatefulWidget {
  const DeckScreen({super.key});

  @override
  ConsumerState<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends ConsumerState<DeckScreen> {
  final _controller = CardSwiperController();
  List<PublicProfile>? _cards;
  int _top = 0;
  bool _exhausted = false;

  /// Profiles that already got a request (via a prompt reply): the card
  /// leaves the deck without sending a second request.
  final _alreadyRequested = <String>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    ref.invalidate(feedProvider);
    final fresh = await ref.read(feedProvider.future);
    if (!mounted) return;
    setState(() {
      _cards = fresh;
      _top = 0;
      _exhausted = fresh.isEmpty;
    });
    _prefetch(0);
  }

  /// Decode the next few photos ahead of time so cards never appear blank.
  void _prefetch(int from) {
    final cards = _cards;
    if (cards == null) return;
    for (final p in cards.skip(from).take(3)) {
      // Same providers (and sizes) ProfilePhoto uses, so the cache hits.
      for (final provider in [
        ProfilePhoto.provider(p.primaryPhoto, ProfilePhoto.screenDecodeWidth(context)),
        ProfilePhoto.provider(p.primaryPhoto, 40),
      ]) {
        if (provider != null) precacheImage(provider, context).catchError((_) {});
      }
    }
  }

  bool _onSwipe(int previous, int? current, CardSwiperDirection direction) {
    final profile = _cards![previous];
    final follow = direction == CardSwiperDirection.right;
    // Sound + haptic on the commit frame, together with the card leaving.
    follow ? Fx.instance.request() : Fx.instance.pass();
    _top = current ?? _cards!.length;
    if (current == null) setState(() => _exhausted = true);
    _prefetch(_top + 1);
    if (!_alreadyRequested.remove(profile.id)) _commit(profile, follow: follow);
    return true;
  }

  Future<void> _commit(PublicProfile p, {required bool follow}) async {
    try {
      final outcome = await ref.read(backendProvider).swipe(p.id, follow: follow);
      if (!mounted) return;
      if (outcome == SwipeOutcome.requested) {
        showSnack(context, 'Request sent to ${p.firstName}', icon: PhosphorIconsFill.paperPlaneTilt);
        return;
      }
      if (outcome != SwipeOutcome.matched) return;
      ref.invalidate(connectionsProvider);
      ref.invalidate(incomingRequestsProvider);
      final me = await ref.read(myProfileProvider.future);
      if (!mounted) return;
      await showMatch(context, me: me, them: p);
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
    }
  }

  Future<void> _reply(PublicProfile p, ProfilePrompt prompt) async {
    final outcome = await showIcebreakerSheet(context, p, prompt);
    if (outcome == null || !mounted) return;
    _alreadyRequested.add(p.id);
    _controller.swipe(CardSwiperDirection.right);
    if (outcome == SwipeOutcome.matched) {
      ref.invalidate(connectionsProvider);
      final me = await ref.read(myProfileProvider.future);
      if (mounted) await showMatch(context, me: me, them: p);
    } else {
      showSnack(context, 'Reply sent with your request to ${p.firstName}', icon: PhosphorIconsFill.paperPlaneTilt);
    }
  }

  void _openProfile(PublicProfile p) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: Motion.of(context, Motion.sheet),
        reverseTransitionDuration: Motion.of(context, Motion.medium),
        pageBuilder: (_, _, _) => ProfileDetailScreen(
          profile: p,
          onReplied: () {
            _alreadyRequested.add(p.id);
            _controller.swipe(CardSwiperDirection.right);
          },
          onPass: () => _controller.swipe(CardSwiperDirection.left),
          onRequest: () => _controller.swipe(CardSwiperDirection.right),
        ),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Motion.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final feed = ref.watch(feedProvider);
    final premium = isPremium(ref);
    // extendBody: the shell already adds the tab bar to the bottom padding.
    final bottomBar = MediaQuery.paddingOf(context).bottom;

    if (_cards == null && feed.hasValue) {
      _cards = feed.value;
      _exhausted = _cards!.isEmpty;
      WidgetsBinding.instance.addPostFrameCallback((_) => _prefetch(0));
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Row(
                children: [
                  const VoubyWordmark(size: 28),
                  const Spacer(),
                  if (premium)
                    const FastTrackBadge(large: true)
                  else
                    Pressable(
                      onTap: () => showPaywall(context),
                      semanticLabel: 'Fast-Track',
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(color: c.goldSoft, borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BoltIcon(size: 16, color: c.gold),
                            const SizedBox(width: 8),
                            Text(
                              'Fast-Track',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.gold),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _cards == null
                  ? (feed.hasError
                        ? _Empty(
                            icon: PhosphorIconsRegular.wifiSlash,
                            title: 'Couldn’t load profiles',
                            body: 'Check your connection and try again.',
                            action: 'Try again',
                            onAction: _reload,
                          )
                        : const SizedBox.shrink())
                  : _exhausted
                  ? _Empty(
                      icon: PhosphorIconsRegular.sparkle,
                      title: 'You’re all caught up',
                      body: 'New people join every day. Profiles you passed come back after 7 days.',
                      action: 'Refresh',
                      onAction: _reload,
                    )
                  : CardSwiper(
                      key: ValueKey(_cards),
                      controller: _controller,
                      cardsCount: _cards!.length,
                      numberOfCardsDisplayed: _cards!.length >= 2 ? 2 : 1,
                      isLoop: false,
                      initialIndex: _top.clamp(0, _cards!.length - 1),
                      duration: Motion.of(context, const Duration(milliseconds: 220)),
                      threshold: 35,
                      maxAngle: 12,
                      scale: 0.95,
                      backCardOffset: const Offset(0, 12),
                      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomBar + 6),
                      allowedSwipeDirection: const AllowedSwipeDirection.symmetric(horizontal: true),
                      onSwipe: _onSwipe,
                      cardBuilder: (context, index, dx, dy) {
                        final p = _cards![index];
                        return ProfileCard(
                          profile: p,
                          dragX: index == _top ? dx : 0,
                          interactive: index == _top,
                          onTap: () => _openProfile(p),
                          onPass: () => _controller.swipe(CardSwiperDirection.left),
                          onRequest: () => _controller.swipe(CardSwiperDirection.right),
                          onReply: (prompt) => _reply(p, prompt),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body, required this.action, required this.onAction});
  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: c.muted),
            const SizedBox(height: 14),
            Text(title, style: t.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: c.muted),
            ),
            const SizedBox(height: 20),
            PillButton(label: action, dark: false, expand: false, height: 46, onTap: onAction),
          ],
        ),
      ),
    );
  }
}
