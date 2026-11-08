import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/profile.dart';
import '../../providers.dart';
import '../deck/profile_card.dart';
import '../safety/safety_actions.dart';

/// Full profile: photos and interests are visible to every signed-in user
/// (not blocked). Contact details are never part of a profile.
class ProfileDetailScreen extends ConsumerWidget {
  const ProfileDetailScreen({super.key, required this.profile, this.onPass, this.onRequest});
  final PublicProfile profile;

  /// Provided when opened from the Discover deck.
  final VoidCallback? onPass;
  final VoidCallback? onRequest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final priv = ref.watch(privateProfileProvider(profile.id));
    final isMe = profile.id == ref.watch(backendProvider).currentUserId;
    final connected = ref.watch(connectionsProvider).value?.any((x) => x.profile.id == profile.id) ?? false;
    final height = MediaQuery.sizeOf(context).height;
    final fromDeck = onPass != null && onRequest != null;

    void act(VoidCallback? f) {
      Navigator.pop(context);
      // Let the pop start before the card leaves the deck.
      Future.delayed(const Duration(milliseconds: 120), f);
    }

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: height * 0.62,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: ProfileCard.heroTag(profile.id),
                        child: ProfilePhoto(url: profile.primaryPhoto, name: profile.fullName),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0, 0.18, 0.55, 1],
                            colors: [Colors.black.withValues(alpha: 0.25), Colors.transparent, Colors.transparent, c.paper],
                          ),
                        ),
                      ),
                      // Name sits inside the photo section: a viewport paints earlier
                      // slivers above later ones, so overlapping from below is hidden.
                      Positioned(
                        left: 22,
                        right: 22,
                        bottom: 6,
                        child: Row(
                          children: [
                            Flexible(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: profile.firstName),
                                    TextSpan(
                                      text: ', ${profile.age}',
                                      style: TextStyle(fontWeight: FontWeight.w400, color: c.ink2),
                                    ),
                                  ],
                                ),
                                style: t.displaySmall,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (profile.isVerified) const VerifiedBadge(size: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(22, 4, 22, fromDeck ? 110 : 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          InfoChip(icon: PhosphorIconsFill.mapPin, label: profile.city),
                          if (profile.isPremium)
                            InfoChip(
                              icon: PhosphorIconsFill.lightning,
                              label: 'Fast-Track',
                              color: c.gold,
                              background: c.goldSoft,
                            ),
                          if (connected) InfoChip(icon: PhosphorIconsFill.userCheck, label: 'Connected', color: c.ok),
                        ],
                      ),
                      if (profile.bio.isNotEmpty) ...[const SizedBox(height: 16), Text(profile.bio, style: t.bodyLarge)],
                      const SectionLabel('Photos · Interests', padding: EdgeInsets.fromLTRB(0, 26, 0, 10)),
                      priv.when(
                        loading: () => const SizedBox(height: 120),
                        error: (e, _) => Text('$e'),
                        // Open profiles: everyone signed in sees photos and interests.
                        data: (p) => _Unlocked(data: p),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Floating top controls over the photo.
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                RoundButton(
                  icon: PhosphorIconsBold.caretDown,
                  glass: true,
                  size: 40,
                  iconSize: 18,
                  onTap: () => Navigator.pop(context),
                  semanticLabel: 'Close',
                ),
                const Spacer(),
                if (!isMe)
                  PopupMenuButton<String>(
                    color: c.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    onSelected: (v) async {
                      final done = v == 'report'
                          ? await showReportSheet(context, profile)
                          : await confirmBlock(context, ref, profile);
                      if (done && context.mounted) Navigator.pop(context);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'report', child: Text('Report')),
                      PopupMenuItem(value: 'block', child: Text('Block')),
                    ],
                    child: const IgnorePointer(
                      child: RoundButton(icon: PhosphorIconsBold.dotsThree, glass: true, size: 40, iconSize: 20, onTap: _noop),
                    ),
                  ),
              ],
            ),
          ),
          if (fromDeck && !connected)
            Positioned(
              left: 20,
              right: 20,
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              child: Row(
                children: [
                  RoundButton(icon: PhosphorIconsBold.x, size: 54, onTap: () => act(onPass), semanticLabel: 'Pass'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PillButton(label: 'Request to follow', icon: PhosphorIconsFill.userPlus, onTap: () => act(onRequest)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

void _noop() {}

class _Unlocked extends StatelessWidget {
  const _Unlocked({required this.data});
  final PrivateProfile data;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.interests.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final i in data.interests)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: c.hair),
                  ),
                  child: Text(i, style: Theme.of(context).textTheme.labelMedium),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (data.gallery.isEmpty)
          Text('No extra photos yet.', style: TextStyle(color: c.muted))
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (final u in data.gallery)
                Pressable(
                  scale: 0.97,
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      clipBehavior: Clip.antiAlias,
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ProfilePhoto(url: u, name: ''),
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ProfilePhoto(url: u, name: ''),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
