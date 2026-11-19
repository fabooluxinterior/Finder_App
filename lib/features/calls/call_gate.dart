import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/fun_lines.dart';
import '../../models/profile.dart';
import '../../providers.dart';
import 'demo_call_screen.dart';

/// Calling opens a few days after two people connect (the number of days is set in the dashboard).
class CallGate {
  const CallGate(this.daysLeft);
  final int daysLeft;
  bool get open => daysLeft <= 0;

  static CallGate of(DateTime connectedAt, int unlockDays, {DateTime? now}) {
    final left = connectedAt.add(Duration(days: unlockDays)).difference(now ?? DateTime.now());
    return CallGate(left <= Duration.zero ? 0 : (left.inMinutes / 1440).ceil());
  }
}

/// The phone icon in the chat header: dim with a small lock until calling opens.
class CallButton extends ConsumerWidget {
  const CallButton({super.key, required this.peer, required this.connectedAt});
  final PublicProfile peer;
  final DateTime? connectedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.fc;
    final days = ref.watch(callUnlockDaysProvider).value ?? 4;
    final since = connectedAt;
    final gate = since == null ? const CallGate(1 << 20) : CallGate.of(since, days);
    return IconButton(
      tooltip: gate.open ? 'Call' : 'Calling opens in ${gate.daysLeft} days',
      onPressed: () {
        if (gate.open) {
          Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => DemoCallScreen(peer: peer)));
        } else {
          showCallLockedSheet(context, ref, peer: peer, daysLeft: gate.daysLeft);
        }
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.call_outlined, size: 24, color: gate.open ? c.ink : c.muted),
          if (!gate.open) Positioned(right: -4, bottom: -3, child: Icon(Icons.lock_rounded, size: 12, color: c.muted)),
        ],
      ),
    );
  }
}

/// The quote shown when someone taps the call button too early.
Future<void> showCallLockedSheet(BuildContext context, WidgetRef ref, {required PublicProfile peer, required int daysLeft}) {
  final c = context.fc;
  final fun = (ref.read(funLinesProvider).value ?? FunLines.defaults).pick(
    'call_locked',
    n: daysLeft,
    name: peer.firstName,
    seed: daysLeft,
  );
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.paddingOf(ctx).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.call_outlined, color: c.accent),
              const SizedBox(width: 10),
              Text('Calling opens soon', style: Theme.of(ctx).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: c.paper,
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: c.accent, width: 3)),
            ),
            child: Text(
              '“Understand each other first. The best calls start after a few good chats.”',
              style: TextStyle(color: c.ink, fontSize: 15.5, height: 1.4, fontStyle: FontStyle.italic),
            ),
          ),
          if (fun.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(fun, style: TextStyle(color: c.ink2, fontSize: 15, height: 1.4)),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
            child: Text(
              daysLeft == 1 ? 'Opens in 1 day' : 'Opens in $daysLeft days',
              style: TextStyle(color: c.accent, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          Text('We’ll notify you both when it opens.', style: TextStyle(color: c.muted, fontSize: 13)),
        ],
      ),
    ),
  );
}
