import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/access.dart';
import '../../providers.dart';
import '../paywall/paywall_sheet.dart';

/// Trial reminders: "ends in 24 hours" and "has ended". Each is shown once
/// (the server records it), never blocks the app, and states that nothing is
/// charged automatically.
class TrialNoticeBanner extends ConsumerStatefulWidget {
  const TrialNoticeBanner({super.key});

  @override
  ConsumerState<TrialNoticeBanner> createState() => _TrialNoticeBannerState();
}

class _TrialNoticeBannerState extends ConsumerState<TrialNoticeBanner> {
  String? _closed;

  Future<void> _close(String notice) async {
    setState(() => _closed = notice);
    await ref.read(backendProvider).markAccessNoticeSeen(notice).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(accessStatusProvider).value;
    final notice = access?.notice;
    final visible = notice != null && notice != _closed;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: !visible
          ? const SizedBox.shrink()
          : _NoticeCard(
              key: ValueKey(notice),
              icon: notice == 'trial_24h' ? PhosphorIconsFill.hourglass : PhosphorIconsFill.lightning,
              title: notice == 'trial_24h' ? 'Your free trial ends in 24 hours' : 'Your free trial has ended',
              body: notice == 'trial_24h'
                  ? 'Keep chatting with Fast-Track for ₹$fastTrackMonthlyRupees/month. Nothing is charged automatically.'
                  : 'Your matches and messages are saved. Get Fast-Track to see requests and chat again.',
              action: 'See Fast-Track',
              onAction: () async {
                await _close(notice);
                if (context.mounted) await showPaywall(context);
              },
              onClose: () => _close(notice),
            ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
    required this.onClose,
  });
  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.gold.withValues(alpha: 0.5)),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 20, color: c.gold),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(body, style: TextStyle(fontSize: 14, height: 1.35, color: c.ink2)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: Icon(PhosphorIconsRegular.x, size: 18, color: c.muted),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 8),
              child: PillButton(label: action, height: 42, expand: false, onTap: onAction),
            ),
          ],
        ),
      ),
    );
  }
}

/// You tab: "Free trial · 5 days left" (tap for the plan details).
class TrialStatusRow extends ConsumerWidget {
  const TrialStatusRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.fc;
    final access = ref.watch(accessStatusProvider).value;
    if (access == null || !access.inTrial) return const SizedBox.shrink();
    final days = access.daysLeft(DateTime.now());
    return Pressable(
      onTap: () => showPaywall(context),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: c.goldSoft, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Icon(PhosphorIconsFill.lightning, size: 18, color: c.gold),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Free trial · $days ${days == 1 ? 'day' : 'days'} left',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
              ),
            ),
            Text('Details', style: TextStyle(fontSize: 13.5, color: c.ink2)),
            Icon(PhosphorIconsRegular.caretRight, size: 16, color: c.muted),
          ],
        ),
      ),
    );
  }
}
