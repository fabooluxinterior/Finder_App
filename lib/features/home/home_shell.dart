import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';

import '../../core/app_lifecycle.dart';
import '../../core/brand.dart';
import '../../core/feedback.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/follow_request.dart';
import '../../providers.dart';
import '../chats/chats_screen.dart';
import '../deck/deck_screen.dart';
import '../match/match_screen.dart';
import '../profile/my_profile_screen.dart';
import '../profile_builder/profile_update_banner.dart';
import '../subscription/trial_banner.dart';
import '../requests/requests_screen.dart';
import '../suggestions/suggestions_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    // New connections and new messages, announced from anywhere in the app.
    ref.listen<AsyncValue<List<Connection>>>(connectionsProvider, (prev, next) {
      final before = prev?.value;
      final now = next.value;
      if (before == null || now == null) return;
      final known = before.map((c) => c.profile.id).toSet();
      final fresh = now.where((c) => !known.contains(c.profile.id) && !MatchScreen.celebrated.contains(c.profile.id)).toList();
      if (fresh.length == 1) {
        // Someone accepted a request you sent.
        ref.read(myProfileProvider.future).then((me) {
          if (context.mounted) showMatch(context, me: me, them: fresh.single.profile, acceptedByThem: true);
        });
      } else {
        for (final c in fresh) {
          showSnack(context, 'You and ${c.profile.firstName} are connected', icon: PhosphorIconsFill.heart);
        }
      }
      final unreadBefore = before.fold<int>(0, (s, c) => s + c.unread);
      final unreadNow = now.fold<int>(0, (s, c) => s + c.unread);
      if (unreadNow > unreadBefore) Fx.instance.received();
    });

    final pending = ref.watch(incomingRequestsProvider).value?.count ?? 0;
    final unread = ref.watch(connectionsProvider).value?.fold<int>(0, (s, c) => s + c.unread) ?? 0;

    // Back: other tab -> Discover; Discover -> app goes to the background
    // (never closes, so you're never asked to sign in again).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tab != 0) {
          setState(() => _tab = 0);
        } else {
          sendAppToBackground();
        }
      },
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            IndexedStack(
              index: _tab,
              children: const [DeckScreen(), SuggestionsScreen(), RequestsScreen(), ChatsScreen(), MyProfileScreen()],
            ),
            // "Your profile needs a small update" (only when a detail is missing).
            Builder(
              builder: (context) => Positioned(
                left: 12,
                right: 12,
                bottom: MediaQuery.paddingOf(context).bottom + 12,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [TrialNoticeBanner(), SizedBox(height: 8), ProfileUpdateBanner()],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _TabBar(
          index: _tab,
          badges: [0, 0, pending, unread, 0],
          // Tab switches happen dozens of times a day: no animation.
          onTap: (i) => setState(() => _tab = i),
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.badges, required this.onTap});
  final int index;
  final List<int> badges;
  final ValueChanged<int> onTap;

  static const _labels = ['Discover', 'Suggestions', 'Requests', 'Chats', 'You'];
  static const _kinds = [TabKind.discover, TabKind.suggestions, TabKind.requests, TabKind.chats, TabKind.you];

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return RepaintBoundary(
      child: Container(
        padding: EdgeInsets.fromLTRB(6, 10, 6, bottom > 0 ? bottom : 14),
        decoration: BoxDecoration(
          color: c.paper,
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < _labels.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (i != index) Fx.instance.tap();
                    onTap(i);
                  },
                  child: Semantics(
                    selected: i == index,
                    button: true,
                    label: badges[i] > 0 ? '${_labels[i]}, ${badges[i]} new' : _labels[i],
                    excludeSemantics: true,
                    child: SizedBox(
                      height: 52,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              TabIcon(kind: _kinds[i], active: i == index, color: i == index ? c.ink : c.muted),
                              if (badges[i] > 0) Positioned(top: -6, right: -14, child: _Badge(count: badges[i])),
                            ],
                          ),
                          const SizedBox(height: 5),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _labels[i],
                              style: TextStyle(
                                fontSize: 13,
                                height: 1,
                                fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                                color: i == index ? c.ink : c.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Orange count badge that springs in when it first appears.
class _Badge extends StatelessWidget {
  const _Badge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return TweenAnimationBuilder<double>(
      key: ValueKey(count),
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, const Duration(milliseconds: 420)),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        constraints: const BoxConstraints(minWidth: 20),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(999)),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: TextStyle(fontSize: 12, height: 1, fontWeight: FontWeight.w700, color: c.paper),
        ),
      ),
    );
  }
}
