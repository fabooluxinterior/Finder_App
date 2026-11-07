import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../../models/follow_request.dart';
import '../../providers.dart';
import '../deck/deck_screen.dart';
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
    // Announce newly accepted follows (realtime).
    ref.listen<AsyncValue<List<Connection>>>(connectionsProvider, (prev, next) {
      final before = prev?.value?.map((c) => c.profile.id).toSet();
      final now = next.value;
      if (before == null || now == null) return;
      for (final c in now.where((c) => !before.contains(c.profile.id))) {
        showSnack(context, '${c.profile.firstName} accepted — chat unlocked 🔓', icon: Icons.lock_open_rounded);
      }
    });

    final pending = ref.watch(incomingRequestsProvider).value?.count ?? 0;
    final unread = ref.watch(connectionsProvider).value?.fold<int>(0, (s, c) => s + c.unread) ?? 0;
    final badge = pending + unread;

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [DeckScreen(), RequestsScreen(), MyProfileScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.style_outlined), selectedIcon: Icon(Icons.style), label: 'Discover'),
          NavigationDestination(
            icon: Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: const Icon(Icons.favorite_border)),
            selectedIcon: Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: const Icon(Icons.favorite)),
            label: 'Requests',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'You'),
        ],
      ),
    );
  }
}
