import 'package:flutter/material.dart';

import '../api.dart';
import '../csv.dart';
import '../download.dart';
import '../generated/migrations.g.dart';
import '../models.dart';
import '../ui.dart';

/// Settings → Database & Data Migration.
/// Read-only view of schema versions, pending migrations and data counts, plus
/// profile-update progress with a reminder button. Schema changes are deployed
/// only through versioned migrations (docs/MIGRATIONS.md); there's
/// deliberately no reset or delete control here.
class DataMigrationPage extends StatefulWidget {
  const DataMigrationPage({super.key, required this.api});
  final AdminApi api;

  @override
  State<DataMigrationPage> createState() => _DataMigrationPageState();
}

class _DataMigrationPageState extends State<DataMigrationPage> {
  late Future<(SchemaStatus, List<RequirementStats>, List<TableCount>)> _data = _load();

  Future<(SchemaStatus, List<RequirementStats>, List<TableCount>)> _load() async {
    final r = await Future.wait([widget.api.schemaStatus(), widget.api.requirementStats(), widget.api.dataSnapshot()]);
    return (r[0] as SchemaStatus, r[1] as List<RequirementStats>, r[2] as List<TableCount>);
  }

  void _reload() => setState(() {
    _data = _load();
  });

  void _export(SchemaStatus schema, List<RequirementStats> reqs, List<TableCount> counts) {
    final rows = <List<Object?>>[
      ['section', 'id', 'description', 'status', 'applied_at', 'tables', 'columns_added', 'error'],
      for (final m in repoMigrations)
        [
          'migration',
          m.id,
          m.description,
          schema.isApplied(m.id) ? 'applied' : 'pending',
          schema.changeLog.where((l) => l.id == m.id).firstOrNull?.appliedAt,
          m.tables,
          m.columns,
          schema.changeLog.where((l) => l.id == m.id).firstOrNull?.error,
        ],
      [],
      [
        'section',
        'key',
        'label',
        'level',
        'introduced_by',
        'users_total',
        'pending',
        'completed',
        'dismissed',
        'affected_at_intro',
      ],
      for (final r in reqs)
        [
          'profile_update',
          r.key,
          r.label,
          r.level,
          r.introducedBy,
          r.usersTotal,
          r.pending,
          r.completed,
          r.dismissed,
          r.affectedAtIntro,
        ],
      [],
      ['section', 'table', 'rows', 'key_checksum'],
      for (final c in counts) ['table', c.table, c.rows, c.checksum],
    ];
    final stamp = DateTime.now().toUtc().toIso8601String().substring(0, 19).replaceAll(':', '');
    final ok = downloadText('vouby-migration-status-$stamp.csv', toCsv(rows));
    toast(context, ok ? 'Exported migration status (CSV).' : 'Export works in the browser.');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _data,
    builder: (context, s) {
      if (s.hasError) {
        return PageFrame(
          title: 'Database & Data Migration',
          children: [
            SectionCard(
              title: 'Couldn’t load',
              child: Row(
                children: [
                  Expanded(
                    child: Text('${s.error}', style: const TextStyle(color: muted)),
                  ),
                  TextButton(onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            ),
          ],
        );
      }
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final (schema, reqs, counts) = s.data!;
      final pending = [
        for (final m in repoMigrations)
          if (!schema.isApplied(m.id)) m,
      ];
      final failed = schema.changeLog.where((m) => m.status == 'failed').toList();
      final latest = schema.changeLog.isEmpty ? null : schema.changeLog.last;
      return PageFrame(
        title: 'Database & Data Migration',
        subtitle: 'Schema versions, pending migrations and profile updates. Existing data is never reset or deleted here.',
        actions: [
          OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh')),
          FilledButton.icon(
            onPressed: () => _export(schema, reqs, counts),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Export CSV'),
          ),
        ],
        children: [
          SectionCard(
            title: 'Schema',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                StatTile(label: 'Schema version', value: latest?.id.split('_').first ?? '—'),
                StatTile(label: 'Applied migrations', value: '${schema.changeLog.length}'),
                StatTile(label: 'Pending migrations', value: '${pending.length}', color: pending.isEmpty ? okGreen : warnAmber),
                StatTile(label: 'Failed', value: '${failed.length}', color: failed.isEmpty ? okGreen : accent),
              ],
            ),
          ),
          if (pending.isNotEmpty)
            SectionCard(
              title: 'Pending migrations',
              subtitle:
                  'In the code but not yet applied to this database. Deploy with the runbook: '
                  'backup check → supabase db push → tool/verify_migration.sh.',
              child: Column(children: [for (final m in pending) _RepoMigrationTile(m)]),
            ),
          SectionCard(
            title: 'Profile updates',
            subtitle: 'Details introduced after launch. Only users missing them are asked; existing data is never changed.',
            child: reqs.isEmpty
                ? const Text('No profile updates registered.', style: TextStyle(color: muted))
                : Column(
                    children: [
                      for (final r in reqs)
                        _RequirementTile(
                          r,
                          onRemind: () async {
                            try {
                              await widget.api.sendReminder(r.key);
                              if (context.mounted) {
                                toast(
                                  context,
                                  'Reminder sent: users still missing ${r.label} see the prompt on their next visit.',
                                );
                              }
                              _reload();
                            } on AdminException catch (e) {
                              if (context.mounted) toast(context, e.message);
                            }
                          },
                        ),
                    ],
                  ),
          ),
          SectionCard(
            title: 'Applied migrations',
            subtitle: latest == null ? null : 'Latest: ${latest.id} · ${fmtDate(latest.appliedAt)}',
            child: Column(
              children: [
                for (final m in schema.changeLog.reversed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      m.status == 'failed' ? Icons.error_outline : Icons.check_circle_outline,
                      color: m.status == 'failed' ? accent : okGreen,
                    ),
                    title: Text(m.id, style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5)),
                    subtitle: Text(
                      [
                        m.description,
                        if (m.tables.isNotEmpty) 'Tables: ${m.tables.join(', ')}',
                        if (m.columnsAdded.isNotEmpty) 'Columns added: ${m.columnsAdded.join(', ')}',
                        if (m.error != null) 'Error: ${m.error}',
                      ].join('\n'),
                    ),
                    trailing: Text(fmtDate(m.appliedAt), style: const TextStyle(color: muted, fontSize: 12.5)),
                  ),
              ],
            ),
          ),
          SectionCard(
            title: 'Data snapshot',
            subtitle: 'Row counts now. Compare before and after a migration with tool/verify_migration.sh.',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [for (final c in counts) StatTile(label: c.table, value: '${c.rows}')],
            ),
          ),
        ],
      );
    },
  );
}

class _RepoMigrationTile extends StatelessWidget {
  const _RepoMigrationTile(this.m);
  final RepoMigration m;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    leading: const Icon(Icons.schedule, color: warnAmber),
    title: Text(m.id, style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5)),
    subtitle: Text(m.description, maxLines: 2, overflow: TextOverflow.ellipsis),
    childrenPadding: const EdgeInsets.only(left: 40, bottom: 12),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (k, v) in [
        ('Tables', m.tables),
        ('Columns added', m.columns),
        ('Backward compatibility', m.compat),
        ('Recovery', m.recovery),
        ('User information', m.userData),
      ])
        if (v.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$k: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: v),
                ],
              ),
            ),
          ),
    ],
  );
}

class _RequirementTile extends StatelessWidget {
  const _RequirementTile(this.r, {required this.onRemind});
  final RequirementStats r;
  final VoidCallback onRemind;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(r.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            StatusChip(switch (r.level) {
              'required' => 'Required',
              'feature' => 'Needed for ${r.gatedFeature}',
              _ => 'Optional',
            }, color: r.level == 'optional' ? muted : warnAmber),
            if (!r.active) const StatusChip('Inactive', color: muted),
            Text('since ${r.introducedBy.split('_').first}', style: const TextStyle(color: muted, fontSize: 12.5)),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(value: r.completion, minHeight: 8, color: okGreen, backgroundColor: hair),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatTile(label: 'Affected when introduced', value: r.affectedAtIntro?.toString() ?? '—'),
            StatTile(label: 'Completed', value: '${r.completed}', color: okGreen),
            StatTile(label: 'Still pending', value: '${r.pending}', color: r.pending == 0 ? okGreen : warnAmber),
            StatTile(label: 'Skipped (optional)', value: '${r.dismissed}'),
            OutlinedButton.icon(
              onPressed: r.pending == 0 ? null : onRemind,
              icon: const Icon(Icons.notifications_active_outlined, size: 18),
              label: Text(r.reminderSentAt == null ? 'Send reminder' : 'Remind again (last ${fmtDate(r.reminderSentAt)})'),
            ),
          ],
        ),
      ],
    ),
  );
}
