import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';

import '../../core/config.dart';
import '../../core/feedback.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../providers.dart';

final _priceProvider = FutureProvider<String>((ref) => ref.watch(purchasesProvider).priceLabel());

enum PaywallReason { general, requests, messaging }

/// Fast-Track sheet. Springs up, drags down, leaves the screen behind it
/// visible. No free trial: the plain monthly base plan only.
/// Returns true if the subscription is active afterwards.
Future<bool> showPaywall(BuildContext context, {PaywallReason reason = PaywallReason.general}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    sheetAnimationStyle: AnimationStyle(
      duration: Motion.of(context, Motion.sheet),
      reverseDuration: Motion.of(context, Motion.medium),
      curve: Motion.drawer,
    ),
    builder: (_) => _PaywallSheet(reason: reason),
  );
  return result ?? false;
}

class _PaywallSheet extends ConsumerStatefulWidget {
  const _PaywallSheet({required this.reason});
  final PaywallReason reason;

  @override
  ConsumerState<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<_PaywallSheet> {
  bool _busy = false;

  Future<void> _buy({bool restore = false}) async {
    setState(() => _busy = true);
    try {
      final notifier = ref.read(premiumProvider.notifier);
      final ok = restore ? await notifier.restore() : await notifier.purchase();
      if (!mounted) return;
      if (ok) {
        Fx.instance.unlock();
        Navigator.pop(context, true);
        showSnack(context, 'Fast-Track is active', icon: PhosphorIconsFill.lightning);
      } else if (restore) {
        showSnack(context, 'No active subscription found on this Google account.');
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final price = ref.watch(_priceProvider).value ?? '₹79';
    final headline = switch (widget.reason) {
      PaywallReason.requests => 'See who wants to follow you',
      PaywallReason.messaging => 'Start the conversation',
      PaywallReason.general => 'Fast-Track',
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: EdgeInsets.fromLTRB(22, 12, 22, 18 + MediaQuery.paddingOf(context).bottom * 0.5),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(36)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 5,
              decoration: BoxDecoration(color: c.hair, borderRadius: BorderRadius.circular(9)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text(headline, style: t.headlineSmall)),
              const SizedBox(width: 12),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: price, style: t.headlineSmall),
                    TextSpan(
                      text: ' / month',
                      style: t.bodyMedium?.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Billed monthly through Google Play. Cancel anytime.', style: t.bodySmall?.copyWith(color: c.muted)),
          const SizedBox(height: 14),
          const _Perk(
            icon: PhosphorIconsFill.eye,
            title: 'See who requested you',
            subtitle: 'Every pending request, unblurred. Accept instantly.',
          ),
          const _Perk(
            icon: PhosphorIconsFill.chatCircle,
            title: 'Message your connections',
            subtitle: 'End-to-end encrypted text and voice notes.',
          ),
          const _Perk(icon: PhosphorIconsFill.mapPin, title: 'Kerala City Boost', subtitle: 'Top of your city’s Discover deck.'),
          const SizedBox(height: 16),
          PillButton(label: 'Continue with Google Play', busy: _busy, onTap: () => _buy()),
          const SizedBox(height: 10),
          Text(
            AppConfig.isDemo ? 'Demo mode: no payment is taken.' : 'UPI · Google Pay · Cards',
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: c.muted),
          ),
          TextButton(
            onPressed: _busy ? null : () => _buy(restore: true),
            child: Text('Restore purchase', style: t.labelMedium?.copyWith(color: c.ink2)),
          ),
        ],
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.goldSoft, borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: c.gold, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleMedium),
                Text(subtitle, style: t.bodySmall?.copyWith(color: c.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
