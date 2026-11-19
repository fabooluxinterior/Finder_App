import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/message.dart';
import '../../models/profile.dart';
import '../../models/scheduled_message.dart';
import '../../providers.dart';
import '../paywall/paywall_sheet.dart';
import 'chat_screen.dart' show readTickBlue;
import 'schedule_picker.dart';

/// Messages waiting to be sent in this chat, plus the ones the server already sent and any that failed.
/// They stay here (not in the chat) until their time; then they move into the chat as normal messages.
class ScheduledMessagesScreen extends ConsumerStatefulWidget {
  const ScheduledMessagesScreen({super.key, required this.peer});
  final PublicProfile peer;

  @override
  ConsumerState<ScheduledMessagesScreen> createState() => _ScheduledMessagesScreenState();
}

class _ScheduledMessagesScreenState extends ConsumerState<ScheduledMessagesScreen> {
  late Future<List<ScheduledItem>> _items = _load();
  Timer? _tick;

  Future<List<ScheduledItem>> _load() => ref.read(backendProvider).scheduledMessages(peerId: widget.peer.id);

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) => _reload());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _items = _load());
  }

  Future<void> _run(Future<void> Function() body) async {
    try {
      await body();
      _reload();
    } on AppException catch (e) {
      if (!mounted) return;
      if (e.code == AppErrorCode.subscriptionRequired) {
        await showPaywall(context, reason: PaywallReason.messaging);
      } else {
        showSnack(context, e.message);
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _reschedule(ScheduledItem m) async {
    if (!m.editable) {
      showSnack(context, 'This can only be changed on the phone that scheduled it.');
      return;
    }
    final at = await pickSendTime(context, initial: m.sendAt);
    if (at == null) return;
    await _run(() async {
      final b = ref.read(backendProvider);
      await b.scheduleMessage(m.peerId, m.text!, at); // the new one first, so nothing is lost if it fails
      await b.cancelScheduled(m.id);
    });
  }

  Future<void> _edit(ScheduledItem m) async {
    if (!m.editable) {
      showSnack(context, 'This can only be changed on the phone that scheduled it.');
      return;
    }
    final ctl = TextEditingController(text: m.text);
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(controller: ctl, autofocus: true, maxLength: 2000, minLines: 1, maxLines: 5),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (text == null || text.isEmpty || text == m.text) return;
    await _run(() async {
      final b = ref.read(backendProvider);
      await b.scheduleMessage(m.peerId, text, m.sendAt);
      await b.cancelScheduled(m.id);
    });
  }

  Future<void> _cancel(ScheduledItem m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel this scheduled message?'),
        content: const Text('It will not be sent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancel message')),
        ],
      ),
    );
    if (ok == true) await _run(() => ref.read(backendProvider).cancelScheduled(m.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final chat = ref.watch(messagesProvider(widget.peer.id)).value ?? const <ChatMessage>[];
    final fmt = DateFormat('EEE, d MMM yyyy · h:mm a');
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled messages')),
      body: FutureBuilder<List<ScheduledItem>>(
        future: _items,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Couldn’t load your scheduled messages. Check your connection.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted),
                ),
              ),
            );
          }
          final list = snap.data;
          if (list == null) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Nothing scheduled.\nHold the send button in a chat to send a message later.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted, height: 1.4),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final m = list[i];
              final sentMsg = m.messageId == null ? null : chat.where((x) => x.id == m.messageId).firstOrNull;
              final (label, color) = switch (m.status) {
                ScheduledStatus.scheduled => ('Scheduled', c.accent),
                ScheduledStatus.sent => switch (sentMsg?.receipt) {
                  ReceiptStatus.read => ('Read', readTickBlue),
                  ReceiptStatus.delivered => ('Delivered', c.ok),
                  _ => ('Sent', c.ok),
                },
                ScheduledStatus.failed => ('Not sent', c.gold),
                ScheduledStatus.cancelled => ('Cancelled', c.muted),
              };
              return Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.hair),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('To ${widget.peer.firstName}', style: TextStyle(fontSize: 12.5, color: c.muted)),
                          const SizedBox(height: 2),
                          Text(
                            (m.text ?? '').isEmpty ? 'Message' : m.text!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15.5, color: c.ink),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.schedule, size: 14, color: c.muted),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  '${fmt.format(m.sendAt)}${m.timezone == null ? '' : ' ${m.timezone}'}',
                                  style: TextStyle(fontSize: 12.5, color: c.muted),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                            ),
                          ),
                          if (m.status == ScheduledStatus.failed && (m.error ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(m.error!, style: TextStyle(fontSize: 12.5, color: c.muted)),
                            ),
                        ],
                      ),
                    ),
                    if (m.status == ScheduledStatus.scheduled)
                      PopupMenuButton<String>(
                        tooltip: 'Options',
                        onSelected: (v) {
                          switch (v) {
                            case 'edit':
                              _edit(m);
                            case 'time':
                              _reschedule(m);
                            case 'cancel':
                              _cancel(m);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'time', child: Text('Reschedule')),
                          PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                        ],
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
