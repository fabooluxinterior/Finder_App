import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';

import '../../core/config.dart';
import '../../core/feedback.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../providers.dart';
import '../onboarding/profile_setup_screen.dart';
import '../paywall/paywall_sheet.dart';
import '../security/security_center_screen.dart';
import '../legal/policy_screen.dart';
import '../verification/verification_screen.dart';
import 'profile_detail_screen.dart';

class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  @override
  ConsumerState<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final me = ref.watch(myProfileProvider).value;
    final premium = isPremium(ref);
    if (me == null) return const Scaffold(body: SizedBox.shrink());
    final bottomBar = 84 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 8, 20, bottomBar + 20),
          children: [
            Text('You', style: t.headlineMedium),
            const SizedBox(height: 20),
            Row(
              children: [
                Avatar(url: me.primaryPhoto, name: me.fullName, size: 80),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${me.firstName}, ${me.age}', style: t.titleLarge),
                      const SizedBox(height: 2),
                      Text(me.city, style: t.bodyMedium?.copyWith(color: c.muted)),
                      if (premium) ...[const SizedBox(height: 8), const FastTrackBadge()],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Edit profile',
                    icon: PhosphorIconsRegular.pencilSimple,
                    dark: false,
                    height: 48,
                    onTap: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSetupScreen(isOnboarding: false))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PillButton(
                    label: 'Preview',
                    icon: PhosphorIconsRegular.eye,
                    dark: false,
                    height: 48,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: me))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (!premium)
              Pressable(
                scale: 0.98,
                onTap: () => showPaywall(context),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(24)),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: c.gold.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                        child: Icon(PhosphorIconsFill.lightning, color: c.gold),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Fast-Track · ₹79/month', style: t.titleMedium?.copyWith(color: c.paper)),
                            const SizedBox(height: 2),
                            Text(
                              'See who requested you and start chatting.',
                              style: t.bodySmall?.copyWith(color: c.paper.withValues(alpha: 0.7)),
                            ),
                          ],
                        ),
                      ),
                      Icon(PhosphorIconsBold.caretRight, color: c.paper, size: 18),
                    ],
                  ),
                ),
              )
            else
              _Card(
                children: [
                  _Row(
                    icon: PhosphorIconsFill.lightning,
                    iconColor: c.gold,
                    title: 'Fast-Track is active',
                    subtitle: 'Manage or cancel in Google Play › Subscriptions',
                  ),
                ],
              ),
            const SizedBox(height: 12),
            _Card(
              children: [
                _Row(
                  icon: PhosphorIconsFill.sealCheck,
                  iconColor: me.isVerified ? const Color(0xFF2E7CF6) : null,
                  title: me.isVerified ? 'You’re verified' : 'Get verified',
                  subtitle: me.isVerified ? 'Your profile shows the Verified badge' : 'A quick selfie earns the blue badge',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const VerificationScreen()),
                  ).then((_) => ref.invalidate(myProfileProvider)),
                ),
              ],
            ),
            const SectionLabel('Settings', padding: EdgeInsets.fromLTRB(4, 24, 4, 8)),
            _Card(
              children: [
                _Row(
                  icon: PhosphorIconsRegular.speakerHigh,
                  title: 'Sounds',
                  subtitle: 'Follows your phone’s silent mode',
                  trailing: Switch(
                    value: Fx.instance.soundsEnabled,
                    onChanged: (v) async {
                      await Fx.instance.setSoundsEnabled(v);
                      setState(() {});
                      if (v) Fx.instance.request();
                    },
                  ),
                ),
                _Row(
                  icon: PhosphorIconsRegular.shieldCheck,
                  title: 'Privacy & security',
                  subtitle: 'Two-step verification, devices, sessions',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityCenterScreen())),
                ),
              ],
            ),
            const SectionLabel('Legal', padding: EdgeInsets.fromLTRB(4, 24, 4, 8)),
            _Card(
              children: [
                for (final p in Policy.values)
                  _Row(icon: PhosphorIconsRegular.fileText, title: p.title, onTap: () => openPolicy(context, p)),
              ],
            ),
            if (AppConfig.isDemo) ...[
              const SizedBox(height: 12),
              _Card(
                children: [
                  _Row(
                    icon: PhosphorIconsRegular.flask,
                    title: 'Demo mode',
                    subtitle: 'Sample data on this phone only. No payments are taken.',
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Center(
              child: TextButton.icon(
                onPressed: () => ref.read(backendProvider).signOut(),
                icon: Icon(PhosphorIconsRegular.signOut, color: c.ink2, size: 18),
                label: Text('Sign out', style: t.labelLarge?.copyWith(color: c.ink2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.hair),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: Divider(color: c.hair),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, this.trailing, this.onTap, this.iconColor});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Row(
        children: [
          Icon(icon, size: 22, color: iconColor ?? c.ink2),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleMedium),
                if (subtitle != null) Text(subtitle!, style: t.bodySmall?.copyWith(color: c.muted)),
              ],
            ),
          ),
          if (trailing != null) trailing! else if (onTap != null) Icon(PhosphorIconsBold.caretRight, size: 16, color: c.muted),
        ],
      ),
    );
    return onTap == null ? row : Pressable(scale: 0.99, onTap: onTap, child: row);
  }
}
