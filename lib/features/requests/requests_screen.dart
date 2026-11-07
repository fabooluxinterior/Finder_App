import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/follow_request.dart';
import '../../providers.dart';
import '../chat/chat_screen.dart';
import '../paywall/paywall_sheet.dart';
import '../profile/profile_detail_screen.dart';

class RequestsScreen extends ConsumerWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(incomingRequestsProvider).value?.count ?? 0;
    final unread = ref.watch(connectionsProvider).value?.fold<int>(0, (s, c) => s + c.unread) ?? 0;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Requests'),
          bottom: TabBar(
            tabs: [
              Tab(child: _TabLabel('Pending Requests', pendingCount)),
              Tab(child: _TabLabel('Mutual Connections', unread)),
            ],
          ),
        ),
        body: const TabBarView(children: [_PendingTab(), _MutualTab()]),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.text, this.count);
  final String text;
  final int count;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
        if (count > 0) ...[const SizedBox(width: 6), Badge(label: Text('$count'))],
      ]);
}

// ------------------------------------------------------------------ pending ---

class _PendingTab extends ConsumerWidget {
  const _PendingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = isPremium(ref);
    final incoming = ref.watch(incomingRequestsProvider);

    return incoming.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (data) {
        if (data.count == 0) {
          return const _Empty(
            icon: Icons.inbox_outlined,
            title: 'No pending requests',
            subtitle: 'When someone swipes right on you, it shows up here.',
          );
        }
        if (!premium) return _BlurredTeaser(count: data.count);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(incomingRequestsProvider.future),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: data.requests.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _RequestTile(request: data.requests[i]),
          ),
        );
      },
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
    try {
      await ref.read(backendProvider).respondToRequest(widget.request.id, accept: accept);
      ref.invalidate(incomingRequestsProvider);
      ref.invalidate(connectionsProvider);
      ref.invalidate(feedProvider);
      if (!mounted) return;
      final p = widget.request.sender;
      if (accept) {
        showSnack(context, 'You and ${p.firstName} are connected. Chat unlocked 🔓', icon: Icons.lock_open_rounded);
        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: p)));
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final p = r.sender;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: p))),
              child: Row(children: [
                Avatar(url: p.primaryPhoto, name: p.fullName, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(
                        child: Text('${p.firstName}, ${p.age}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                      ),
                      if (p.isPremium) ...[const SizedBox(width: 6), const FastTrackBadge(compact: true)],
                    ]),
                    Text('${p.city} · ${_ago(r.createdAt)}', style: TextStyle(color: Colors.grey.shade600)),
                  ]),
                ),
              ]),
            ),
            if (r.directNote != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.star_rounded, color: AppColors.gold, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r.directNote!, style: const TextStyle(height: 1.3))),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _respond(false),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _respond(true),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  icon: const Icon(Icons.how_to_reg_rounded),
                  label: const Text('Accept Follow'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _BlurredTeaser extends StatelessWidget {
  const _BlurredTeaser({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.78,
          children: [for (var i = 0; i < count.clamp(1, 6); i++) _BlurTile(seed: i)],
        ),
        const SizedBox(height: 20),
        Text(
          '$count ${count == 1 ? 'person wants' : 'people want'} to follow you',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'See who they are and accept instantly with Fast-Track — or keep swiping: if you request them back, it’s an instant match.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.ink),
          onPressed: () => showPaywall(context, reason: 'Unblur all $count pending requests.'),
          icon: const Icon(Icons.visibility_rounded),
          label: const Text('Unlock Who Requested You · ₹79'),
        ),
      ],
    );
  }
}

class _BlurTile extends StatelessWidget {
  const _BlurTile({required this.seed});
  final int seed;

  static const _palettes = [
    [Color(0xFFFFA8B8), Color(0xFF9B6BFF)],
    [Color(0xFFFFC27A), Color(0xFFFF6A8A)],
    [Color(0xFF7AD3FF), Color(0xFF8B7CFF)],
    [Color(0xFFB0F0C4), Color(0xFF52B7FF)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _palettes[seed % _palettes.length];
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(fit: StackFit.expand, children: [
        // Nothing identifying is ever downloaded for free users; this is an abstract silhouette.
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: const Align(
              alignment: Alignment(0, 0.3),
              child: Icon(Icons.person, size: 150, color: Colors.white70),
            ),
          ),
        ),
        const Center(
          child: CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white,
            child: Icon(Icons.lock_rounded, color: AppColors.ink),
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------- mutual ---

class _MutualTab extends ConsumerWidget {
  const _MutualTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(connectionsProvider);
    return connections.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => list.isEmpty
          ? const _Empty(
              icon: Icons.people_outline,
              title: 'No connections yet',
              subtitle: 'Chat unlocks the moment a follow request is accepted.',
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(connectionsProvider.future),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(indent: 84, height: 1),
                itemBuilder: (_, i) {
                  final c = list[i];
                  final p = c.profile;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Avatar(url: p.primaryPhoto, name: p.fullName, size: 54),
                    title: Text(p.firstName, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      c.lastMessage ?? 'Connected ${_ago(c.connectedAt)} · say hi 👋',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: c.unread > 0 ? FontWeight.w700 : FontWeight.normal,
                        color: c.unread > 0 ? AppColors.ink : Colors.grey.shade600,
                      ),
                    ),
                    trailing: c.unread > 0
                        ? Badge(label: Text('${c.unread}'), backgroundColor: AppColors.brand)
                        : const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: p))),
                  );
                },
              ),
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ]),
        ),
      );
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return DateFormat('d MMM').format(t);
}
