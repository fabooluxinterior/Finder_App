import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../ui.dart';

String _short(String id) => id.length > 8 ? '${id.substring(0, 8)}…' : id;

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key, required this.api});
  final AdminApi api;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Safety overview',
    subtitle: 'Open work and recent security events.',
    children: [
      Loader<Map<String, dynamic>>(
        load: api.securityOverview,
        builder: (context, m, reload) {
          final scalars = {
            for (final e in m.entries)
              if (e.value is num) e.key: e.value as num,
          };
          final maps = {
            for (final e in m.entries)
              if (e.value is Map) e.key: (e.value as Map).cast<String, dynamic>(),
          };
          final lists = {
            for (final e in m.entries)
              if (e.value is List) e.key: e.value as List,
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: 'Now',
                trailing: IconButton(onPressed: reload, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [for (final e in scalars.entries) StatTile(label: e.key.replaceAll('_', ' '), value: '${e.value}')],
                ),
              ),
              for (final e in maps.entries)
                SectionCard(
                  title: e.key.replaceAll('_', ' '),
                  child: Column(
                    children: [
                      for (final kv in e.value.entries)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(kv.key),
                          trailing: Text('${kv.value}'),
                        ),
                    ],
                  ),
                ),
              for (final e in lists.entries)
                SectionCard(
                  title: e.key.replaceAll('_', ' '),
                  child: Column(
                    children: [
                      for (final row in e.value.take(30))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(row is Map ? '${row['kind'] ?? row['action'] ?? ''}' : '$row'),
                          subtitle: row is Map ? Text(jsonEncode(row['details'] ?? row['target_type'] ?? ''), maxLines: 2) : null,
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, required this.api});
  final AdminApi api;

  Future<void> _open(BuildContext context, ReportItem r) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Open report evidence'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Why are you opening it? (logged)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Open')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final ev = await api.openReportEvidence(r.id, reason.text.trim().isEmpty ? 'review' : reason.text.trim());
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Report · ${r.reason}'),
          content: SingleChildScrollView(child: SelectableText(const JsonEncoder.withIndent('  ').convert(ev))),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
        ),
      );
    } on AdminException catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  Future<void> _resolve(BuildContext context, ReportItem r, bool actioned, VoidCallback reload) async {
    try {
      await api.resolveReport(r.id, actioned: actioned, resolution: actioned ? 'Actioned from admin web' : 'Dismissed');
      reload();
    } on AdminException catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Reports',
    subtitle: 'Opening evidence is logged with your reason.',
    children: [
      Loader<List<ReportItem>>(
        load: api.openReports,
        builder: (context, items, reload) => items.isEmpty
            ? const SectionCard(
                title: 'No open reports',
                child: Text('All caught up.', style: TextStyle(color: muted)),
              )
            : Column(
                children: [
                  for (final r in items)
                    SectionCard(
                      title: r.reason.replaceAll('_', ' '),
                      subtitle: 'User ${_short(r.reportedId)} · ${r.reportCount} report(s) · ${fmtDate(r.createdAt)}',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (r.hasEvidence)
                            OutlinedButton(onPressed: () => _open(context, r), child: const Text('Open evidence')),
                          FilledButton(onPressed: () => _resolve(context, r, true, reload), child: const Text('Take action')),
                          TextButton(onPressed: () => _resolve(context, r, false, reload), child: const Text('Dismiss')),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    ],
  );
}

class MediaReviewPage extends StatelessWidget {
  const MediaReviewPage({super.key, required this.api});
  final AdminApi api;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Photo review',
    subtitle: 'Photos the automatic check flagged for a person to look at.',
    children: [
      Loader<List<MediaItem>>(
        load: api.pendingMedia,
        builder: (context, items, reload) => items.isEmpty
            ? const SectionCard(
                title: 'Nothing to review',
                child: Text('All caught up.', style: TextStyle(color: muted)),
              )
            : Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final m in items)
                    SizedBox(
                      width: 260,
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(
                              aspectRatio: 4 / 5,
                              child: m.url.isEmpty
                                  ? const ColoredBox(
                                      color: hair,
                                      child: Icon(Icons.image_outlined, size: 48, color: muted),
                                    )
                                  : Image.network(
                                      m.url,
                                      headers: api.mediaHeaders,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const ColoredBox(
                                        color: hair,
                                        child: Icon(Icons.broken_image_outlined, color: muted),
                                      ),
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text('${m.kind} · ${_short(m.ownerId)}', style: const TextStyle(color: muted)),
                                  ),
                                  IconButton(
                                    tooltip: 'Reject',
                                    onPressed: () async {
                                      await api.reviewMedia(m.id, approve: false);
                                      reload();
                                    },
                                    icon: const Icon(Icons.close, color: accent),
                                  ),
                                  IconButton(
                                    tooltip: 'Approve',
                                    onPressed: () async {
                                      await api.reviewMedia(m.id, approve: true);
                                      reload();
                                    },
                                    icon: const Icon(Icons.check, color: okGreen),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    ],
  );
}

class VerificationPage extends StatelessWidget {
  const VerificationPage({super.key, required this.api});
  final AdminApi api;

  Widget _photo(String? url, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 12.5)),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 180,
          height: 225,
          child: url == null
              ? const ColoredBox(
                  color: hair,
                  child: Icon(Icons.person_outline, size: 48, color: muted),
                )
              : Image.network(url, headers: api.mediaHeaders, fit: BoxFit.cover),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Verification',
    subtitle: 'Compare the live selfie (with the requested pose) to the profile photo.',
    children: [
      Loader<List<VerificationQueueItem>>(
        load: api.verificationQueue,
        builder: (context, items, reload) => items.isEmpty
            ? const SectionCard(
                title: 'No pending selfies',
                child: Text('All caught up.', style: TextStyle(color: muted)),
              )
            : Column(
                children: [
                  for (final v in items)
                    SectionCard(
                      title: v.name,
                      subtitle: 'Pose: ${v.pose} · ${fmtDate(v.submittedAt)}',
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          _photo(v.selfieUrl, 'Selfie'),
                          _photo(v.profileUrl, 'Profile photo'),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FilledButton(
                                onPressed: () async {
                                  await api.reviewVerification(v.requestId, approve: true);
                                  reload();
                                },
                                child: const Text('Approve'),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: () async {
                                  await api.reviewVerification(v.requestId, approve: false);
                                  reload();
                                },
                                child: const Text('Reject'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    ],
  );
}
