import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';

/// Keeps requests and chats current even when the live connection missed a
/// change (phone asleep, network dropped). Realtime normally pushes changes;
/// this re-fetches:
///  * when the Requests or Chats tab is opened,
///  * when the app comes back to the foreground,
///  * every [interval] while one of those tabs is open, and every fourth
///    interval otherwise (keeps the tab badges honest, one cheap call each).
/// Renders nothing.
class SocialRefresher extends ConsumerStatefulWidget {
  const SocialRefresher({super.key, required this.tab, this.interval = const Duration(seconds: 15)});

  /// The visible tab (0 Discover, 1 Suggestions, 2 Requests, 3 Chats, 4 You).
  final int tab;
  final Duration interval;

  static bool watches(int tab) => tab == 2 || tab == 3;

  @override
  ConsumerState<SocialRefresher> createState() => _SocialRefresherState();
}

class _SocialRefresherState extends ConsumerState<SocialRefresher> with WidgetsBindingObserver {
  Timer? _timer;
  int _ticks = 0;

  void _refresh() {
    ref.invalidate(incomingRequestsProvider);
    ref.invalidate(connectionsProvider);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.interval, (_) {
      _ticks++;
      if (SocialRefresher.watches(widget.tab) || _ticks % 4 == 0) _refresh();
    });
  }

  @override
  void didUpdateWidget(SocialRefresher old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab && SocialRefresher.watches(widget.tab)) {
      // Providers can't be invalidated while the tree is building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
