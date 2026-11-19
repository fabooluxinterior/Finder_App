import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/follow_request.dart';
import '../../providers.dart';
import '../chat/chat_screen.dart';
import '../paywall/paywall_sheet.dart';
import '../profile/profile_detail_screen.dart';

/// Opens the chat with [c]; chatting needs Fast-Track (or the free trial), so the paywall comes first when it doesn't.
Future<void> openChatWith(BuildContext context, WidgetRef ref, Connection c) async {
  if (!isPremium(ref)) {
    final ok = await showPaywall(context, reason: PaywallReason.messaging);
    if (!ok || !context.mounted) return;
  }
  Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: c.profile)));
}

/// "View profile" or "Send a message" for someone you follow (or who follows you).
Future<void> showPersonSheet(BuildContext context, WidgetRef ref, Connection c) {
  final fc = context.fc;
  final p = c.profile;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: fc.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: fc.ink),
                            ),
                          ),
                          if (p.isVerified) ...[const SizedBox(width: 6), const VerifiedBadge(size: 17)],
                        ],
                      ),
                      Text(p.city, style: TextStyle(fontSize: 14, color: fc.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            PillButton(
              label: 'View profile',
              dark: false,
              onTap: () {
                Navigator.pop(sheet);
                Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: p)));
              },
            ),
            const SizedBox(height: 10),
            PillButton(
              label: c.hasChat ? 'Open chat' : 'Send a message',
              onTap: () {
                Navigator.pop(sheet);
                openChatWith(context, ref, c);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// "Mutual", "Follows you" or "You follow": only ever shown to the person looking at their own lists.
String relationLabel(Connection c) => c.isMutual
    ? 'Mutual'
    : c.followsMe
    ? 'Follows you'
    : 'You follow';
