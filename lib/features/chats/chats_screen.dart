import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/phosphor.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/follow_request.dart';
import '../../providers.dart';
import '../paywall/paywall_sheet.dart';
import 'person_sheet.dart';

/// Chats lists only the people you have messaged. A small search icon (top right) stretches into a
/// search bar that finds anyone you follow, including people with no chat yet.
class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _open = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _open = true);
    // Focus once the bar has started to stretch, so the keyboard doesn't fight the animation.
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _focus.requestFocus();
    });
  }

  void _closeSearch() {
    _focus.unfocus();
    _controller.clear();
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final premium = isPremium(ref);
    final connections = ref.watch(connectionsProvider);
    // extendBody: the shell already adds the tab bar to the bottom padding.
    final bottomBar = MediaQuery.paddingOf(context).bottom;
    final query = _controller.text.trim().toLowerCase();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              open: _open,
              controller: _controller,
              focus: _focus,
              onOpen: _openSearch,
              onClose: _closeSearch,
              onChanged: () => setState(() {}),
            ),
            if (!premium && (connections.value?.isNotEmpty ?? false) && !_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Pressable(
                  scale: 0.98,
                  onTap: () => showPaywall(context, reason: PaywallReason.messaging),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    decoration: BoxDecoration(color: c.goldSoft, borderRadius: BorderRadius.circular(18)),
                    child: Row(
                      children: [
                        Icon(PhosphorIconsFill.lockSimple, color: c.gold, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('Messaging is part of Fast-Track', style: t.labelMedium?.copyWith(color: c.ink)),
                        ),
                        Icon(PhosphorIconsBold.caretRight, color: c.gold, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                color: c.accent,
                onRefresh: () => ref.refresh(connectionsProvider.future),
                child: connections.when(
                  skipLoadingOnReload: true,
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => ListView(
                    children: [
                      Center(
                        child: Padding(padding: const EdgeInsets.all(32), child: Text('$e')),
                      ),
                    ],
                  ),
                  data: (all) {
                    if (query.isNotEmpty) return _Results(all: all, query: query, bottom: bottomBar);
                    final chats = all.where((x) => x.hasChat).toList()
                      ..sort((a, b) => (b.lastAt ?? b.connectedAt).compareTo(a.lastAt ?? a.connectedAt));
                    if (chats.isEmpty) return _Empty(bottom: bottomBar, anyone: all.isNotEmpty);
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16, 4, 16, bottomBar + 12),
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: c.hair),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var i = 0; i < chats.length; i++) ...[
                                if (i > 0) Divider(height: 1, indent: 78, color: c.line),
                                _ChatRow(
                                  connection: chats[i],
                                  locked: !premium,
                                  onTap: () => openChatWith(context, ref, chats[i]),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Text(
                            'Only people you have messaged show here. Tap the search icon to find anyone else you follow.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, height: 1.45, color: c.muted),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The title and a 48 px search icon at the right. Opening stretches the bar to the left over the title
/// (0.42 s); the field fades in and an × appears beside the icon.
class _Header extends StatelessWidget {
  const _Header({
    required this.open,
    required this.controller,
    required this.focus,
    required this.onOpen,
    required this.onClose,
    required this.onChanged,
  });
  final bool open;
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final dur = Motion.of(context, const Duration(milliseconds: 420));
    const curve = Curves.easeOutCubic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: SizedBox(
        height: 48,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            alignment: Alignment.centerRight,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: AnimatedSlide(
                  duration: dur,
                  curve: curve,
                  offset: open ? const Offset(-0.05, 0) : Offset.zero,
                  child: AnimatedOpacity(
                    duration: Motion.of(context, const Duration(milliseconds: 220)),
                    opacity: open ? 0 : 1,
                    child: Text('Chats', style: t.headlineMedium),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: dur,
                curve: curve,
                width: open ? box.maxWidth : 48,
                height: 48,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: open ? c.ink3 : c.hair),
                ),
                child: LayoutBuilder(
                  builder: (context, inner) {
                    final fieldWidth = (inner.maxWidth - 92).clamp(0.0, double.infinity);
                    return Stack(
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: fieldWidth,
                          child: AnimatedOpacity(
                            duration: Motion.of(context, const Duration(milliseconds: 220)),
                            opacity: open ? 1 : 0,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 18),
                              child: TextField(
                                controller: controller,
                                focusNode: focus,
                                enabled: open,
                                textInputAction: TextInputAction.search,
                                style: TextStyle(fontSize: 16, color: c.ink),
                                cursorColor: c.accent,
                                decoration: InputDecoration(
                                  hintText: 'Search people you follow',
                                  hintStyle: TextStyle(color: c.muted),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  filled: false,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (_) => onChanged(),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 46,
                          top: 0,
                          bottom: 0,
                          width: 44,
                          child: AnimatedOpacity(
                            duration: Motion.of(context, const Duration(milliseconds: 220)),
                            opacity: open ? 1 : 0,
                            child: IgnorePointer(
                              ignoring: !open,
                              child: IconButton(
                                onPressed: onClose,
                                tooltip: 'Close search',
                                icon: Icon(PhosphorIconsRegular.x, size: 18, color: c.muted),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          width: 46,
                          child: IconButton(
                            onPressed: open ? () => focus.requestFocus() : onOpen,
                            tooltip: 'Search people you follow',
                            icon: Icon(Icons.search_rounded, size: 22, color: c.ink),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.all, required this.query, required this.bottom});
  final List<Connection> all;
  final String query;
  final double bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.fc;
    final r = all
        .where((x) => x.profile.fullName.toLowerCase().contains(query) || x.profile.city.toLowerCase().contains(query))
        .toList();
    if (r.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 56, 32, 0),
            child: Column(
              children: [
                Icon(Icons.search_rounded, size: 34, color: c.muted),
                const SizedBox(height: 10),
                Text(
                  'No one named “$query” in your followers.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 12),
      children: [
        const SectionLabel('People you follow', padding: EdgeInsets.fromLTRB(2, 4, 2, 8)),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.hair),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < r.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 78, color: c.line),
                PersonRow(connection: r[i], onTap: () => showPersonSheet(context, ref, r[i])),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A person with their city and how you are connected ("Mutual", "Follows you", "You follow").
class PersonRow extends StatelessWidget {
  const PersonRow({super.key, required this.connection, required this.onTap, this.tag});
  final Connection connection;
  final VoidCallback onTap;

  /// Small label at the right; the relation ("Mutual", "Follows you", "You follow") when null.
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final p = connection.profile;
    return Pressable(
      scale: 0.99,
      haptic: false,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Row(
          children: [
            Avatar(url: p.primaryPhoto, name: p.fullName, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.firstName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600, color: c.ink),
                        ),
                      ),
                      if (p.isVerified) ...[const SizedBox(width: 5), const VerifiedBadge(size: 16)],
                    ],
                  ),
                  Text(
                    p.city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, height: 20 / 14.5, color: c.muted),
                  ),
                ],
              ),
            ),
            if (tag != '')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: c.hair),
                ),
                child: Text(tag ?? relationLabel(connection), style: TextStyle(fontSize: 12, color: c.muted)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.bottom, required this.anyone});
  final double bottom;
  final bool anyone;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(32, 80, 32, bottom),
          child: Column(
            children: [
              Icon(PhosphorIconsRegular.chatCircle, size: 44, color: c.muted),
              const SizedBox(height: 12),
              Text(anyone ? 'No chats yet' : 'No connections yet', style: t.titleLarge),
              const SizedBox(height: 6),
              Text(
                anyone
                    ? 'Tap the search icon to find someone you follow and say hi.'
                    : 'When you and someone follow each other, your chat appears here.',
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.connection, required this.locked, required this.onTap});
  final Connection connection;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final p = connection.profile;
    final unread = connection.unread > 0;
    final preview = connection.lastMessage ?? 'You’re connected. Say hi.';
    return Pressable(
      scale: 0.99,
      haptic: false,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 76),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(url: p.primaryPhoto, name: p.fullName, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.firstName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600, color: c.ink),
                          ),
                        ),
                        if (p.isVerified) ...[const SizedBox(width: 5), const VerifiedBadge(size: 16)],
                      ],
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: Motion.of(context, const Duration(milliseconds: 160)),
                      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                      layoutBuilder: (current, previous) =>
                          Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                      child: Align(
                        key: ValueKey(locked ? 'locked' : preview),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          locked ? 'Unlock with Fast-Track to read and reply' : preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 21 / 15,
                            color: unread && !locked ? c.ink : c.muted,
                            fontWeight: unread && !locked ? FontWeight.w500 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Time sits at the top end; the unread count (or lock) sits under it.
              SizedBox(
                height: 52,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _when(connection.lastAt ?? connection.connectedAt),
                      style: TextStyle(fontSize: 13, height: 22 / 13, color: unread && !locked ? c.accent : c.muted),
                    ),
                    const Spacer(),
                    if (locked)
                      Icon(PhosphorIconsFill.lockSimple, size: 15, color: c.muted)
                    else if (unread)
                      Semantics(
                        label: '${connection.unread} unread',
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            connection.unread > 99 ? '99+' : '${connection.unread}',
                            style: TextStyle(fontSize: 12.5, height: 1, fontWeight: FontWeight.w700, color: c.paper),
                          ),
                        ),
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

  static String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    if (d.inDays < 7) return DateFormat('EEE').format(t);
    return DateFormat('d MMM').format(t);
  }
}
