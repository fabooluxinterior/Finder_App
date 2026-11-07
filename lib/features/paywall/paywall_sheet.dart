import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../providers.dart';

final _priceProvider = FutureProvider<String>((ref) => ref.watch(purchasesProvider).priceLabel());

/// Returns true if the user now has the Fast-Track pass.
Future<bool> showPaywall(BuildContext context, {String? reason}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PaywallSheet(reason: reason),
  );
  return result ?? false;
}

class _PaywallSheet extends ConsumerStatefulWidget {
  const _PaywallSheet({this.reason});
  final String? reason;

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
        Navigator.pop(context, true);
        showSnack(context, 'Fast-Track pass active. Enjoy! ⚡', icon: Icons.bolt);
      } else if (restore) {
        showSnack(context, 'No active pass found on this Google account.');
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = ref.watch(_priceProvider).value ?? '₹79';
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(22, 12, 22, 16 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(gradient: AppColors.vipGradient, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fast-Track Pass', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    Text('Monthly · cancel anytime in Google Play', style: TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          if (widget.reason != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(12)),
              child: Text(widget.reason!, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
          const SizedBox(height: 18),
          const _Perk(icon: Icons.all_inclusive, title: 'Unlimited swipes',
              subtitle: 'No more ${AppConfig.freeDailySwipes}-a-day cap on follow requests'),
          const _Perk(icon: Icons.star_rounded, title: 'Direct DM Invite',
              subtitle: 'Attach a 100-character icebreaker to your request'),
          const _Perk(icon: Icons.visibility_rounded, title: 'Who Requested You',
              subtitle: 'See every pending request unblurred and accept instantly'),
          const _Perk(icon: Icons.location_city_rounded, title: 'Kerala City Boost',
              subtitle: 'Top of local decks in Kochi, Kozhikode, Trivandrum & more'),
          const SizedBox(height: 18),
          SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.ink),
              onPressed: _busy ? null : _buy,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.account_balance_wallet_rounded, size: 20),
                        const SizedBox(width: 10),
                        Text('Pay $price / month · UPI / GPay'),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppConfig.isDemo
                ? 'Demo mode: no money is charged.'
                : 'Billed through Google Play. UPI, Google Pay and cards supported. Renews monthly.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          TextButton(onPressed: _busy ? null : () => _buy(restore: true), child: const Text('Restore purchase')),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: const Color(0xFFFFF1E6), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: const Color(0xFFFF6A3D), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(subtitle, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
}
