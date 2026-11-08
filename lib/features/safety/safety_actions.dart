import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../../models/message.dart';
import '../../models/profile.dart';
import '../../models/security.dart';
import '../../providers.dart';

void _refresh(WidgetRef ref) {
  ref.invalidate(connectionsProvider);
  ref.invalidate(incomingRequestsProvider);
  ref.invalidate(feedProvider);
}

Future<bool> confirmUnmatch(BuildContext context, WidgetRef ref, PublicProfile peer) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Unmatch ${peer.firstName}?'),
      content: const Text(
        'You’ll both lose the chat. The conversation is deleted from this device and from Finder’s servers. '
        'Copies already on their device can’t be removed by us.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Unmatch')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await ref.read(backendProvider).unmatch(peer.id);
    _refresh(ref);
    if (context.mounted) showSnack(context, 'Unmatched ${peer.firstName}');
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, '$e', icon: Icons.error_outline);
    return false;
  }
}

Future<bool> confirmBlock(BuildContext context, WidgetRef ref, PublicProfile peer) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Block ${peer.firstName}?'),
      content: const Text(
        'They won’t be able to see your profile, request you again, or send you messages. '
        'Your chat is deleted from this device and from Finder’s servers.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Block')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await ref.read(backendProvider).blockUser(peer.id);
    _refresh(ref);
    if (context.mounted) showSnack(context, '${peer.firstName} is blocked', icon: Icons.block);
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, '$e', icon: Icons.error_outline);
    return false;
  }
}

/// Returns true when a report was sent.
Future<bool> showReportSheet(BuildContext context, PublicProfile peer, {List<ChatMessage> thread = const []}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReportSheet(peer: peer, thread: thread),
  );
  return sent ?? false;
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.peer, required this.thread});
  final PublicProfile peer;
  final List<ChatMessage> thread;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  ReportReason? _reason;
  final _details = TextEditingController();
  bool _shareMessages = false;
  bool _block = true;
  bool _busy = false;

  List<ChatMessage> get _theirRecent =>
      widget.thread.where((m) => m.senderId == widget.peer.id && !m.isVoice).toList().reversed.take(10).toList();

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(backendProvider)
          .report(
            widget.peer.id,
            _reason!,
            details: _details.text.trim().isEmpty ? null : _details.text.trim(),
            evidence: _shareMessages ? _theirRecent : const [],
            block: _block,
          );
      _refresh(ref);
      if (!mounted) return;
      Navigator.pop(context, true);
      showSnack(context, 'Thanks. Our safety team will review this.', icon: Icons.shield_outlined);
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recent = _theirRecent;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Report ${widget.peer.firstName}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('They won’t know you reported them.', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final r in ReportReason.values)
                    RadioListTile<ReportReason>(value: r, title: Text(r.label), dense: true, contentPadding: EdgeInsets.zero),
                ],
              ),
            ),
            TextField(
              controller: _details,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'What happened? (optional)'),
            ),
            if (recent.isNotEmpty) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _shareMessages,
                onChanged: (v) => setState(() => _shareMessages = v ?? false),
                title: Text('Share their last ${recent.length} messages with moderators'),
                subtitle: const Text(
                  'Your chat is end-to-end encrypted, so moderators can’t see it unless you choose to share it. '
                  'If you tick this, these messages are decrypted on your phone and sent with your report. '
                  'Only Finder’s safety team can read them, every access is logged, and they’re deleted 90 days after the report is closed.',
                ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _block,
              onChanged: (v) => setState(() => _block = v),
              title: Text('Also block ${widget.peer.firstName}'),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy || _reason == null ? null : _send, child: const Text('Send report')),
          ],
        ),
      ),
    );
  }
}
