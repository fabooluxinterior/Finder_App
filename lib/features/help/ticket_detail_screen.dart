import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/feedback.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/support.dart';
import '../../providers.dart';
import 'my_tickets_screen.dart';

/// One ticket: its status, the whole conversation with the team, your reply box, and reopen / rate once it is resolved.
class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.ticket});
  final SupportTicket ticket;

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  late SupportTicket _ticket = widget.ticket;
  List<TicketMessage> _thread = const [];
  List<TicketEvent> _events = const [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  bool _loaded = false;
  bool _sending = false;
  bool _showHistory = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final b = ref.read(backendProvider);
      final results = await Future.wait<Object>([b.ticketThread(_ticket.id), b.ticketEvents(_ticket.id), b.myTickets()]);
      if (!mounted) return;
      final fresh = (results[2] as List<SupportTicket>).where((t) => t.id == _ticket.id).firstOrNull;
      final thread = results[0] as List<TicketMessage>;
      final grew = thread.length > _thread.length;
      setState(() {
        _thread = thread;
        _events = results[1] as List<TicketEvent>;
        if (fresh != null) _ticket = fresh;
        _loaded = true;
        _error = null;
      });
      if (grew) {
        if (_thread.isNotEmpty && _thread.last.fromStaff) {
          Fx.instance.received();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: Motion.of(context, Motion.medium),
              curve: Motion.easeOut,
            );
          }
        });
      }
    } catch (_) {
      if (mounted && !_loaded) setState(() => _error = 'Couldn’t load this ticket. Check your connection.');
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(backendProvider).replyToTicket(_ticket.id, text);
      _input.clear();
      await _refresh();
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reopen() async {
    try {
      await ref.read(backendProvider).reopenTicket(_ticket.id);
      ref.invalidate(myTicketsProvider);
      await _refresh();
      if (mounted) showSnack(context, 'Ticket reopened.');
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _rate() async {
    var stars = 0;
    final comment = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Rate our support'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      tooltip: '$i star${i == 1 ? '' : 's'}',
                      onPressed: () => set(() => stars = i),
                      icon: Icon(
                        i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 32,
                        color: i <= stars ? ctx.fc.gold : ctx.fc.muted,
                      ),
                    ),
                ],
              ),
              TextField(
                controller: comment,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Anything to add? (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            FilledButton(onPressed: stars == 0 ? null : () => Navigator.pop(ctx, true), child: const Text('Send')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(backendProvider)
          .rateTicket(_ticket.id, stars, comment: comment.text.trim().isEmpty ? null : comment.text.trim());
      ref.invalidate(myTicketsProvider);
      await _refresh();
      if (mounted) showSnack(context, 'Thanks for your feedback.');
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = _ticket;
    final color = ticketStatusColor(context, t.status);
    final closed = t.status == TicketStatus.closed;
    final fmt = DateFormat('d MMM, h:mm a');
    return Scaffold(
      appBar: AppBar(title: Text(t.ticketNo)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.hair)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.subject,
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: c.ink),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(t.status.label, color),
                    Text('${t.category.label} · ${t.priority.label} priority', style: TextStyle(fontSize: 12.5, color: c.muted)),
                    GestureDetector(
                      onTap: () => setState(() => _showHistory = !_showHistory),
                      child: Text(
                        _showHistory ? 'Hide history' : 'Status history',
                        style: TextStyle(fontSize: 12.5, color: c.accent),
                      ),
                    ),
                  ],
                ),
                if (_showHistory)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in _events)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '${fmt.format(e.at)} · ${e.status.label}${(e.note ?? '').isEmpty ? '' : ' · ${e.note}'}',
                              style: TextStyle(fontSize: 12.5, color: c.ink3),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: !_loaded
                ? Center(
                    child: _error == null ? const CircularProgressIndicator() : Text(_error!, style: TextStyle(color: c.muted)),
                  )
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    children: [
                      for (final m in _thread)
                        Align(
                          alignment: m.fromStaff ? Alignment.centerLeft : Alignment.centerRight,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: m.fromStaff ? c.surface : c.accent,
                                border: m.fromStaff ? Border.all(color: c.hair) : null,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (m.fromStaff)
                                    Text(
                                      'Vouby team',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.accent),
                                    ),
                                  Text(m.body, style: TextStyle(fontSize: 15, height: 1.4, color: m.fromStaff ? c.ink : c.paper)),
                                  const SizedBox(height: 3),
                                  Text(
                                    fmt.format(m.createdAt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: (m.fromStaff ? c.muted : c.paper.withValues(alpha: 0.7)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (t.status == TicketStatus.waitingForUser)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('The team is waiting for your reply.', style: TextStyle(fontSize: 13, color: c.accent)),
                        ),
                      if (t.status == TicketStatus.resolved || closed)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (t.canReopen) OutlinedButton(onPressed: _reopen, child: const Text('Reopen ticket')),
                              if (t.canRate) OutlinedButton(onPressed: _rate, child: const Text('Rate support')),
                              if (t.rating != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Text('You rated this ${t.rating}/5. Thank you.', style: TextStyle(color: c.muted)),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          if (!closed)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 2000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Write a reply',
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: BorderSide(color: c.hair),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: BorderSide(color: c.hair),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: BorderSide(color: c.ink3),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      tooltip: 'Send',
                      style: IconButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: c.paper,
                        fixedSize: const Size(52, 52),
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 22),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, this.color, {super.key});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
    child: Text(
      label,
      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
    ),
  );
}
