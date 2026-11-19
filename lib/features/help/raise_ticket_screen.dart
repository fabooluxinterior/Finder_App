import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/feedback.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/support.dart';
import '../../providers.dart';
import 'my_tickets_screen.dart';
import 'ticket_detail_screen.dart';

/// The ticket form: category, title, details and priority. Text only (no screenshots or images).
/// The ticket id, app version, device and the chatbot conversation are added automatically.
class RaiseTicketScreen extends ConsumerStatefulWidget {
  const RaiseTicketScreen({super.key, this.category, this.title, this.details, this.botConversationId});
  final SupportCategory? category;
  final String? title;
  final String? details;
  final String? botConversationId;

  @override
  ConsumerState<RaiseTicketScreen> createState() => _RaiseTicketScreenState();
}

class _RaiseTicketScreenState extends ConsumerState<RaiseTicketScreen> {
  late SupportCategory _category = widget.category ?? SupportCategory.other;
  TicketPriority _priority = TicketPriority.normal;
  late final _title = TextEditingController(text: widget.title);
  late final _details = TextEditingController(text: widget.details);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final problem = validateTicket(subject: _title.text, description: _details.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await ref
          .read(backendProvider)
          .submitSupportTicket(
            category: _category,
            subject: _title.text.trim(),
            description: _details.text.trim(),
            priority: _priority,
            botConversationId: widget.botConversationId,
          );
      Fx.instance.request();
      ref.invalidate(myTicketsProvider);
      if (!mounted) return;
      showSnack(context, 'Ticket ${t.ticketNo} sent. We’ll reply here.', icon: PhosphorIconsFill.checkCircle);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TicketDetailScreen(ticket: t)));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Scaffold(
      appBar: AppBar(title: const Text('Raise a support ticket')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Tell us what happened in words. Please don’t include passwords or one-time codes. A person reads every ticket.',
            style: TextStyle(fontSize: 14, height: 1.4, color: c.ink3),
          ),
          const SizedBox(height: 18),
          _Label('Issue category'),
          DropdownButtonFormField<SupportCategory>(
            isExpanded: true,
            initialValue: _category,
            items: [for (final s in SupportCategory.values) DropdownMenuItem(value: s, child: Text(s.label))],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 16),
          _Label('Title'),
          TextField(
            controller: _title,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'A short summary', counterText: ''),
          ),
          const SizedBox(height: 16),
          _Label('Details'),
          TextField(
            controller: _details,
            minLines: 5,
            maxLines: 10,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'What happened? What did you expect?', counterText: ''),
          ),
          const SizedBox(height: 16),
          _Label('Priority'),
          Wrap(
            spacing: 8,
            children: [
              for (final p in [TicketPriority.low, TicketPriority.normal, TicketPriority.high])
                ChoiceChip(label: Text(p.label), selected: _priority == p, onSelected: (_) => setState(() => _priority = p)),
            ],
          ),
          if (_category == SupportCategory.safety)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Safety tickets are reviewed first, whatever priority you choose.',
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(_error!, style: TextStyle(color: c.accent)),
            ),
          const SizedBox(height: 22),
          PillButton(label: 'Submit ticket', busy: _busy, onTap: _busy ? null : _submit),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.fc.ink2),
    ),
  );
}
