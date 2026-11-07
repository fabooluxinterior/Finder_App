import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../onboarding/profile_setup_screen.dart';
import '../paywall/paywall_sheet.dart';
import '../../providers.dart';
import 'profile_detail_screen.dart';

class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myProfileProvider).value;
    final premium = isPremium(ref);
    if (me == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('You')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            Avatar(url: me.primaryPhoto, name: me.fullName, size: 84),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${me.fullName}, ${me.age}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                Text(me.city, style: TextStyle(color: Colors.grey.shade700)),
                if (premium) ...[const SizedBox(height: 6), const FastTrackBadge()],
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const ProfileSetupScreen(isOnboarding: false))),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit profile'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: me))),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Preview'),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          if (!premium)
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => showPaywall(context),
              child: Ink(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(gradient: AppColors.vipGradient, borderRadius: BorderRadius.circular(20)),
                child: const Row(children: [
                  Icon(Icons.bolt_rounded, color: Colors.white, size: 34),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Get Fast-Track · ₹79/mo',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                      Text('Unlimited swipes, Direct DM Invites, see who requested you, City Boost',
                          style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                  Icon(Icons.chevron_right, color: Colors.white),
                ]),
              ),
            )
          else
            const ListTile(
              leading: Icon(Icons.verified_rounded, color: AppColors.gold),
              title: Text('Fast-Track pass active'),
              subtitle: Text('Manage or cancel in Google Play › Subscriptions'),
            ),
          const SizedBox(height: 12),
          const ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Privacy protection'),
            subtitle: Text('Screenshots & screen recording are blocked. Contact details are filtered from bios, notes and opening messages.'),
          ),
          if (AppConfig.isDemo)
            const ListTile(
              leading: Icon(Icons.science_outlined),
              title: Text('Demo mode'),
              subtitle: Text('Offline sample data. Build with SUPABASE_URL & SUPABASE_ANON_KEY to go live.'),
            ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => ref.read(backendProvider).signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
