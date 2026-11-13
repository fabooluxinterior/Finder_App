import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';

import '../../core/brand.dart';
import '../../core/errors.dart';
import '../../core/feedback.dart';
import '../../core/illustrations.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/follow_request.dart';
import '../../models/profile_catalog.dart';
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
    // extendBody: the shell already adds the tab bar to the bottom padding.
    final bottomBar = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.accent,
          onRefresh: () => ref.refresh(incomingRequestsProvider.future),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Requests', style: t.headlineMedium),
                      const SizedBox(height: 4),
                      Text(
                        count == 0
                            ? 'No one is waiting right now.'
                            : '$count ${count == 1 ? 'person wants' : 'people want'} to chat. Accept to open the conversation.',
                        style: TextStyle(fontSize: 15, height: 22 / 15, color: c.muted),
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
                  sliver: SliverList.separated(
                    itemCount: incoming.value!.requests.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
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

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final tiles = count.clamp(1, 3);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: Column(
        children: [
          // Placeholder request cards: shape only, nothing identifying.
          for (var i = 0; i < tiles; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: c.hair),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        width: 72,
                        height: 92,
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: IllustratedPerson(index: i + 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (w, h) in [(110.0, 16.0), (150.0, 11.0), (190.0, 11.0)]) ...[
                            Container(
                              width: w,
                              height: h,
                              decoration: BoxDecoration(color: c.hair, borderRadius: BorderRadius.circular(99)),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: c.hair),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: c.goldSoft, borderRadius: BorderRadius.circular(14)),
                      child: Center(child: BoltIcon(size: 22, color: c.gold)),
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
    final p = widget.request.sender;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: c.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            scale: 0.98,
            semanticLabel: 'View ${p.firstName}’s profile',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: p))),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    width: 72,
                    height: 92,
                    child: ProfilePhoto(url: p.primaryPhoto, name: p.fullName, decodeWidth: 200),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: p.firstName),
                                  TextSpan(
                                    text: ' ${p.age}',
                                    style: const TextStyle(fontWeight: FontWeight.w400, color: Color(0xFFC9C9CF)),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 20,
                                height: 26 / 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                                color: c.ink,
                              ),
                            ),
                          ),
                          if (p.isVerified) ...[const SizedBox(width: 6), const VerifiedBadge(size: 17)],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${p.city}, ${_ago(widget.request.createdAt)}',
                        style: TextStyle(fontSize: 14, height: 20 / 14, color: c.muted),
                      ),
                      if (p.bio.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          p.bio,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, height: 21 / 15, color: c.ink2),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (widget.request.introText != null) ...[
            const SizedBox(height: 12),
            IntroQuote(
              question: promptById(widget.request.introPromptId ?? '')?.question,
              text: widget.request.introText!,
              label: '${p.firstName} replied to your prompt',
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Pressable(
                onTap: _busy ? null : () => _respond(false),
                semanticLabel: 'Decline ${p.firstName}',
                child: Container(
                  width: 52,
                  height: 48,
                  decoration: BoxDecoration(
                    color: c.paper,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.hair),
                  ),
                  alignment: Alignment.center,
                  child: VIcon(VIcons.close, size: 20, color: c.ink, stroke: 2.4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillButton(label: 'Accept and chat', height: 48, busy: _busy, onTap: () => _respond(true)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1];
  return '${t.day}/${t.month}';
}

/// A prompt reply that came with a request (shown in Requests and at the top
/// of the chat it opened).
class IntroQuote extends StatelessWidget {
  const IntroQuote({super.key, required this.question, required this.text, required this.label, this.note});
  final String? question;
  final String text;
  final String label;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: c.accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.accent),
          ),
          if (question != null) ...[const SizedBox(height: 4), Text(question!, style: TextStyle(fontSize: 13, color: c.muted))],
          const SizedBox(height: 4),
          Text('“$text”', style: TextStyle(fontSize: 15.5, height: 1.35, color: c.ink)),
          if (note != null) ...[const SizedBox(height: 6), Text(note!, style: TextStyle(fontSize: 12, color: c.muted))],
        ],
      ),
    );
  }
}
