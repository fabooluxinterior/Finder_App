import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/phosphor.dart';
import '../auth/add_email_screen.dart';
import '../update/app_update.dart';

import '../../core/brand.dart';
import '../../core/config.dart';
import '../../core/feedback.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/security.dart';
import '../../providers.dart';
import 'profile_editor_screen.dart';
import '../suggestions/discovery_preferences_screen.dart';
import '../../models/profile_catalog.dart' show genderLabel;
import '../profile_builder/completion_meter.dart';
import '../profile_builder/profile_update_banner.dart';
import '../paywall/paywall_sheet.dart';
import '../security/security_center_screen.dart';
import '../legal/policy_screen.dart';
import '../help/help_center_screen.dart';
import '../help/my_tickets_screen.dart';
import '../help/notifications_screen.dart';
import '../subscription/trial_banner.dart';
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
    // Approval happens later (staff review), so refresh the profile when the
    // status flips and show the badge right away.
    ref.listen(verificationStatusProvider, (prev, next) {
      if (next.value == VerificationStatus.approved && prev?.value != VerificationStatus.approved) {
        ref.invalidate(myProfileProvider);
      }
    });
    final status = ref.watch(verificationStatusProvider).value;
    final loaded = ref.watch(myProfileProvider).value;
    final me = loaded == null || loaded.isVerified || status != VerificationStatus.approved
        ? loaded
        : loaded.copyWith(isVerified: true);
    final access = ref.watch(accessStatusProvider).value;
    final inTrial = access?.inTrial ?? false;
    // Paid Fast-Track only (an active trial also unlocks chat, but nothing is
    // billed, so it isn't shown as a subscription).
    final premium = isPremium(ref) && !inTrial;
    final unread = (ref.watch(notificationsProvider).value ?? const []).where((n) => n.readAt == null).length;
    if (me == null) return const Scaffold(body: SizedBox.shrink());
    // extendBody: the shell already adds the tab bar to the bottom padding.
    final bottomBar = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottomBar + 20),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(child: Text('You', style: t.headlineMedium)),
                  RoundButton(
                    icon: Icons.tune,
                    iconWidget: VIcon(VIcons.settings, size: 22, color: c.ink),
                    size: 44,
                    semanticLabel: 'Privacy & security',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityCenterScreen())),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Pressable(
                  scale: 0.98,
                  semanticLabel: 'Preview your profile',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: me))),
                  child: Container(
                    width: 112,
                    height: 144,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: c.surface, width: 3),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(23),
                      child: ProfilePhoto(url: me.primaryPhoto, name: me.fullName, decodeWidth: 300),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: me.firstName),
                                TextSpan(
                                  text: ' ${me.age}',
                                  style: const TextStyle(fontWeight: FontWeight.w400, color: Color(0xFFC9C9CF)),
                                ),
                              ],
                            ),
                            style: TextStyle(
                              fontSize: 28,
                              height: 32 / 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.8,
                              color: c.ink,
                            ),
                          ),
                          if (me.isVerified) const VerifiedBadge(size: 22),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${me.city}, ${me.photoCount} ${me.photoCount == 1 ? 'photo' : 'photos'}',
                        style: TextStyle(fontSize: 15, height: 20 / 15, color: c.ink3),
                      ),
                      const SizedBox(height: 10),
                      Pressable(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileEditorScreen())),
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: c.hair),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Edit profile',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: c.goldSoft, borderRadius: BorderRadius.circular(24)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          premium ? 'Fast-Track is active' : 'Fast-Track',
                          style: const TextStyle(
                            fontSize: 16,
                            height: 22 / 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF3D9A6),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          premium
                              ? 'Manage or cancel in Google Play › Subscriptions.'
                              : inTrial
                              ? 'Included in your free trial. Keep it afterwards for ₹79/month; nothing is charged automatically.'
                              : 'See who requested you, accept, and chat. ₹79/month.',
                          style: const TextStyle(fontSize: 14, height: 20 / 14, color: Color(0xFFCDB68C)),
                        ),
                      ],
                    ),
                  ),
                  if (!premium) ...[
                    const SizedBox(width: 14),
                    Pressable(
                      onTap: () => showPaywall(context),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(999)),
                        alignment: Alignment.center,
                        child: Text(
                          'Get it',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.paper),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            CompletionMeter(
              profile: me,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileEditorScreen())),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(4, 6, 4, 0), child: ProfileUpdateStatusRow()),
            const Padding(padding: EdgeInsets.only(top: 10), child: TrialStatusRow()),
            if (me.bio.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: c.hair),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bio',
                      style: TextStyle(fontSize: 14, height: 20 / 14, color: c.muted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      me.bio,
                      style: TextStyle(fontSize: 17, height: 24 / 17, color: c.ink),
                    ),
                  ],
                ),
              ),
            ],
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
                  icon: PhosphorIconsRegular.slidersHorizontal,
                  title: 'Discovery preferences',
                  subtitle:
                      '${me.prefGenders.isEmpty ? 'Everyone' : me.prefGenders.map((g) => genderLabel(g) ?? g).join(', ')} · '
                      '${me.prefAgeMin}–${me.prefAgeMax >= 80 ? '80+' : me.prefAgeMax}',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoveryPreferencesScreen())),
                ),
                _Row(
                  icon: PhosphorIconsRegular.shieldCheck,
                  title: 'Privacy & security',
                  subtitle: 'Two-step verification, devices, sessions',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityCenterScreen())),
                ),
                _Row(
                  icon: PhosphorIconsRegular.envelopeSimple,
                  title: 'Email for notifications',
                  subtitle: (ref.watch(contactEmailProvider).value ?? '').isEmpty
                      ? 'Add an email'
                      : ref.watch(contactEmailProvider).value!,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddEmailScreen()),
                  ).then((_) => ref.invalidate(contactEmailProvider)),
                ),
                _Row(
                  icon: PhosphorIconsRegular.bell,
                  title: 'Notifications',
                  subtitle: unread == 0 ? 'Trial reminders, ticket updates' : '$unread new',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                  ).then((_) => ref.invalidate(notificationsProvider)),
                ),
                _Row(
                  icon: PhosphorIconsRegular.chatCircle,
                  title: 'Show when I’m typing and online',
                  subtitle: 'Lets people you chat with see typing, recording, photos, and when you are online or last seen',
                  trailing: Switch(
                    value: ref.watch(sharePresenceProvider).value ?? true,
                    onChanged: (v) => ref.read(sharePresenceProvider.notifier).set(v),
                  ),
                ),
                if (ref.watch(pushServiceProvider).available)
                  _Row(
                    icon: PhosphorIconsRegular.bell,
                    title: 'Popup notifications',
                    subtitle: 'Messages from Vouby on this phone',
                    trailing: Switch(
                      value: ref.watch(pushEnabledProvider).value ?? true,
                      onChanged: (v) => ref.read(pushEnabledProvider.notifier).set(v),
                    ),
                  ),
              ],
            ),
            const SectionLabel('Help', padding: EdgeInsets.fromLTRB(4, 24, 4, 8)),
            _Card(
              children: [
                _Row(
                  icon: PhosphorIconsRegular.lifebuoy,
                  title: 'Help & support',
                  subtitle: 'Answers to common questions, contact us',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpCenterScreen())),
                ),
                _Row(
                  icon: PhosphorIconsRegular.ticket,
                  title: 'My tickets',
                  subtitle: 'Your support requests and their status',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyTicketsScreen())),
                ),
                if (ref.watch(updateSupportedProvider))
                  _Row(
                    icon: PhosphorIconsFill.downloadSimple,
                    title: 'App version',
                    subtitle: ref.watch(availableUpdateProvider).value != null
                        ? 'Build ${ref.watch(currentBuildProvider)} · update available, tap to download'
                        : 'Build ${ref.watch(currentBuildProvider)} · tap to check for updates',
                    onTap: () async {
                      final update = ref.read(availableUpdateProvider).value;
                      if (update != null) {
                        await launchUrl(update.url, mode: LaunchMode.externalApplication);
                        return;
                      }
                      ref.invalidate(availableUpdateProvider);
                      final fresh = await ref.read(availableUpdateProvider.future);
                      if (context.mounted) {
                        showSnack(
                          context,
                          fresh != null ? 'A new version is available.' : 'You have the latest version.',
                          icon: PhosphorIconsFill.checkCircle,
                        );
                      }
                    },
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
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.hair),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: Divider(color: c.line),
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
