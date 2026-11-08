import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/phosphor.dart';

import '../../core/feedback.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/follow_request.dart';
import '../../providers.dart';
import '../chats/chats_screen.dart';
import '../deck/deck_screen.dart';
import '../match/match_screen.dart';
import '../profile/my_profile_screen.dart';
import '../requests/requests_screen.dart';

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
      for (final c in now.where((c) => !known.contains(c.profile.id) && !MatchScreen.celebrated.contains(c.profile.id))) {
        showSnack(context, 'You and ${c.profile.firstName} are connected', icon: PhosphorIconsFill.heart);
      }
      final unreadBefore = before.fold<int>(0, (s, c) => s + c.unread);
      final unreadNow = now.fold<int>(0, (s, c) => s + c.unread);
      if (unreadNow > unreadBefore) Fx.instance.received();
    });

    final pending = ref.watch(incomingRequestsProvider).value?.count ?? 0;
    final unread = ref.watch(connectionsProvider).value?.fold<int>(0, (s, c) => s + c.unread) ?? 0;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _tab,
        children: const [DeckScreen(), RequestsScreen(), ChatsScreen(), MyProfileScreen()],
      ),
      bottomNavigationBar: _TabBar(
        index: _tab,
        badges: [0, pending, unread, 0],
        // Tab switches happen dozens of times a day: no animation.
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.badges, required this.onTap});
  final int index;
  final List<int> badges;
  final ValueChanged<int> onTap;

  static const _items = [
    ('Discover', PhosphorIconsRegular.cards, PhosphorIconsFill.cards),
    ('Requests', PhosphorIconsRegular.heart, PhosphorIconsFill.heart),
    ('Chats', PhosphorIconsRegular.chatCircle, PhosphorIconsFill.chatCircle),
    ('You', PhosphorIconsRegular.user, PhosphorIconsFill.user),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottom > 0 ? bottom : 10),
          decoration: BoxDecoration(
            color: c.paper.withValues(alpha: 0.84),
            border: Border(top: BorderSide(color: c.hair)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _items.length; i++)
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
                      label: _items[i].$1,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Badge(
                          isLabelVisible: badges[i] > 0,
                          label: Text('${badges[i]}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                          backgroundColor: c.accent,
                          child: Icon(i == index ? _items[i].$3 : _items[i].$2, size: 26, color: i == index ? c.ink : c.muted),
                        ),
                        const SizedBox(height: 3),
                        Text(_items[i].$1,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: i == index ? c.ink : c.muted,
                            )),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
