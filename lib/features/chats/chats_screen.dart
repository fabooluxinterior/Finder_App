import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/phosphor.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/follow_request.dart';
import '../../providers.dart';
import '../chat/chat_screen.dart';
import '../paywall/paywall_sheet.dart';

class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, Connection c) async {
    if (!isPremium(ref)) {
      final ok = await showPaywall(context, reason: PaywallReason.messaging);
      if (!ok || !context.mounted) return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: c.profile)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final premium = isPremium(ref);
    final connections = ref.watch(connectionsProvider);
    final bottomBar = 84 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.ink,
          onRefresh: () => ref.refresh(connectionsProvider.future),
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text('Chats', style: t.headlineMedium),
              ),
            ),
            if (!premium && (connections.value?.isNotEmpty ?? false))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Pressable(
                    scale: 0.98,
                    onTap: () => showPaywall(context, reason: PaywallReason.messaging),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      decoration: BoxDecoration(color: c.goldSoft, borderRadius: BorderRadius.circular(18)),
                      child: Row(children: [
                        Icon(PhosphorIconsFill.lockSimple, color: c.gold, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Messaging is part of Fast-Track', style: t.labelMedium?.copyWith(color: c.ink))),
                        Icon(PhosphorIconsBold.caretRight, color: c.gold, size: 16),
                      ]),
                    ),
                  ),
                ),
              ),
            ...connections.when(
              loading: () => [const SliverToBoxAdapter(child: SizedBox.shrink())],
              error: (e, _) => [SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('$e')))],
              data: (list) => list.isEmpty
                  ? [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(32, 0, 32, bottomBar),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(PhosphorIconsRegular.chatCircle, size: 44, color: c.muted),
                            const SizedBox(height: 12),
                            Text('No connections yet', style: t.titleLarge),
                            const SizedBox(height: 6),
                            Text('When you and someone follow each other, your chat appears here.',
                                textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: c.muted)),
                          ]),
                        ),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: EdgeInsets.only(bottom: bottomBar + 8),
                        sliver: SliverList.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, _) => Padding(padding: const EdgeInsets.only(left: 86), child: Divider(color: c.hair)),
                          itemBuilder: (_, i) => _ChatRow(connection: list[i], locked: !premium, onTap: () => _open(context, ref, list[i])),
                        ),
                      ),
                    ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.connection, required this.locked, required this.onTap});
  final Connection connection;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final p = connection.profile;
    final unread = connection.unread > 0;
    final preview = connection.lastMessage ?? 'You’re connected. Say hi.';
    return Pressable(
      scale: 0.99,
      haptic: false,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(children: [
          Avatar(url: p.primaryPhoto, name: p.fullName, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(p.firstName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium)),
                const SizedBox(width: 4),
                const VerifiedBadge(size: 15),
                const Spacer(),
                Text(_when(connection.connectedAt), style: t.bodySmall?.copyWith(color: c.muted)),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Expanded(
                  child: Text(
                    locked ? 'Unlock to read and reply' : preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(
                      color: unread && !locked ? c.ink : c.muted,
                      fontWeight: unread && !locked ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (locked)
                  Icon(PhosphorIconsFill.lockSimple, size: 15, color: c.muted)
                else if (unread)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(99)),
                    alignment: Alignment.center,
                    child: Text('${connection.unread}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  static String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    if (d.inDays < 7) return DateFormat('EEE').format(t);
    return DateFormat('d MMM').format(t);
  }
}
