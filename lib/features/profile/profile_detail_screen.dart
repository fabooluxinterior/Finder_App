import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/profile.dart';
import '../../providers.dart';
import '../safety/safety_actions.dart';

/// Instagram-private-style profile: public header always visible; photo grid
/// and interests come from `profile_private`, which RLS returns only to
/// accepted connections.
class ProfileDetailScreen extends ConsumerWidget {
  const ProfileDetailScreen({super.key, required this.profile});
  final PublicProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priv = ref.watch(privateProfileProvider(profile.id));
    final connected = ref.watch(connectionsProvider).value?.any((c) => c.profile.id == profile.id) ?? false;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 420,
            pinned: true,
            foregroundColor: Colors.white,
            backgroundColor: AppColors.ink,
            actions: [
              if (profile.id != ref.watch(backendProvider).currentUserId)
                PopupMenuButton<String>(
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
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(fit: StackFit.expand, children: [
                ProfilePhoto(url: profile.primaryPhoto, name: profile.fullName),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.6, 1],
                      colors: [Colors.transparent, Color(0xCC000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  bottom: 18,
                  right: 20,
                  child: Row(children: [
                    Flexible(
                      child: Text('${profile.fullName}, ${profile.age}',
                          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                    ),
                    if (profile.isPremium) ...[const SizedBox(width: 8), const FastTrackBadge()],
                  ]),
                ),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList.list(children: [
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: 4),
                Text(profile.city, style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (connected)
                  Chip(
                    avatar: const Icon(Icons.how_to_reg_rounded, size: 16),
                    label: const Text('Connected'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.green.shade50,
                  ),
              ]),
              if (profile.bio.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(profile.bio, style: const TextStyle(fontSize: 16, height: 1.4)),
              ],
              const SizedBox(height: 24),
              priv.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('$e'),
                data: (p) => connected || p.gallery.isNotEmpty || p.interests.isNotEmpty
                    ? _Unlocked(data: p)
                    : const _Locked(),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Unlocked extends StatelessWidget {
  const _Unlocked({required this.data});
  final PrivateProfile data;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.interests.isNotEmpty) ...[
            const Text('Interests', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final i in data.interests) Chip(label: Text(i), backgroundColor: const Color(0xFFFFEEF1)),
            ]),
            const SizedBox(height: 24),
          ],
          const Text('Photos', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (data.gallery.isEmpty)
            Text('No extra photos yet.', style: TextStyle(color: Colors.grey.shade600))
          else
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: [
                for (final u in data.gallery)
                  GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        clipBehavior: Clip.antiAlias,
                        child: AspectRatio(aspectRatio: 1, child: ProfilePhoto(url: u, name: '')),
                      ),
                    ),
                    child: ProfilePhoto(url: u, name: ''),
                  ),
              ],
            ),
        ],
      );
}

class _Locked extends StatelessWidget {
  const _Locked();

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: [
                for (var i = 0; i < 6; i++)
                  Container(color: i.isEven ? Colors.grey.shade300 : Colors.grey.shade200),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 16)],
            ),
            child: const Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_rounded, size: 30),
              SizedBox(height: 6),
              Text('This account is private', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              SizedBox(height: 2),
              Text('Photos and interests unlock once they accept your follow.', textAlign: TextAlign.center),
            ]),
          ),
        ],
      );
}
