import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/follow_request.dart';
import '../../models/profile.dart';
import '../../providers.dart';
import '../chat/chat_screen.dart';
import '../paywall/paywall_sheet.dart';
import '../profile/profile_detail_screen.dart';
import 'direct_note_sheet.dart';
import 'profile_card.dart';

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
  String? _pendingNote;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _premium => ref.read(premiumProvider).value ?? false;
  int get _remaining => ref.read(remainingSwipesProvider).value ?? 1;
  bool get _outOfSwipes => !_premium && _remaining == 0;

  Future<void> _reload() async {
    ref.invalidate(feedProvider);
    ref.invalidate(remainingSwipesProvider);
    final fresh = await ref.read(feedProvider.future);
    if (!mounted) return;
    setState(() {
      _cards = fresh;
      _top = 0;
      _exhausted = fresh.isEmpty;
    });
  }

  bool _onSwipe(int previous, int? current, CardSwiperDirection direction) {
    final profile = _cards![previous];

    if (direction == CardSwiperDirection.top) {
      // Swipe up = Direct DM Invite. Keep the card and open the note flow.
      WidgetsBinding.instance.addPostFrameCallback((_) => _startDirectNote());
      return false;
    }

    if (direction == CardSwiperDirection.right && _outOfSwipes) {
      _pendingNote = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => showPaywall(context,
          reason: 'You’ve sent your 10 free follow requests for today. Go unlimited with Fast-Track.'));
      return false;
    }

    final follow = direction == CardSwiperDirection.right;
    final note = follow ? _pendingNote : null;
    _pendingNote = null;
    _top = current ?? _cards!.length;
    if (current == null) setState(() => _exhausted = true);
    _commitSwipe(profile, follow: follow, note: note);
    return true;
  }

  Future<void> _commitSwipe(PublicProfile p, {required bool follow, String? note}) async {
    try {
      final outcome = await ref.read(backendProvider).swipe(p.id, follow: follow, directNote: note);
      ref.invalidate(remainingSwipesProvider);
      if (!mounted) return;
      switch (outcome) {
        case SwipeOutcome.matched:
          ref.invalidate(connectionsProvider);
          ref.invalidate(incomingRequestsProvider);
          _showMatch(p);
        case SwipeOutcome.requested:
          showSnack(context, note != null ? 'Request + note sent to ${p.firstName} ⭐' : 'Follow request sent to ${p.firstName}',
              icon: Icons.person_add_alt_1);
        case SwipeOutcome.passed:
          break;
      }
    } on AppException catch (e) {
      if (!mounted) return;
      if (e.code == AppErrorCode.swipeLimit || e.code == AppErrorCode.premiumRequired) {
        showPaywall(context, reason: e.message);
      } else {
        showSnack(context, e.message, icon: Icons.error_outline);
      }
    }
  }

  Future<void> _startDirectNote() async {
    if (_cards == null || _exhausted) return;
    if (!_premium) {
      final ok = await showPaywall(context,
          reason: 'Direct DM Invite lets you attach a note to your follow request. It’s a Fast-Track perk.');
      if (!ok || !mounted) return;
    }
    final profile = _cards![_top];
    final note = await showDirectNoteSheet(context, profile);
    if (note == null || !mounted) return;
    _pendingNote = note;
    _controller.swipe(CardSwiperDirection.right);
  }

  void _showMatch(PublicProfile p) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.favorite_rounded, color: AppColors.brand, size: 40),
        title: const Text('It’s mutual!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Avatar(url: p.primaryPhoto, name: p.fullName, size: 88),
            const SizedBox(height: 12),
            Text('You and ${p.firstName} follow each other. Chat and the private photo grid are now unlocked.',
                textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep swiping')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: p)));
            },
            child: const Text('Say hi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final premium = isPremium(ref);
    final remaining = ref.watch(remainingSwipesProvider).value;

    if (_cards == null && feed.hasValue) {
      _cards = feed.value;
      _exhausted = _cards!.isEmpty;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: premium
                ? const FastTrackBadge()
                : ActionChip(
                    avatar: const Icon(Icons.local_fire_department_rounded, size: 18, color: AppColors.brand),
                    label: Text(remaining == null ? '…' : '$remaining left today'),
                    onPressed: () => showPaywall(context),
                  ),
          ),
        ],
      ),
      body: _cards == null
          ? feed.hasError
              ? Center(child: TextButton(onPressed: _reload, child: Text('${feed.error}\nTap to retry')))
              : const Center(child: CircularProgressIndicator())
          : _exhausted
              ? _EmptyDeck(onRefresh: _reload)
              : Column(
                  children: [
                    Expanded(
                      child: CardSwiper(
                        key: ValueKey(_cards),
                        controller: _controller,
                        cardsCount: _cards!.length,
                        numberOfCardsDisplayed: _cards!.length >= 2 ? 2 : 1,
                        isLoop: false,
                        initialIndex: _top.clamp(0, _cards!.length - 1),
                        backCardOffset: const Offset(0, 28),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        allowedSwipeDirection: const AllowedSwipeDirection.only(left: true, right: true, up: true),
                        onSwipe: _onSwipe,
                        cardBuilder: (context, index, dx, dy) => ProfileCard(
                          profile: _cards![index],
                          dragX: dx,
                          dragY: dy,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: _cards![index])),
                          ),
                        ),
                      ),
                    ),
                    _ActionBar(
                      onPass: () => _controller.swipe(CardSwiperDirection.left),
                      onNote: _startDirectNote,
                      onFollow: () => _controller.swipe(CardSwiperDirection.right),
                      premium: premium,
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.onPass, required this.onNote, required this.onFollow, required this.premium});
  final VoidCallback onPass;
  final VoidCallback onNote;
  final VoidCallback onFollow;
  final bool premium;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _RoundButton(icon: Icons.close_rounded, color: AppColors.pass, size: 62, onTap: onPass, tooltip: 'Pass'),
          const SizedBox(width: 22),
          _RoundButton(
            icon: Icons.star_rounded,
            color: AppColors.gold,
            size: 50,
            onTap: onNote,
            tooltip: 'Direct DM Invite',
            locked: !premium,
          ),
          const SizedBox(width: 22),
          _RoundButton(
            icon: Icons.person_add_alt_1_rounded,
            color: AppColors.brand,
            size: 62,
            onTap: onFollow,
            tooltip: 'Request to follow',
            filled: true,
          ),
        ],
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
    required this.tooltip,
    this.filled = false,
    this.locked = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;
  final String tooltip;
  final bool filled;
  final bool locked;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: filled ? color : Colors.white,
              shape: const CircleBorder(),
              elevation: 4,
              shadowColor: Colors.black26,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox.square(
                  dimension: size,
                  child: Icon(icon, color: filled ? Colors.white : color, size: size * 0.48),
                ),
              ),
            ),
            if (locked)
              const Positioned(
                right: -2,
                top: -2,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: AppColors.ink,
                  child: Icon(Icons.lock, size: 11, color: Colors.white),
                ),
              ),
          ],
        ),
      );
}

class _EmptyDeck extends StatelessWidget {
  const _EmptyDeck({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.travel_explore_rounded, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text('You’re all caught up', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('New people join every day. Passed profiles come back after 7 days.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh), label: const Text('Refresh')),
            ],
          ),
        ),
      );
}
