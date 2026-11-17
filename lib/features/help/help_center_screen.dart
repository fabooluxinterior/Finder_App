import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../models/support.dart';
import '../../providers.dart';
import 'my_tickets_screen.dart';
import 'raise_ticket_screen.dart';
import 'support_chat_screen.dart';

IconData supportIcon(SupportCategory c) => switch (c) {
  SupportCategory.account => PhosphorIconsRegular.user,
  SupportCategory.profile => PhosphorIconsRegular.camera,
  SupportCategory.discovery => PhosphorIconsRegular.heart,
  SupportCategory.chat => PhosphorIconsRegular.chatCircle,
  SupportCategory.subscription => PhosphorIconsRegular.sparkle,
  SupportCategory.privacy => PhosphorIconsRegular.shieldCheck,
  SupportCategory.safety => PhosphorIconsRegular.flag,
  SupportCategory.technical => PhosphorIconsRegular.lifebuoy,
  SupportCategory.other => PhosphorIconsRegular.lifebuoy,
};

/// Help & Support: search the FAQ, browse by topic, chat with the help assistant or open your tickets.
class HelpCenterScreen extends ConsumerStatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  ConsumerState<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends ConsumerState<HelpCenterScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<FaqEntry>? _results;
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _searching = true);
      try {
        final r = await ref.read(backendProvider).supportFaqs(query: v.trim());
        if (mounted && _search.text.trim() == v.trim()) setState(() => _results = r);
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _search,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search help',
              prefixIcon: Icon(Icons.search_rounded, color: c.muted),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : (_search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Clear',
                            onPressed: () {
                              _search.clear();
                              setState(() => _results = null);
                            },
                          )),
            ),
          ),
          const SizedBox(height: 14),
          if (_results != null) ...[
            if (_results!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('No answers found. Try the Help chat or raise a ticket.', style: TextStyle(color: c.muted)),
              ),
            for (final f in _results!) FaqTile(entry: f),
          ] else ...[
            for (final cat in SupportCategoryX.helpTopics)
              _Row(
                icon: supportIcon(cat),
                title: cat.label,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FaqListScreen(category: cat))),
              ),
            const SizedBox(height: 10),
            _Row(
              icon: PhosphorIconsRegular.chatCircle,
              title: 'Help chat',
              subtitle: 'Ask a question and get an answer straight away',
              accent: true,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportChatScreen())),
            ),
            _Row(
              icon: PhosphorIconsRegular.envelopeSimple,
              title: 'My support tickets',
              subtitle: 'Your requests and replies from our team',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyTicketsScreen())),
            ),
            _Row(
              icon: PhosphorIconsRegular.plus,
              title: 'Raise a support ticket',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RaiseTicketScreen())),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.onTap, this.subtitle, this.accent = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: accent ? c.accentSoft : c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent ? c.accent.withValues(alpha: 0.5) : c.hair),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: accent ? c.accent : c.ink2),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 13, color: c.muted)),
                  ],
                ),
              ),
              Icon(PhosphorIconsRegular.caretRight, size: 18, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A question that opens to its answer.
class FaqTile extends StatelessWidget {
  const FaqTile({super.key, required this.entry});
  final FaqEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.hair),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            expandedAlignment: Alignment.centerLeft,
            title: Text(
              entry.title,
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: c.ink),
            ),
            children: [Text(entry.answer, style: TextStyle(fontSize: 14.5, height: 1.45, color: c.ink3))],
          ),
        ),
      ),
    );
  }
}

/// All questions in one topic.
class FaqListScreen extends ConsumerWidget {
  const FaqListScreen({super.key, required this.category});
  final SupportCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.fc;
    return Scaffold(
      appBar: AppBar(title: Text(category.label)),
      body: FutureBuilder<List<FaqEntry>>(
        future: ref.read(backendProvider).supportFaqs(category: category),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text('Couldn’t load help. Check your connection.', style: TextStyle(color: c.muted)),
            );
          }
          final list = snap.data;
          if (list == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              for (final f in list) FaqTile(entry: f),
              const SizedBox(height: 8),
              Text(
                'Still need help?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportChatScreen())),
                    child: const Text('Help chat'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => RaiseTicketScreen(category: category))),
                    child: const Text('Raise a ticket'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
