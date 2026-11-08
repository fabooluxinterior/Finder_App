import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';

import '../../core/errors.dart';
import '../../core/feedback.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/follow_request.dart';
import '../../providers.dart';
import '../match/match_screen.dart';
import '../paywall/paywall_sheet.dart';
import '../profile/profile_detail_screen.dart';

/// Received follow requests. Without Fast-Track the server returns only a
/// count (RLS hides who sent them), so the teaser shows nothing identifying.
class RequestsScreen extends ConsumerWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final premium = isPremium(ref);
    final incoming = ref.watch(incomingRequestsProvider);
    final count = incoming.value?.count ?? 0;
    final bottomBar = 84 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.ink,
          onRefresh: () => ref.refresh(incomingRequestsProvider.future),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Requests', style: t.headlineMedium),
                      const SizedBox(height: 4),
                      Text(
                        count == 0
                            ? 'No one is waiting right now'
                            : '$count ${count == 1 ? 'person wants' : 'people want'} to follow you',
                        style: t.bodyMedium?.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
              ),
              if (incoming.isLoading && !incoming.hasValue)
                const SliverToBoxAdapter(child: SizedBox(height: 200))
              else if (count == 0)
                SliverFillRemaining(hasScrollBody: false, child: _EmptyState(bottom: bottomBar))
              else if (!premium)
                SliverToBoxAdapter(
                  child: _LockedTeaser(count: count, bottom: bottomBar),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, bottomBar + 16),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.66,
                    ),
                    itemCount: incoming.value!.requests.length,
                    itemBuilder: (_, i) => _RequestTile(request: incoming.value!.requests[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.bottom});
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(32, 0, 32, bottom),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(PhosphorIconsRegular.heart, size: 44, color: c.muted),
          const SizedBox(height: 12),
          Text('No requests yet', style: t.titleLarge),
          const SizedBox(height: 6),
          Text(
            'When someone requests to follow you, they’ll appear here.',
            textAlign: TextAlign.center,
            style: t.bodyMedium?.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _LockedTeaser extends StatelessWidget {
  const _LockedTeaser({required this.count, required this.bottom});
  final int count;
  final double bottom;

  static const _palettes = [
    [Color(0xFFFFC9B8), Color(0xFFB48CFF)],
    [Color(0xFFFFD99A), Color(0xFFFF8FA3)],
    [Color(0xFFA9DFFF), Color(0xFF9C8CFF)],
    [Color(0xFFC6F2D2), Color(0xFF6CC3FF)],
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final tiles = count.clamp(1, 4);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
            children: [
              for (var i = 0; i < tiles; i++)
                RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _palettes[i % _palettes.length],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Align(
                              alignment: Alignment(0, 0.5),
                              child: Icon(PhosphorIconsFill.user, size: 140, color: Colors.white54),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 14,
                          bottom: 14,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 70,
                                height: 12,
                                decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(9)),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: 46,
                                height: 9,
                                decoration: BoxDecoration(color: Colors.white54, borderRadius: BorderRadius.circular(9)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: c.hair),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 30, offset: const Offset(0, 12))],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: c.goldSoft, borderRadius: BorderRadius.circular(14)),
                      child: Icon(PhosphorIconsFill.eye, color: c.gold, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('See who requested you', style: t.titleMedium),
                          const SizedBox(height: 2),
                          Text('Accept them and start chatting with Fast-Track.', style: t.bodySmall?.copyWith(color: c.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                PillButton(
                  label: 'Unlock with Fast-Track',
                  height: 50,
                  onTap: () => showPaywall(context, reason: PaywallReason.requests),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestTile extends ConsumerStatefulWidget {
  const _RequestTile({required this.request});
  final FollowRequest request;

  @override
  ConsumerState<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<_RequestTile> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    accept ? Fx.instance.request() : Fx.instance.pass();
    try {
      await ref.read(backendProvider).respondToRequest(widget.request.id, accept: accept);
      ref.invalidate(incomingRequestsProvider);
      ref.invalidate(connectionsProvider);
      ref.invalidate(feedProvider);
      if (accept && mounted) {
        final me = await ref.read(myProfileProvider.future);
        if (mounted) await showMatch(context, me: me, them: widget.request.sender);
      }
    } on AppException catch (e) {
      if (!mounted) return;
      if (e.code == AppErrorCode.subscriptionRequired) {
        showPaywall(context, reason: PaywallReason.requests);
      } else {
        showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final p = widget.request.sender;
    return Pressable(
      scale: 0.98,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: p))),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: c.hair),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ProfilePhoto(url: p.primaryPhoto, name: p.fullName),
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(widthFactor: 1, heightFactor: 0.5, child: FrostedFade(color: c.surface, blur: false)),
              ),
              Positioned(
                left: 12,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${p.firstName}, ${p.age}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (p.isVerified) const VerifiedBadge(size: 15),
                      ],
                    ),
                    Text(p.city, style: t.bodySmall?.copyWith(color: c.muted)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        RoundButton(
                          icon: PhosphorIconsBold.x,
                          size: 38,
                          iconSize: 16,
                          onTap: _busy ? null : () => _respond(false),
                          semanticLabel: 'Decline',
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: PillButton(
                            label: 'Accept',
                            icon: PhosphorIconsBold.check,
                            height: 38,
                            busy: _busy,
                            onTap: () => _respond(true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
