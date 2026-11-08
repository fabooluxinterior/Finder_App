import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/widgets.dart';
import '../../models/security.dart';
import '../../providers.dart';

final _overviewProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(backendProvider).securityOverview(),
);
final _reportsProvider = FutureProvider.autoDispose<List<ReportSummary>>((ref) => ref.watch(backendProvider).openReports());
final _pendingMediaProvider = FutureProvider.autoDispose<List<PendingMedia>>((ref) => ref.watch(backendProvider).pendingMedia());
final _verificationProvider = FutureProvider.autoDispose<List<VerificationItem>>(
  (ref) => ref.watch(backendProvider).verificationQueue(),
);

/// Staff-only. Every call is authorised server-side (staff role + MFA
/// session) and every access to private data is written to the
/// append-only audit log. Hiding this screen is not the security boundary.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Safety dashboard'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Security'),
              Tab(text: 'Reports'),
              Tab(text: 'Photo review'),
              Tab(text: 'Verification'),
            ],
          ),
        ),
        body: const TabBarView(children: [_SecurityTab(), _ReportsTab(), _MediaTab(), _VerificationTab()]),
      ),
    );
  }
}

class _SecurityTab extends ConsumerWidget {
  const _SecurityTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(_overviewProvider);
    final fmt = DateFormat('d MMM HH:mm');
    return o.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text('$e\n\nAdmins need an MFA-verified session.')),
      ),
      data: (d) {
        final counts = (d['events_24h'] as Map).cast<String, dynamic>();
        final events = (d['recent_events'] as List).cast<Map>();
        final access = (d['recent_staff_access'] as List).cast<Map>();
        return RefreshIndicator(
          onRefresh: () => ref.refresh(_overviewProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Stat('Critical (24h)', '${d['critical_24h']}', danger: (d['critical_24h'] as num) > 0),
                  _Stat('Open reports', '${d['open_reports']}'),
                  _Stat('Photos awaiting review', '${d['pending_media']}'),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Events in the last 24 hours', style: TextStyle(fontWeight: FontWeight.w800)),
              if (counts.isEmpty) const Text('None'),
              for (final e in counts.entries) ListTile(dense: true, title: Text(e.key), trailing: Text('${e.value}')),
              const SizedBox(height: 12),
              const Text('Recent security events', style: TextStyle(fontWeight: FontWeight.w800)),
              for (final e in events)
                ListTile(
                  dense: true,
                  leading: Icon(
                    e['severity'] == 'critical'
                        ? Icons.error
                        : e['severity'] == 'warning'
                        ? Icons.warning_amber
                        : Icons.info_outline,
                    color: e['severity'] == 'critical'
                        ? Colors.red
                        : e['severity'] == 'warning'
                        ? Colors.orange
                        : Colors.grey,
                  ),
                  title: Text('${e['kind']}'),
                  subtitle: Text(jsonEncode(e['details'])),
                  trailing: Text(fmt.format(DateTime.parse(e['created_at'] as String).toLocal())),
                ),
              const SizedBox(height: 12),
              const Text('Staff access log', style: TextStyle(fontWeight: FontWeight.w800)),
              for (final a in access)
                ListTile(
                  dense: true,
                  title: Text('${a['action']} · ${a['target_type']}'),
                  subtitle: Text('by ${(a['actor_id'] as String).substring(0, 8)}…'),
                  trailing: Text(fmt.format(DateTime.parse(a['created_at'] as String).toLocal())),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.danger = false});
  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) => Container(
    width: 160,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: danger ? const Color(0xFF2A1210) : context.fc.surface,
      border: Border.all(color: context.fc.hair),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: danger ? const Color(0xFFFF6B5A) : null),
        ),
        Text(label, style: TextStyle(color: context.fc.ink3)),
      ],
    ),
  );
}

class _ReportsTab extends ConsumerWidget {
  const _ReportsTab();

  Future<void> _open(BuildContext context, WidgetRef ref, ReportSummary r) async {
    final reason = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Open report evidence'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Your access is recorded in the audit log with this reason.'),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason for access'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Open')),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    try {
      final d = await ref.read(backendProvider).openReportEvidence(r.id, reason.text);
      if (!context.mounted) return;
      final resolution = TextEditingController();
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Report · ${r.reason}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Details: ${d['details'] ?? '—'}'),
                const SizedBox(height: 8),
                const Text('Shared messages (decrypted by the reporter):', style: TextStyle(fontWeight: FontWeight.w700)),
                for (final m in ((d['evidence'] as List?) ?? const []).cast<Map>())
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${m['from_reported_user'] == true ? 'Reported user' : 'Reporter'}: ${m['text']}'),
                  ),
                TextField(
                  controller: resolution,
                  decoration: const InputDecoration(labelText: 'Resolution note'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await ref.read(backendProvider).resolveReport(r.id, actioned: false, resolution: resolution.text);
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('Dismiss'),
            ),
            TextButton(
              onPressed: () async {
                await ref.read(backendProvider).resolveReport(r.id, actioned: true, resolution: resolution.text);
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('Action taken'),
            ),
          ],
        ),
      );
      ref.invalidate(_reportsProvider);
    } catch (e) {
      if (context.mounted) showSnack(context, '$e', icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(_reportsProvider);
    return reports.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => list.isEmpty
          ? const Center(child: Text('No open reports'))
          : ListView(
              children: [
                for (final r in list)
                  ListTile(
                    leading: Icon(r.hasEvidence ? Icons.chat_outlined : Icons.flag_outlined),
                    title: Text(r.reason),
                    subtitle: Text('User ${r.reportedId.substring(0, 8)}… · ${r.reportCount} report(s) total'),
                    trailing: Text(DateFormat('d MMM').format(r.createdAt)),
                    onTap: () => _open(context, ref, r),
                  ),
              ],
            ),
    );
  }
}

class _MediaTab extends ConsumerWidget {
  const _MediaTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(_pendingMediaProvider);
    return media.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => list.isEmpty
          ? const Center(child: Text('Nothing waiting for review'))
          : GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(12),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.8,
              children: [
                for (final m in list)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        Expanded(
                          child: ProfilePhoto(url: m.url, name: '?'),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () async {
                                  await ref.read(backendProvider).reviewMedia(m.id, approve: false);
                                  ref.invalidate(_pendingMediaProvider);
                                },
                                child: const Text('Reject'),
                              ),
                            ),
                            Expanded(
                              child: TextButton(
                                onPressed: () async {
                                  await ref.read(backendProvider).reviewMedia(m.id, approve: true);
                                  ref.invalidate(_pendingMediaProvider);
                                },
                                child: const Text('Approve'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Selfie verification queue: selfie, requested pose and profile photo side
/// by side. Viewing a selfie is audit-logged by the media function; the
/// decision is made by mod_review_verification (staff + MFA only).
class _VerificationTab extends ConsumerWidget {
  const _VerificationTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(_verificationProvider);
    return queue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text('$e')),
      ),
      data: (list) => list.isEmpty
          ? const Center(child: Text('No selfies waiting for review'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (_, i) {
                final v = list[i];
                Widget photo(String? url, String label) => Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 6),
                      AspectRatio(
                        aspectRatio: 3 / 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: ProfilePhoto(url: url, name: v.name),
                        ),
                      ),
                    ],
                  ),
                );
                Future<void> decide(bool approve) async {
                  try {
                    await ref.read(backendProvider).reviewVerification(v.requestId, approve: approve);
                    ref.invalidate(_verificationProvider);
                  } catch (e) {
                    if (context.mounted) showSnack(context, '$e');
                  }
                }

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.name, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text('Pose: ${v.pose}', style: Theme.of(context).textTheme.bodyMedium),
                        Text(
                          'Submitted ${DateFormat('d MMM, HH:mm').format(v.submittedAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            photo(v.selfieUrl, 'SELFIE'),
                            const SizedBox(width: 10),
                            photo(v.profileUrl, 'PROFILE PHOTO'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(onPressed: () => decide(false), child: const Text('Reject')),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(onPressed: () => decide(true), child: const Text('Approve')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
