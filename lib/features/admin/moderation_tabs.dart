import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/moderation.dart';
import '../../models/security.dart';
import '../../models/support.dart';
import '../../providers.dart';
import '../help/my_tickets_screen.dart' show ticketStatusColor;

final staffReportsProvider = FutureProvider.autoDispose.family<List<StaffReport>, String>(
  (ref, status) => ref.watch(backendProvider).staffReports(status: status),
);
final staffTicketsProvider = FutureProvider.autoDispose.family<List<SupportTicket>, String>(
  (ref, status) => ref.watch(backendProvider).staffTickets(status: status),
);

String _short(String id) => id.length > 8 ? '${id.substring(0, 8)}…' : id;

/// Reports: every one is reviewed by a person. Decisions (incl. "false
/// report") and any restriction are recorded in the moderation history;
/// nothing is decided automatically from report counts.
class ModerationReportsTab extends ConsumerStatefulWidget {
  const ModerationReportsTab({super.key});

  @override
  ConsumerState<ModerationReportsTab> createState() => _ModerationReportsTabState();
}

class _ModerationReportsTabState extends ConsumerState<ModerationReportsTab> {
  String _status = 'open';

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final reports = ref.watch(staffReportsProvider(_status));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'open', label: Text('Open')),
              ButtonSegment(value: 'actioned', label: Text('Actioned')),
              ButtonSegment(value: 'dismissed', label: Text('Dismissed')),
            ],
            selected: {_status},
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: context.fc.accentSoft,
              selectedForegroundColor: context.fc.accent,
            ),
            onSelectionChanged: (v) => setState(() => _status = v.first),
          ),
        ),
        Expanded(
          child: reports.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) => list.isEmpty
                ? Center(
                    child: Text('No reports here', style: TextStyle(color: c.muted)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = list[i];
                      return Card(
                        child: ListTile(
                          title: Text('${r.reportNo} · ${r.reason.label}'),
                          subtitle: Text(
                            [
                              'User ${_short(r.reportedId)} · ${r.reportCount} report(s) total',
                              if (r.hasEvidence || r.evidenceFiles > 0)
                                'Evidence: ${r.hasEvidence ? 'messages' : ''}${r.hasEvidence && r.evidenceFiles > 0 ? ' + ' : ''}'
                                    '${r.evidenceFiles > 0 ? '${r.evidenceFiles} photo(s)' : ''}',
                              if (r.reporterFalseReports > 0) '⚠ Reporter has ${r.reporterFalseReports} false report(s)',
                              if (r.decision != null) 'Decision: ${r.decision!.label}',
                            ].join('\n'),
                          ),
                          isThreeLine: true,
                          trailing: Text(DateFormat('d MMM').format(r.createdAt)),
                          onTap: () async {
                            await showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              builder: (_) => _ReportReview(report: r),
                            );
                            ref.invalidate(staffReportsProvider);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _ReportReview extends ConsumerStatefulWidget {
  const _ReportReview({required this.report});
  final StaffReport report;

  @override
  ConsumerState<_ReportReview> createState() => _ReportReviewState();
}

class _ReportReviewState extends ConsumerState<_ReportReview> {
  ModDecision? _decision;
  final _note = TextEditingController();
  int? _days = 7;
  bool _busy = false;
  Map<String, dynamic>? _history;
  Map<String, dynamic>? _evidence;
  List<EvidenceItem>? _files;

  @override
  void initState() {
    super.initState();
    final b = ref.read(backendProvider);
    b
        .userModerationHistory(widget.report.reportedId)
        .then((h) {
          if (mounted) setState(() => _history = h);
        })
        .catchError((_) {});
    if (widget.report.evidenceFiles > 0) {
      b
          .reportEvidenceFiles(widget.report.id)
          .then((f) {
            if (mounted) setState(() => _files = f);
          })
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _openMessages() async {
    try {
      final d = await ref.read(backendProvider).openReportEvidence(widget.report.id, 'review ${widget.report.reportNo}');
      if (mounted) setState(() => _evidence = d);
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _openFile(EvidenceItem f) async {
    try {
      final url = await ref
          .read(backendProvider)
          .staffFileUrl(kind: 'evidence', id: f.id, reason: 'review ${widget.report.reportNo}');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.network(url, fit: BoxFit.contain),
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close (link expires in 5 minutes)')),
            ],
          ),
        ),
      );
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _decide() async {
    final d = _decision;
    if (d == null) return;
    if (d != ModDecision.review && _note.text.trim().isEmpty) {
      showSnack(context, 'Add a note explaining the decision.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(backendProvider)
          .decideReport(
            widget.report.id,
            d,
            note: _note.text.trim(),
            days: d == ModDecision.restricted || d == ModDecision.suspended ? _days : null,
          );
      if (mounted) Navigator.pop(context);
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final r = widget.report;
    final h = _history;
    final timed = _decision == ModDecision.restricted || _decision == ModDecision.suspended;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${r.reportNo} · ${r.reason.label}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Reported user ${_short(r.reportedId)} · reporter ${_short(r.reporterId)}'
              '${r.reporterFalseReports > 0 ? ' (⚠ ${r.reporterFalseReports} earlier false report(s))' : ''}',
              style: TextStyle(color: c.muted),
            ),
            if (r.details != null) ...[const SizedBox(height: 10), Text('“${r.details}”')],
            if (r.contentRef != null) Text('Content: ${r.contentRef}', style: TextStyle(color: c.muted, fontSize: 13)),
            if (h != null) ...[
              const SizedBox(height: 12),
              Text(
                'History: ${h['reports_against']} report(s) against, ${h['reports_upheld']} upheld, '
                '${(h['restrictions'] as List?)?.length ?? 0} restriction(s).',
                style: TextStyle(color: c.ink2),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (r.hasEvidence && _evidence == null)
                  OutlinedButton(onPressed: _openMessages, child: const Text('Open shared messages (logged)')),
                for (final f in _files ?? const <EvidenceItem>[])
                  OutlinedButton(onPressed: () => _openFile(f), child: Text('Open ${f.kind} (logged)')),
              ],
            ),
            if (_evidence != null)
              for (final m in ((_evidence!['evidence'] as List?) ?? const []).cast<Map>())
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${m['from_reported_user'] == true ? 'Reported user' : 'Reporter'}: ${m['text']}'),
                ),
            const SizedBox(height: 16),
            const Text('Decision', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in ModDecision.values)
                  ChoiceChip(label: Text(d.label), selected: _decision == d, onSelected: (_) => setState(() => _decision = d)),
              ],
            ),
            if (timed) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Duration'),
                  const SizedBox(width: 12),
                  DropdownButton<int?>(
                    value: _days,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 day')),
                      DropdownMenuItem(value: 7, child: Text('7 days')),
                      DropdownMenuItem(value: 30, child: Text('30 days')),
                      DropdownMenuItem(value: null, child: Text('Until lifted')),
                    ],
                    onChanged: (v) => setState(() => _days = v),
                  ),
                ],
              ),
            ],
            if (_decision == ModDecision.banned)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Bans are permanent and need an admin.', style: TextStyle(color: c.accent)),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Note (shown in history; reason sent to the user for restrictions)'),
            ),
            FilledButton(onPressed: _busy || _decision == null ? null : _decide, child: const Text('Save decision')),
          ],
        ),
      ),
    );
  }
}

/// Support tickets: status changes notify the user.
class SupportTicketsTab extends ConsumerStatefulWidget {
  const SupportTicketsTab({super.key});

  @override
  ConsumerState<SupportTicketsTab> createState() => _SupportTicketsTabState();
}

class _SupportTicketsTabState extends ConsumerState<SupportTicketsTab> {
  String _status = 'open';

  Future<void> _change(SupportTicket t) async {
    final note = TextEditingController();
    TicketStatus next = t.status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('${t.ticketNo} · ${t.subject}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${t.category.label} · ${t.email ?? 'no email'}'),
                const SizedBox(height: 8),
                Text(t.description),
                if (t.hasAttachment)
                  TextButton(
                    onPressed: () async {
                      try {
                        final url = await ref.read(backendProvider).staffFileUrl(kind: 'ticket', id: t.id);
                        if (c.mounted) {
                          await showDialog<void>(
                            context: c,
                            builder: (_) => Dialog(child: Image.network(url)),
                          );
                        }
                      } on AppException catch (e) {
                        if (c.mounted) showSnack(c, e.message);
                      }
                    },
                    child: const Text('Open screenshot (logged)'),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in TicketStatus.values)
                      ChoiceChip(label: Text(s.label), selected: next == s, onSelected: (_) => set(() => next = s)),
                  ],
                ),
                TextField(
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Message to the user (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Update')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(backendProvider).setTicketStatus(t.id, next, note: note.text.trim().isEmpty ? null : note.text.trim());
      ref.invalidate(staffTicketsProvider);
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final tickets = ref.watch(staffTicketsProvider(_status));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'open', label: Text('Open')),
              ButtonSegment(value: 'resolved', label: Text('Resolved')),
              ButtonSegment(value: 'all', label: Text('All')),
            ],
            selected: {_status},
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: context.fc.accentSoft,
              selectedForegroundColor: context.fc.accent,
            ),
            onSelectionChanged: (v) => setState(() => _status = v.first),
          ),
        ),
        Expanded(
          child: tickets.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) => list.isEmpty
                ? Center(
                    child: Text('No tickets here', style: TextStyle(color: c.muted)),
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final t in list)
                        Card(
                          child: ListTile(
                            title: Text('${t.ticketNo} · ${t.subject}'),
                            subtitle: Text('${t.category.label} · ${DateFormat('d MMM, h:mm a').format(t.createdAt)}'),
                            trailing: Text(
                              t.status.label,
                              style: TextStyle(color: ticketStatusColor(context, t.status), fontWeight: FontWeight.w600),
                            ),
                            onTap: () => _change(t),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
