import 'package:flutter/material.dart';

import '../api.dart';
import '../models_mod.dart';
import '../ui.dart';

String _words(String s) => s.replaceAll('_', ' ');

Color statusColor(AccountStatus s) => switch (s) {
  AccountStatus.active => okGreen,
  AccountStatus.restricted => warnAmber,
  AccountStatus.suspended || AccountStatus.deactivated => const Color(0xFFFF8A3D),
  AccountStatus.banned || AccountStatus.removalPending => const Color(0xFFFF4D4D),
};

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final AccountStatus status;
  @override
  Widget build(BuildContext context) => StatusChip(status.label, color: statusColor(status));
}

/// Asks for the note (and optionally a number of days) that every action requires.
Future<({String note, int? days})?> askNote(
  BuildContext context, {
  required String title,
  required String confirm,
  bool askDays = false,
  String? hint,
  bool danger = false,
}) {
  final note = TextEditingController();
  final days = TextEditingController();
  String? error;
  return showDialog<({String note, int? days})>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: note,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: 'Note (required, saved in the audit log)',
                  hintText: hint,
                  errorText: error,
                ),
              ),
              if (askDays)
                TextField(
                  controller: days,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Days (leave empty for no end date)'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: const Color(0xFFD93636)) : null,
            onPressed: () {
              if (note.text.trim().length < 3) {
                set(() => error = 'Write at least a few words.');
                return;
              }
              Navigator.pop(c, (note: note.text.trim(), days: int.tryParse(days.text.trim())));
            },
            child: Text(confirm),
          ),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------------ overview

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.api, required this.onGo});
  final AdminApi api;

  /// Jump to another section by name.
  final void Function(String label) onGo;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Overview',
    subtitle: 'What needs attention right now.',
    children: [
      Loader<Overview>(
        load: api.overview,
        builder: (context, o, reload) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Tile('Open reports', o.n('open_reports'), Icons.flag_outlined, accent, () => onGo('Reports')),
                _Tile(
                  'Suspended',
                  o.n('suspended'),
                  Icons.pause_circle_outline,
                  const Color(0xFFFF8A3D),
                  () => onGo('Suspended accounts'),
                ),
                _Tile(
                  'Restricted',
                  o.n('restricted'),
                  Icons.do_not_disturb_on_outlined,
                  warnAmber,
                  () => onGo('Suspended accounts'),
                ),
                _Tile('Banned', o.n('banned'), Icons.block, const Color(0xFFFF4D4D), () => onGo('Suspended accounts')),
                _Tile(
                  'Removal pending',
                  o.n('removal_pending'),
                  Icons.schedule,
                  const Color(0xFFFF4D4D),
                  () => onGo('Suspended accounts'),
                ),
                _Tile('Open tickets', o.n('open_tickets'), Icons.support_agent_outlined, okGreen, () => onGo('Reports')),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Community',
              trailing: IconButton(onPressed: reload, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  StatTile(label: 'Total users', value: '${o.n('users_total')}'),
                  StatTile(label: 'Joined today', value: '${o.n('users_today')}'),
                  StatTile(label: 'Staff actions today', value: '${o.n('actions_today')}'),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, this.icon, this.color, this.onTap);
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: onTap,
    child: Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: hair),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 14),
          Text('$value', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
          Text(label, style: const TextStyle(color: muted, fontSize: 13.5)),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------------- reports

class ReportsQueuePage extends StatefulWidget {
  const ReportsQueuePage({super.key, required this.api, required this.isAdmin});
  final AdminApi api;
  final bool isAdmin;

  @override
  State<ReportsQueuePage> createState() => _ReportsQueuePageState();
}

class _ReportsQueuePageState extends State<ReportsQueuePage> {
  String _status = 'open';
  int _gen = 0;

  Future<void> _decide(
    ReportRow r,
    String decision, {
    String? restriction,
    bool days = false,
    required String title,
    required String confirm,
    bool danger = false,
  }) async {
    final a = await askNote(context, title: title, confirm: confirm, askDays: days, danger: danger);
    if (a == null || !mounted) return;
    try {
      await widget.api.decideReport(r.id, decision: decision, note: a.note, restriction: restriction, days: a.days);
      if (mounted) {
        setState(() => _gen++);
        toast(context, 'Saved.');
      }
    } on AdminException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _evidence(ReportRow r) async {
    final reason = await askNote(context, title: 'Open evidence', confirm: 'Open', hint: 'Why are you opening it?');
    if (reason == null || !mounted) return;
    try {
      final ev = await widget.api.openReportEvidence(r.id, reason.note);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Evidence · ${_words(r.reason)}'),
          content: SingleChildScrollView(child: SelectableText('$ev')),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
        ),
      );
    } on AdminException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Reports',
    subtitle: 'Review each report, then act. Every decision needs a note and is logged.',
    actions: [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'open', label: Text('Open')),
          ButtonSegment(value: 'closed', label: Text('Closed')),
          ButtonSegment(value: 'all', label: Text('All')),
        ],
        selected: {_status},
        onSelectionChanged: (s) => setState(() {
          _status = s.first;
          _gen++;
        }),
      ),
    ],
    children: [
      Loader<List<ReportRow>>(
        key: ValueKey('$_status$_gen'),
        load: () => widget.api.reports(status: _status),
        builder: (context, items, reload) => items.isEmpty
            ? const SectionCard(
                title: 'Nothing here',
                child: Text('All caught up.', style: TextStyle(color: muted)),
              )
            : Column(
                children: [
                  for (final r in items)
                    SectionCard(
                      title: '${r.reportNo ?? 'Report'} · ${_words(r.reason)}',
                      subtitle:
                          '${fmtDate(r.createdAt)} · ${r.reportCount} report(s) against this user'
                          '${r.reporterFalseReports > 0 ? ' · reporter has ${r.reporterFalseReports} false report(s)' : ''}',
                      trailing: StatusChip(
                        r.status == 'open' ? 'Open' : (r.decision ?? r.status).replaceAll('_', ' '),
                        color: r.status == 'open' ? warnAmber : okGreen,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((r.details ?? '').isNotEmpty)
                            Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(r.details!)),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (r.hasEvidence || r.evidenceFiles > 0)
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.attach_file, size: 18),
                                  onPressed: () => _evidence(r),
                                  label: Text('Evidence (${r.evidenceFiles})'),
                                ),
                              OutlinedButton(
                                onPressed: () => showUserSheet(context, widget.api, r.reportedId, widget.isAdmin),
                                child: const Text('View user'),
                              ),
                              if (r.status == 'open') ...[
                                OutlinedButton(
                                  onPressed: () => _decide(
                                    r,
                                    'warning_issued',
                                    restriction: 'warning',
                                    title: 'Warn this user',
                                    confirm: 'Send warning',
                                  ),
                                  child: const Text('Warn'),
                                ),
                                OutlinedButton(
                                  onPressed: () => _decide(
                                    r,
                                    'restricted',
                                    restriction: 'restricted',
                                    days: true,
                                    title: 'Restrict this account',
                                    confirm: 'Restrict',
                                  ),
                                  child: const Text('Restrict'),
                                ),
                                FilledButton(
                                  onPressed: () => _decide(
                                    r,
                                    'suspended',
                                    restriction: 'suspended',
                                    days: true,
                                    title: 'Suspend this account',
                                    confirm: 'Suspend',
                                  ),
                                  child: const Text('Suspend'),
                                ),
                                if (widget.isAdmin)
                                  FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD93636)),
                                    onPressed: () => _decide(
                                      r,
                                      'banned',
                                      restriction: 'banned',
                                      title: 'Ban this account',
                                      confirm: 'Ban',
                                      danger: true,
                                    ),
                                    child: const Text('Ban'),
                                  ),
                                OutlinedButton(
                                  onPressed: () => _decide(r, 'content_removed', title: 'Content removed', confirm: 'Save'),
                                  child: const Text('Content removed'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _decide(r, 'false_report', title: 'Mark as a false report', confirm: 'Mark false'),
                                  child: const Text('False report'),
                                ),
                                TextButton(
                                  onPressed: () => _decide(r, 'dismissed', title: 'Dismiss this report', confirm: 'Dismiss'),
                                  child: const Text('Dismiss'),
                                ),
                              ],
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

// --------------------------------------------------------------------- users

/// Opens a user's detail with every action their status allows.
Future<void> showUserSheet(BuildContext context, AdminApi api, String id, bool isAdmin, {VoidCallback? onChanged}) =>
    showDialog<void>(
      context: context,
      builder: (c) => _UserDialog(api: api, id: id, isAdmin: isAdmin, onChanged: onChanged),
    );

class _UserDialog extends StatefulWidget {
  const _UserDialog({required this.api, required this.id, required this.isAdmin, this.onChanged});
  final AdminApi api;
  final String id;
  final bool isAdmin;
  final VoidCallback? onChanged;
  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  late Future<UserDetail> _f = widget.api.userDetail(widget.id);

  Future<void> _act(
    String action, {
    required String title,
    required String confirm,
    bool days = false,
    bool danger = false,
    bool unsuspend = false,
  }) async {
    final a = await askNote(context, title: title, confirm: confirm, askDays: days, danger: danger);
    if (a == null || !mounted) return;
    try {
      if (unsuspend) {
        await widget.api.unsuspend(widget.id, note: a.note);
      } else {
        await widget.api.applyAction(widget.id, action, note: a.note, days: a.days);
      }
      widget.onChanged?.call();
      if (mounted) {
        setState(() => _f = widget.api.userDetail(widget.id));
        toast(context, 'Done.');
      }
    } on AdminException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: bg,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
      child: FutureBuilder<UserDetail>(
        future: _f,
        builder: (context, s) {
          if (s.hasError) {
            return Padding(padding: const EdgeInsets.all(24), child: Text('${s.error}'));
          }
          final u = s.data;
          if (u == null) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
          final st = u.status;
          final h = u.history;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 10, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(u.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                          Text(
                            '${u.m['age'] ?? '—'} · ${u.m['city'] ?? '—'} · ${u.m['gender'] ?? '—'} · joined ${fmtDate(DateTime.tryParse('${u.m['created_at']}')?.toLocal())}',
                            style: const TextStyle(color: muted),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(st),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 16),
                  children: [
                    SectionCard(
                      title: 'Contact (logged when opened)',
                      child: Text('${u.m['email'] ?? '—'}   ·   ${u.m['phone'] ?? '—'}'),
                    ),
                    if (st.isLimited)
                      SectionCard(
                        title: st.label,
                        child: Text(
                          [
                            for (final r in u.restrictions.where((r) => r['lifted_at'] == null).take(1)) '${r['reason']}',
                            if (u.m['deactivation_reason'] != null) '${u.m['deactivation_reason']}',
                            if (u.m['removal_due_at'] != null)
                              'Permanent removal after ${fmtDate(DateTime.tryParse('${u.m['removal_due_at']}')?.toLocal())}.',
                          ].join('\n'),
                        ),
                      ),
                    SectionCard(
                      title: 'History',
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          StatTile(label: 'Reports against', value: '${h['reports_against'] ?? 0}'),
                          StatTile(label: 'Upheld', value: '${h['reports_upheld'] ?? 0}'),
                          StatTile(label: 'Reports made', value: '${h['reports_made'] ?? 0}'),
                          StatTile(label: 'False reports made', value: '${h['false_reports_made'] ?? 0}'),
                        ],
                      ),
                    ),
                    if (u.actions.isNotEmpty)
                      SectionCard(
                        title: 'Staff actions',
                        child: Column(
                          children: [
                            for (final a in u.actions.take(10))
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(_words('${a['decision']}')),
                                subtitle: Text('${a['note'] ?? ''}'),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (st == AccountStatus.suspended ||
                        st == AccountStatus.deactivated ||
                        st == AccountStatus.restricted ||
                        (st == AccountStatus.banned && widget.isAdmin))
                      FilledButton.icon(
                        icon: const Icon(Icons.lock_open, size: 18),
                        onPressed: () => _act('', title: 'Unsuspend ${u.name}', confirm: 'Unsuspend', unsuspend: true),
                        label: const Text('Unsuspend'),
                      ),
                    if (st == AccountStatus.removalPending && widget.isAdmin)
                      FilledButton(
                        onPressed: () => _act('cancel_removal', title: 'Cancel the removal', confirm: 'Cancel removal'),
                        child: const Text('Cancel removal'),
                      ),
                    if (st == AccountStatus.active || st == AccountStatus.restricted) ...[
                      OutlinedButton(
                        onPressed: () => _act('warning', title: 'Warn ${u.name}', confirm: 'Send warning'),
                        child: const Text('Warn'),
                      ),
                      OutlinedButton(
                        onPressed: () => _act('restricted', title: 'Restrict ${u.name}', confirm: 'Restrict', days: true),
                        child: const Text('Restrict'),
                      ),
                    ],
                    if (st == AccountStatus.active || st == AccountStatus.restricted)
                      FilledButton(
                        onPressed: () => _act('suspended', title: 'Suspend ${u.name}', confirm: 'Suspend', days: true),
                        child: const Text('Suspend'),
                      ),
                    if (st == AccountStatus.active || st == AccountStatus.restricted || st == AccountStatus.suspended)
                      OutlinedButton(
                        onPressed: () => _act('deactivate', title: 'Deactivate ${u.name}', confirm: 'Deactivate'),
                        child: const Text('Deactivate'),
                      ),
                    if (widget.isAdmin && st != AccountStatus.banned && st != AccountStatus.removalPending)
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD93636)),
                        onPressed: () => _act('banned', title: 'Ban ${u.name}', confirm: 'Ban', danger: true),
                        child: const Text('Ban'),
                      ),
                    if (widget.isAdmin && st != AccountStatus.removalPending)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF6B6B)),
                        onPressed: () => _act('remove', title: 'Remove ${u.name}', confirm: 'Remove (30 days)', danger: true),
                        child: const Text('Remove'),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class UsersPage extends StatefulWidget {
  const UsersPage({super.key, required this.api, required this.isAdmin});
  final AdminApi api;
  final bool isAdmin;
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _q = TextEditingController();
  String _status = 'all';
  int _gen = 0;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Users',
    subtitle: 'Search by name, email, phone number or user ID.',
    children: [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: 340,
            child: TextField(
              controller: _q,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search users'),
              onSubmitted: (_) => setState(() => _gen++),
            ),
          ),
          DropdownButton<String>(
            value: _status,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All statuses')),
              DropdownMenuItem(value: 'active', child: Text('Active')),
              DropdownMenuItem(value: 'restricted', child: Text('Restricted')),
              DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
              DropdownMenuItem(value: 'deactivated', child: Text('Deactivated')),
              DropdownMenuItem(value: 'banned', child: Text('Banned')),
              DropdownMenuItem(value: 'removal_pending', child: Text('Removal pending')),
            ],
            onChanged: (v) => setState(() {
              _status = v ?? 'all';
              _gen++;
            }),
          ),
          FilledButton(onPressed: () => setState(() => _gen++), child: const Text('Search')),
        ],
      ),
      const SizedBox(height: 16),
      Loader<List<UserRow>>(
        key: ValueKey(_gen),
        load: () => widget.api.searchUsers(query: _q.text, status: _status),
        builder: (context, rows, reload) => rows.isEmpty
            ? const SectionCard(
                title: 'No users found',
                child: Text('Try another search.', style: TextStyle(color: muted)),
              )
            : Card(
                child: Column(
                  children: [
                    for (final (i, u) in rows.indexed) ...[
                      if (i > 0) const Divider(),
                      ListTile(
                        onTap: () => showUserSheet(context, widget.api, u.id, widget.isAdmin, onChanged: reload),
                        leading: CircleAvatar(backgroundColor: hair, child: Text(u.name.isEmpty ? '?' : u.name[0].toUpperCase())),
                        title: Row(
                          children: [
                            Flexible(child: Text(u.name, overflow: TextOverflow.ellipsis)),
                            if (u.verified)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(Icons.verified, size: 16, color: accent),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          '${u.age ?? '—'} · ${u.city ?? '—'} · joined ${fmtDate(u.createdAt).split(' ').first}${u.reportsAgainst > 0 ? ' · ${u.reportsAgainst} report(s)' : ''}',
                        ),
                        trailing: StatusBadge(u.status),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    ],
  );
}

// ------------------------------------------------------- suspended accounts

class SuspendedPage extends StatefulWidget {
  const SuspendedPage({super.key, required this.api, required this.isAdmin});
  final AdminApi api;
  final bool isAdmin;
  @override
  State<SuspendedPage> createState() => _SuspendedPageState();
}

class _SuspendedPageState extends State<SuspendedPage> {
  String _status = 'all';
  int _gen = 0;

  Future<void> _unsuspend(RestrictedRow r) async {
    final a = await askNote(
      context,
      title: 'Unsuspend ${r.name}',
      confirm: 'Unsuspend',
      hint: 'Why is this account being restored?',
    );
    if (a == null || !mounted) return;
    try {
      if (r.status == AccountStatus.removalPending) {
        await widget.api.applyAction(r.userId, 'cancel_removal', note: a.note);
      } else {
        await widget.api.unsuspend(r.userId, note: a.note);
      }
      if (mounted) {
        setState(() => _gen++);
        toast(context, '${r.name} is active again.');
      }
    } on AdminException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Suspended accounts',
    subtitle: 'Everyone currently limited. Unsuspend restores the account at once and notifies the person.',
    actions: [
      DropdownButton<String>(
        value: _status,
        items: const [
          DropdownMenuItem(value: 'all', child: Text('All')),
          DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
          DropdownMenuItem(value: 'restricted', child: Text('Restricted')),
          DropdownMenuItem(value: 'deactivated', child: Text('Deactivated')),
          DropdownMenuItem(value: 'banned', child: Text('Banned')),
          DropdownMenuItem(value: 'removal_pending', child: Text('Removal pending')),
        ],
        onChanged: (v) => setState(() {
          _status = v ?? 'all';
          _gen++;
        }),
      ),
    ],
    children: [
      Loader<List<RestrictedRow>>(
        key: ValueKey('$_status$_gen'),
        load: () => widget.api.restricted(status: _status),
        builder: (context, rows, reload) => rows.isEmpty
            ? const SectionCard(
                title: 'No limited accounts',
                child: Text('Nobody is suspended right now.', style: TextStyle(color: muted)),
              )
            : Column(
                children: [
                  for (final r in rows)
                    SectionCard(
                      title: r.name,
                      subtitle:
                          '${r.reason ?? 'No reason recorded'}'
                          '${r.reportNo != null ? ' · ${r.reportNo}' : ''}',
                      trailing: StatusBadge(r.status),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Since ${fmtDate(r.since)}', style: const TextStyle(color: muted)),
                          Text(
                            r.removalDue != null
                                ? 'Removal on ${fmtDate(r.removalDue)}'
                                : (r.until == null ? 'No end date' : 'Ends ${fmtDate(r.until)}'),
                            style: const TextStyle(color: muted),
                          ),
                          if (r.by != null) Text('By ${r.by}', style: const TextStyle(color: muted)),
                          OutlinedButton(
                            onPressed: () => showUserSheet(
                              context,
                              widget.api,
                              r.userId,
                              widget.isAdmin,
                              onChanged: () => setState(() => _gen++),
                            ),
                            child: const Text('Details'),
                          ),
                          if (r.status != AccountStatus.banned && (r.status != AccountStatus.removalPending || widget.isAdmin) ||
                              widget.isAdmin)
                            FilledButton.icon(
                              icon: const Icon(Icons.lock_open, size: 18),
                              onPressed: () => _unsuspend(r),
                              label: Text(r.status == AccountStatus.removalPending ? 'Cancel removal' : 'Unsuspend'),
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

// --------------------------------------------------------------- audit & staff

class AuditPage extends StatelessWidget {
  const AuditPage({super.key, required this.api});
  final AdminApi api;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Audit log',
    subtitle: 'Every staff action and every time private data was opened. Cannot be edited or deleted.',
    children: [
      Loader<List<AuditRow>>(
        load: api.auditLog,
        builder: (context, rows, reload) => rows.isEmpty
            ? const SectionCard(
                title: 'Nothing yet',
                child: Text('Actions will appear here.', style: TextStyle(color: muted)),
              )
            : Card(
                child: Column(
                  children: [
                    for (final (i, a) in rows.indexed) ...[
                      if (i > 0) const Divider(),
                      ListTile(
                        dense: true,
                        title: Text('${_words(a.action)} · ${a.target}'),
                        subtitle: Text(
                          '${a.actor ?? 'staff'} · ${fmtDate(a.at)}${(a.reason ?? '').isEmpty ? '' : '\n${a.reason}'}',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    ],
  );
}

class StaffPage extends StatefulWidget {
  const StaffPage({super.key, required this.api});
  final AdminApi api;
  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  final _email = TextEditingController();
  String _role = 'moderator';
  int _gen = 0;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _set(String email, String? role) async {
    try {
      await widget.api.setStaff(email, role);
      if (mounted) {
        setState(() => _gen++);
        _email.clear();
        toast(context, role == null ? 'Removed.' : 'Saved.');
      }
    } on AdminException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Staff',
    subtitle: 'Moderators warn, restrict, suspend and unsuspend. Admins can also ban, remove and manage staff.',
    children: [
      SectionCard(
        title: 'Add or change a staff member',
        subtitle: 'They need a Vouby account already. Two-step verification is required to sign in.',
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Account email'),
              ),
            ),
            DropdownButton<String>(
              value: _role,
              items: const [
                DropdownMenuItem(value: 'moderator', child: Text('Moderator')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: (v) => setState(() => _role = v ?? 'moderator'),
            ),
            FilledButton(onPressed: () => _set(_email.text.trim(), _role), child: const Text('Save')),
          ],
        ),
      ),
      Loader<List<StaffRow>>(
        key: ValueKey(_gen),
        load: widget.api.staff,
        builder: (context, rows, reload) => Card(
          child: Column(
            children: [
              for (final (i, s) in rows.indexed) ...[
                if (i > 0) const Divider(),
                ListTile(
                  title: Text(s.email ?? s.userId),
                  subtitle: Text(s.role),
                  trailing: TextButton(onPressed: () => _set(s.email ?? '', null), child: const Text('Remove')),
                ),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}
