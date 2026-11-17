import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../models/support.dart';
import '../../providers.dart';
import '../help/notifications_screen.dart';
import 'raise_ticket_screen.dart';
import 'ticket_detail_screen.dart';

final myTicketsProvider = FutureProvider.autoDispose<List<SupportTicket>>((ref) => ref.watch(backendProvider).myTickets());

Color ticketStatusColor(BuildContext context, TicketStatus s) {
  final c = context.fc;
  return switch (s) {
    TicketStatus.newTicket || TicketStatus.open => c.ink2,
    TicketStatus.assigned || TicketStatus.inProgress => c.gold,
    TicketStatus.waitingForUser || TicketStatus.escalated => c.accent,
    TicketStatus.resolved || TicketStatus.closed => c.ok,
  };
}

/// The user's support requests and their status.
class MyTicketsScreen extends ConsumerWidget {
  const MyTicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.fc;
    final tickets = ref.watch(myTicketsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My support tickets'),
        actions: [
          // Replies and status changes arrive here as notifications.
          IconButton(
            tooltip: 'Notifications',
            icon: Badge(
              isLabelVisible: (ref.watch(notificationsProvider).value ?? const []).any((n) => n.readAt == null),
              child: const Icon(PhosphorIconsRegular.bell),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ).then((_) => ref.invalidate(notificationsProvider)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.accent,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RaiseTicketScreen())),
        icon: const Icon(PhosphorIconsRegular.plus),
        label: const Text('New request'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myTicketsProvider.future),
        child: tickets.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [Text('Couldn’t load your tickets. Pull to try again.', style: TextStyle(color: c.muted))],
          ),
          data: (list) => list.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(32),
                  children: [
                    Icon(PhosphorIconsRegular.lifebuoy, size: 48, color: c.muted),
                    const SizedBox(height: 12),
                    Text(
                      'No support requests yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'If something isn’t working, send us a request and follow it here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.muted),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final t = list[i];
                    final color = ticketStatusColor(context, t.status);
                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TicketDetailScreen(ticket: t)),
                      ).then((_) => ref.invalidate(myTicketsProvider)),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: c.hair),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  t.ticketNo,
                                  style: TextStyle(fontWeight: FontWeight.w700, color: c.ink, letterSpacing: 0.5),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    t.status.label,
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              t.subject,
                              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: c.ink),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: c.ink3),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${t.category.label} · ${MaterialLocalizations.of(context).formatMediumDate(t.createdAt)}',
                              style: TextStyle(fontSize: 12.5, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
