import 'package:flutter/material.dart';

import 'api.dart';
import 'pages/data_migration.dart';
import 'pages/integrations.dart';
import 'pages/safety.dart';
import 'ui.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.group, this.adminOnly, this.build);
  final String label;
  final IconData icon;
  final String group;
  final bool adminOnly;
  final Widget Function(AdminApi api) build;
}

final _dests = <_Dest>[
  _Dest('Overview', Icons.shield_outlined, 'Safety', false, (a) => SecurityPage(api: a)),
  _Dest('Reports', Icons.flag_outlined, 'Safety', false, (a) => ReportsPage(api: a)),
  _Dest('Photo review', Icons.image_outlined, 'Safety', false, (a) => MediaReviewPage(api: a)),
  _Dest('Verification', Icons.verified_outlined, 'Safety', false, (a) => VerificationPage(api: a)),
  _Dest('Database & Data Migration', Icons.storage_outlined, 'Settings', true, (a) => DataMigrationPage(api: a)),
  _Dest('Integrations & credentials', Icons.key_outlined, 'Settings', true, (a) => IntegrationsPage(api: a)),
];

/// Sidebar on wide screens, drawer on narrow ones. Settings pages are for
/// admins; moderators see Safety only (the database enforces this too).
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.api, required this.isAdmin});
  final AdminApi api;
  final bool isAdmin;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _i = 0;

  List<_Dest> get _visible => [
    for (final d in _dests)
      if (widget.isAdmin || !d.adminOnly) d,
  ];

  Widget _nav(BuildContext context, {required bool inDrawer}) {
    final items = _visible;
    String? group;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 4, 12, 16),
          child: Text('Vouby admin', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
        for (final (i, d) in items.indexed) ...[
          if (d.group != group) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
              child: Text(
                (group = d.group).toUpperCase(),
                style: const TextStyle(color: muted, fontSize: 11.5, letterSpacing: 1, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          ListTile(
            dense: true,
            selected: i == _i,
            selectedTileColor: accent.withValues(alpha: 0.12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: Icon(d.icon, size: 20),
            title: Text(d.label),
            onTap: () {
              setState(() => _i = i);
              if (inDrawer) Navigator.pop(context);
            },
          ),
        ],
        const Divider(height: 32),
        ListTile(
          dense: true,
          leading: const Icon(Icons.logout, size: 20),
          title: Text(widget.api.email ?? 'Sign out', overflow: TextOverflow.ellipsis),
          subtitle: const Text('Sign out'),
          onTap: widget.api.signOut,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final dest = _visible[_i.clamp(0, _visible.length - 1)];
    final body = Column(
      children: [
        if (widget.api.isDemo)
          Container(
            width: double.infinity,
            color: warnAmber.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text(
              'Sample data preview — not connected to the live database.',
              style: TextStyle(color: warnAmber, fontWeight: FontWeight.w600),
            ),
          ),
        Expanded(
          child: KeyedSubtree(key: ValueKey(dest.label), child: dest.build(widget.api)),
        ),
      ],
    );
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 270,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: hair)),
                ),
                child: _nav(context, inDrawer: false),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(dest.label), backgroundColor: bg),
      drawer: Drawer(
        backgroundColor: bg,
        child: SafeArea(child: _nav(context, inDrawer: true)),
      ),
      body: body,
    );
  }
}
