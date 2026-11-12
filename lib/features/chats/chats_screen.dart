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
    // extendBody: the shell already adds the tab bar to the bottom padding.
    final bottomBar = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.accent,
          onRefresh: () => ref.refresh(connectionsProvider.future),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
                        child: Row(
                          children: [
                            Icon(PhosphorIconsFill.lockSimple, color: c.gold, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('Messaging is part of Fast-Track', style: t.labelMedium?.copyWith(color: c.ink)),
                            ),
                            Icon(PhosphorIconsBold.caretRight, color: c.gold, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ...connections.when(
                skipLoadingOnReload: true,
                loading: () => [const SliverToBoxAdapter(child: SizedBox.shrink())],
                error: (e, _) => [SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('$e')))],
                data: (list) => list.isEmpty
                    ? [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(32, 0, 32, bottomBar),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(PhosphorIconsRegular.chatCircle, size: 44, color: c.muted),
                                const SizedBox(height: 12),
                                Text('No connections yet', style: t.titleLarge),
                                const SizedBox(height: 6),
                                Text(
                                  'When you and someone follow each other, your chat appears here.',
                                  textAlign: TextAlign.center,
                                  style: t.bodyMedium?.copyWith(color: c.muted),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ]
                    : [
                        if (list.any((x) => x.lastMessage == null))
                          SliverToBoxAdapter(
                            child: _NewConnections(
                              list: list.where((x) => x.lastMessage == null).toList(),
                              onOpen: (x) => _open(context, ref, x),
                            ),
                          ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(12, 6, 12, bottomBar + 8),
                          sliver: SliverList.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, _) => Divider(color: c.line),
                            itemBuilder: (_, i) =>
                                _ChatRow(connection: list[i], locked: !premium, onTap: () => _open(context, ref, list[i])),
                          ),
                        ),
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// People you're newly connected with and haven't talked to yet.
class _NewConnections extends StatelessWidget {
  const _NewConnections({required this.list, required this.onOpen});
  final List<Connection> list;
  final ValueChanged<Connection> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'New connections',
              style: TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w600, color: c.ink3),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 114,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final p = list[i].profile;
                return Pressable(
                  onTap: () => onOpen(list[i]),
                  semanticLabel: 'Chat with ${p.firstName}',
                  child: Column(
                    children: [
                      Container(
                        width: 70,
                        height: 88,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: c.accent, width: 2),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ProfilePhoto(url: p.primaryPhoto, name: p.fullName, decodeWidth: 200),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        p.firstName,
                        style: TextStyle(fontSize: 14, height: 18 / 14, fontWeight: FontWeight.w600, color: c.ink),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
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
    final p = connection.profile;
    final unread = connection.unread > 0;
    final preview = connection.lastMessage ?? 'You’re connected. Say hi.';
    return Pressable(
      scale: 0.99,
      haptic: false,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 76),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(url: p.primaryPhoto, name: p.fullName, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.firstName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600, color: c.ink),
                          ),
                        ),
                        if (p.isVerified) ...[const SizedBox(width: 5), const VerifiedBadge(size: 15)],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      locked ? 'Unlock with Fast-Track to read and reply' : preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, height: 21 / 15, color: unread && !locked ? c.ink : c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Time sits at the top end; the unread count (or lock) sits under it.
              SizedBox(
                height: 52,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _when(connection.connectedAt),
                      style: TextStyle(fontSize: 13, height: 22 / 13, color: unread && !locked ? c.accent : c.muted),
                    ),
                    const Spacer(),
                    if (locked)
                      Icon(PhosphorIconsFill.lockSimple, size: 15, color: c.muted)
                    else if (unread)
                      Semantics(
                        label: '${connection.unread} unread',
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            connection.unread > 99 ? '99+' : '${connection.unread}',
                            style: TextStyle(fontSize: 12.5, height: 1, fontWeight: FontWeight.w700, color: c.paper),
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

  static String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    if (d.inDays < 7) return DateFormat('EEE').format(t);
    return DateFormat('d MMM').format(t);
  }
}
