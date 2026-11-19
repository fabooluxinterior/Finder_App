import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../models/access.dart';
import '../../providers.dart';

/// In-app notices: trial reminders, ticket updates and safety notices.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(backendProvider).markNotificationsRead().catchError((_) {});
    });
  }

  IconData _icon(AppNotification n) => switch (n.kind) {
    final k when k.startsWith('trial') => PhosphorIconsFill.lightning,
    final k when k.startsWith('ticket') => PhosphorIconsFill.lifebuoy,
    final k when k.startsWith('moderation') => PhosphorIconsFill.shieldWarning,
    _ => PhosphorIconsFill.bell,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final list = ref.watch(notificationsProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
          ? Center(
              child: Text('Nothing new.', style: TextStyle(color: c.muted)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final n = list[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: n.readAt == null ? c.accent.withValues(alpha: 0.5) : c.hair),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_icon(n), size: 20, color: c.gold),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.title,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
                            ),
                            const SizedBox(height: 4),
                            Text(n.body, style: TextStyle(fontSize: 14, height: 1.35, color: c.ink2)),
                            const SizedBox(height: 6),
                            Text(
                              MaterialLocalizations.of(context).formatMediumDate(n.createdAt),
                              style: TextStyle(fontSize: 12, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
