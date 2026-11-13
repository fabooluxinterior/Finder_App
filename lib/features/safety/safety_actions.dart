import 'package:flutter/material.dart';

import '../../core/theme.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../../models/message.dart';
import '../../models/moderation.dart';
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
        'You’ll both lose the chat. The conversation is deleted from this device and from Vouby’s servers. '
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
        'Your chat is deleted from this device and from Vouby’s servers.',
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

/// Returns true when a report was sent. [selected] are the messages or photos
/// the user picked in the chat (long-press); only those can be shared, and
/// only after a preview and confirmation.
Future<bool> showReportSheet(
  BuildContext context,
  PublicProfile peer, {
  List<ChatMessage> thread = const [],
  List<ChatMessage> selected = const [],
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReportSheet(peer: peer, thread: thread, selected: selected),
  );
  return sent ?? false;
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.peer, required this.thread, required this.selected});
  final PublicProfile peer;
  final List<ChatMessage> thread;
  final List<ChatMessage> selected;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  ReportReason? _reason;
  final _details = TextEditingController();
  late bool _shareSelected = widget.selected.isNotEmpty;
  bool _block = true;
  bool _busy = false;

  List<ChatMessage> get _texts => widget.selected.where((m) => !m.isVoice && !m.isImage && (m.content ?? '').isNotEmpty).toList();
  List<ChatMessage> get _photos => widget.selected.where((m) => m.isImage).toList();

  Future<ReportEvidence> _buildEvidence() async {
    if (!_shareSelected || widget.selected.isEmpty) return const ReportEvidence();
    final backend = ref.read(backendProvider);
    final images = <(String, List<int>)>[];
    for (final m in _photos.take(10)) {
      try {
        images.add((m.id, await backend.imageBytes(m)));
      } catch (_) {
        // A photo that can't be opened on this device is skipped.
      }
    }
    return ReportEvidence(
      texts: [
        for (final m in _texts.take(20))
          {
            'message_id': m.id,
            'from_reported_user': m.senderId == widget.peer.id,
            'sent_at': m.createdAt.toUtc().toIso8601String(),
            'text': m.content,
          },
      ],
      images: images,
    );
  }

  Future<void> _send() async {
    final evidenceCount = _shareSelected ? _texts.length + _photos.length : 0;
    if (evidenceCount > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Share this evidence?'),
          content: Text(
            'You’re about to share ${_texts.length} ${_texts.length == 1 ? 'message' : 'messages'}'
            '${_photos.isEmpty ? '' : ' and ${_photos.length} ${_photos.length == 1 ? 'photo' : 'photos'}'} '
            'with Vouby’s safety team. They’re decrypted on your phone and sent with your report. Nothing else from this chat '
            'is shared. Every access is logged and the evidence is deleted 90 days after the report is closed.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Share and report')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final evidence = await _buildEvidence();
      final no = await ref
          .read(backendProvider)
          .reportWithEvidence(
            widget.peer.id,
            _reason!,
            details: _details.text.trim().isEmpty ? null : _details.text.trim(),
            contentRef: widget.selected.isEmpty ? null : 'msg:${widget.selected.first.id}',
            evidence: evidence,
            block: _block,
          );
      _refresh(ref);
      if (!mounted) return;
      Navigator.pop(context, true);
      showSnack(context, 'Report $no sent. Our safety team will review it.', icon: Icons.shield_outlined);
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
    final c = context.fc;
    final selected = widget.selected;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Report ${widget.peer.firstName}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'They won’t know you reported them. A person reviews every report; nobody is banned automatically.',
              style: TextStyle(color: c.muted),
            ),
            const SizedBox(height: 12),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final r in ReportReason.values.where((r) => r.selectable))
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
            if (selected.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Evidence preview',
                style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.hair),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final m in _texts)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '${m.senderId == widget.peer.id ? widget.peer.firstName : 'You'}: ${m.content}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: c.ink2),
                        ),
                      ),
                    if (_photos.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(spacing: 6, runSpacing: 6, children: [for (final m in _photos) _EvidenceThumb(message: m)]),
                      ),
                    if (selected.any((m) => m.isVoice))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Voice notes aren’t shared.', style: TextStyle(fontSize: 12.5, color: c.muted)),
                      ),
                  ],
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _shareSelected,
                onChanged: (v) => setState(() => _shareSelected = v ?? false),
                title: const Text('Include only these with my report'),
                subtitle: const Text('Decrypted on your phone. Nothing else from the chat is shared.'),
              ),
            ] else if (widget.thread.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(
                  'Tip: to include messages or photos as evidence, long-press them in the chat, then tap Report.',
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _block,
              onChanged: (v) => setState(() => _block = v),
              title: Text('Also block ${widget.peer.firstName}'),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy || _reason == null ? null : _send, child: Text(_busy ? 'Sending…' : 'Send report')),
          ],
        ),
      ),
    );
  }
}

class _EvidenceThumb extends ConsumerWidget {
  const _EvidenceThumb({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox(
      width: 72,
      height: 72,
      child: FutureBuilder(
        future: ref.read(backendProvider).imageBytes(message),
        builder: (_, s) => s.hasData
            ? Image.memory(s.data!, fit: BoxFit.cover)
            : ColoredBox(color: context.fc.hair, child: const Icon(Icons.image_outlined)),
      ),
    ),
  );
}
