import 'package:flutter/material.dart';

import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'contact_support_screen.dart';
import 'faq_content.dart';
import 'my_tickets_screen.dart';

/// Help Center: a chat-style FAQ. Pick a topic, then a question; the answer
/// arrives as a reply. "Contact support" is always one tap away.
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _Bubble {
  const _Bubble(this.text, {required this.mine});
  final String text;
  final bool mine;
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _bubbles = <_Bubble>[const _Bubble('Hi! I’m the Vouby help assistant. What do you need help with?', mine: false)];
  FaqCategory? _category;
  final _scroll = ScrollController();

  void _say(String mine, String reply) {
    setState(() {
      _bubbles
        ..add(_Bubble(mine, mine: true))
        ..add(_Bubble(reply, mine: false));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Motion.of(context, Motion.medium), curve: Motion.easeOut);
      }
    });
  }

  void _pickCategory(FaqCategory c) {
    _category = c;
    _say(c.title, 'Here are common questions about ${c.title.toLowerCase()}. Tap one.');
  }

  void _pickQuestion(Faq f) => _say(f.question, f.answer);

  void _contact() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ContactSupportScreen(category: _category?.support)));

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final cat = _category;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help Center'),
        actions: [
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyTicketsScreen())),
            child: const Text('My tickets'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              itemCount: _bubbles.length,
              itemBuilder: (_, i) {
                final b = _bubbles[i];
                return Align(
                  alignment: b.mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: b.mine ? c.accent : c.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: b.mine ? null : Border.all(color: c.hair),
                    ),
                    child: Text(b.text, style: TextStyle(fontSize: 15, height: 1.4, color: b.mine ? Colors.white : c.ink)),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: c.paper,
                border: Border(top: BorderSide(color: c.hair)),
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (cat == null)
                        for (final f in faqCategories) _Choice(label: f.title, onTap: () => _pickCategory(f))
                      else ...[
                        for (final f in cat.items) _Choice(label: f.question, onTap: () => _pickQuestion(f)),
                        _Choice(
                          label: 'Other topics',
                          icon: PhosphorIconsRegular.arrowLeft,
                          onTap: () => setState(() {
                            _category = null;
                            _bubbles.add(const _Bubble('Sure, pick another topic.', mine: false));
                          }),
                        ),
                      ],
                      _Choice(
                        label: 'Still need help? Contact support',
                        icon: PhosphorIconsRegular.envelopeSimple,
                        accent: true,
                        onTap: _contact,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.onTap, this.icon, this.accent = false});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: accent ? c.accentSoft : c.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: accent ? c.accent.withValues(alpha: 0.6) : c.hair),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: accent ? c.accent : c.ink2), const SizedBox(width: 6)],
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: accent ? c.accent : c.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
