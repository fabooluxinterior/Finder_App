import 'package:flutter/material.dart';

import '../api.dart';
import '../models_mod.dart';
import '../ui.dart';

const _statuses = ['new', 'open', 'assigned', 'in_progress', 'waiting_for_user', 'escalated', 'resolved', 'closed'];
const _categories = ['account', 'profile', 'discovery', 'chat', 'subscription', 'privacy', 'safety', 'technical', 'other'];
const _priorities = ['low', 'normal', 'high', 'urgent'];

String statusLabel(String s) => switch (s) {
  'new' => 'New',
  'open' => 'Open',
  'assigned' => 'Assigned',
  'in_progress' => 'In progress',
  'waiting_for_user' => 'Waiting for user',
  'escalated' => 'Escalated',
  'resolved' => 'Resolved',
  'closed' => 'Closed',
  _ => s,
};
String categoryLabel(String c) => switch (c) {
  'account' => 'Account & Login',
  'profile' => 'Profile & Verification',
  'discovery' => 'Matches & Likes',
  'chat' => 'Chat & Messages',
  'subscription' => 'Payments & Subscription',
  'privacy' => 'Privacy & Security',
  'safety' => 'Safety & Reporting',
  'technical' => 'Technical Issues',
  _ => 'Other',
};
Color statusColor(String s) => switch (s) {
  'new' => accent,
  'open' || 'assigned' => const Color(0xFF3D9BFF),
  'in_progress' => const Color(0xFFFF8A3D),
  'waiting_for_user' => warnAmber,
  'escalated' => const Color(0xFFFF4D4D),
  _ => okGreen,
};
Color priorityColor(String p) => switch (p) {
  'urgent' => const Color(0xFFFF4D4D),
  'high' => const Color(0xFFFF8A3D),
  'low' => muted,
  _ => const Color(0xFF8A8A93),
};

// =================================================================== tickets

class SupportPage extends StatefulWidget {
  const SupportPage({super.key, required this.api});
  final AdminApi api;
  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final _q = TextEditingController();
  String _status = 'active';
  String _category = 'all';
  String _priority = 'all';
  int _gen = 0;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _gen++);

  Widget _count(String label, int? n, String status, Color color) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: () => setState(() {
      _status = status;
      _gen++;
    }),
    child: StatTile(label: label, value: '${n ?? 0}', color: _status == status ? color : null),
  );

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Support tickets',
    subtitle: 'Reply to users, add internal notes, assign, escalate and close. Replies appear in the user’s Help chat.',
    actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
    children: [
      Loader<Map<String, int>>(
        key: ValueKey('c$_gen'),
        load: widget.api.ticketCounts,
        builder: (context, c, _) => Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _count('Total tickets', c['total'], 'all', accent),
            _count('New', c['new'], 'new', accent),
            _count('Open', c['open'], 'open', const Color(0xFF3D9BFF)),
            _count('In progress', c['in_progress'], 'in_progress', const Color(0xFFFF8A3D)),
            _count('Waiting for user', c['waiting_for_user'], 'waiting_for_user', warnAmber),
            _count('Escalated', c['escalated'], 'escalated', const Color(0xFFFF4D4D)),
            _count('Resolved', c['resolved'], 'resolved', okGreen),
            _count('Closed', c['closed'], 'closed', okGreen),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: _q,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Ticket ID or username'),
              onSubmitted: (_) => _refresh(),
            ),
          ),
          _Drop(
            'Status',
            _status,
            const ['active', 'all', ..._statuses],
            statusLabelOrAll,
            (v) => setState(() {
              _status = v;
              _gen++;
            }),
          ),
          _Drop(
            'Category',
            _category,
            const ['all', ..._categories],
            (v) => v == 'all' ? 'All categories' : categoryLabel(v),
            (v) => setState(() {
              _category = v;
              _gen++;
            }),
          ),
          _Drop(
            'Priority',
            _priority,
            const ['all', ..._priorities],
            (v) => v == 'all' ? 'All priorities' : '${v[0].toUpperCase()}${v.substring(1)}',
            (v) => setState(() {
              _priority = v;
              _gen++;
            }),
          ),
          FilledButton(onPressed: _refresh, child: const Text('Search')),
        ],
      ),
      const SizedBox(height: 16),
      Loader<List<TicketRow>>(
        key: ValueKey('l$_gen'),
        load: () => widget.api.tickets(status: _status, category: _category, priority: _priority, query: _q.text),
        builder: (context, rows, reload) => rows.isEmpty
            ? const SectionCard(
                title: 'No tickets',
                child: Text('Nothing matches.', style: TextStyle(color: muted)),
              )
            : Card(
                child: Column(
                  children: [
                    for (final (i, t) in rows.indexed) ...[
                      if (i > 0) const Divider(),
                      ListTile(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => TicketDialog(api: widget.api, ticketId: t.id, onChanged: _refresh),
                        ),
                        title: Row(
                          children: [
                            Flexible(child: Text('${t.ticketNo} · ${t.subject}', overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 8),
                            if (t.priority == 'urgent' || t.priority == 'high')
                              StatusChip(t.priority, color: priorityColor(t.priority)),
                          ],
                        ),
                        subtitle: Text(
                          '${t.userName ?? 'Unknown'} · ${categoryLabel(t.category)} · ${fmtDate(t.updatedAt)}${t.assignee == null ? '' : ' · ${t.assignee}'}',
                        ),
                        trailing: StatusChip(statusLabel(t.status), color: statusColor(t.status)),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    ],
  );
}

String statusLabelOrAll(String v) => v == 'all' ? 'All statuses' : (v == 'active' ? 'Not resolved' : statusLabel(v));

class _Drop extends StatelessWidget {
  const _Drop(this.label, this.value, this.items, this.text, this.onChanged);
  final String label;
  final String value;
  final List<String> items;
  final String Function(String) text;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButton<String>(
    value: value,
    hint: Text(label),
    items: [for (final i in items) DropdownMenuItem(value: i, child: Text(text(i)))],
    onChanged: (v) => onChanged(v ?? value),
  );
}

class TicketDialog extends StatefulWidget {
  const TicketDialog({super.key, required this.api, required this.ticketId, required this.onChanged});
  final AdminApi api;
  final String ticketId;
  final VoidCallback onChanged;
  @override
  State<TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends State<TicketDialog> {
  final _reply = TextEditingController();
  final _note = TextEditingController();
  late Future<TicketDetail> _f = widget.api.ticketDetail(widget.ticketId);
  late final Future<List<StaffPerson>> _staff = widget.api.staffPeople();
  bool _busy = false;
  bool _showBot = false;

  @override
  void dispose() {
    _reply.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _do(Future<void> Function() body, {String? done}) async {
    setState(() => _busy = true);
    try {
      await body();
      widget.onChanged();
      if (mounted) {
        setState(() => _f = widget.api.ticketDetail(widget.ticketId));
        if (done != null) toast(context, done);
      }
    } on AdminException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _escalate() async {
    final ctl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Escalate this ticket'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Why? (internal)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Escalate')),
        ],
      ),
    );
    if (note == null) return;
    await _do(() => widget.api.escalateTicket(widget.ticketId, note), done: 'Escalated.');
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: bg,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
      child: FutureBuilder<TicketDetail>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) return Padding(padding: const EdgeInsets.all(24), child: Text('${snap.error}'));
          final d = snap.data;
          if (d == null) return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
          final t = d.ticket;
          final status = t['status'] as String;
          final priority = (t['priority'] as String?) ?? 'normal';
          final u = d.user;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 10, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${t['ticket_no']} · ${t['subject']}',
                            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${categoryLabel('${t['category']}')} · opened ${fmtDate(DateTime.tryParse('${t['created_at']}')?.toLocal())}',
                            style: const TextStyle(color: muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
                  children: [
                    SectionCard(
                      title: 'User',
                      child: Text(
                        '${u['name'] ?? 'Unknown'} · ${u['email'] ?? 'no email'} · ${u['city'] ?? ''} · account ${u['status'] ?? 'active'}\nApp: ${t['app_version'] ?? '—'} · Device: ${t['device_info'] ?? '—'}',
                      ),
                    ),
                    SectionCard(
                      title: 'Conversation',
                      child: Column(
                        children: [
                          for (final m in d.thread)
                            Align(
                              alignment: m.fromStaff ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                constraints: const BoxConstraints(maxWidth: 440),
                                decoration: BoxDecoration(
                                  color: m.fromStaff ? accent.withValues(alpha: 0.18) : surface,
                                  border: Border.all(color: hair),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.body),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${m.fromStaff ? 'Team' : (u['name'] ?? 'User')} · ${fmtDate(m.at)}',
                                      style: const TextStyle(color: muted, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _reply,
                            minLines: 2,
                            maxLines: 5,
                            maxLength: 2000,
                            decoration: const InputDecoration(labelText: 'Reply to the user (they see this)'),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final body = _reply.text;
                                      await _do(() => widget.api.replyTicket(widget.ticketId, body), done: 'Reply sent.');
                                      _reply.clear();
                                    },
                              child: const Text('Send reply'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SectionCard(
                      title: 'Internal notes (only staff see these)',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final n in d.notes)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('${n['body']}'),
                              subtitle: Text(
                                '${n['author'] ?? 'staff'} · ${fmtDate(DateTime.tryParse('${n['at']}')?.toLocal())}',
                              ),
                            ),
                          TextField(
                            controller: _note,
                            minLines: 1,
                            maxLines: 3,
                            decoration: const InputDecoration(labelText: 'Add an internal note'),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final body = _note.text;
                                      await _do(() => widget.api.addTicketNote(widget.ticketId, body), done: 'Note added.');
                                      _note.clear();
                                    },
                              child: const Text('Add note'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SectionCard(
                      title: 'Chatbot conversation',
                      trailing: TextButton(
                        onPressed: () => setState(() => _showBot = !_showBot),
                        child: Text(_showBot ? 'Hide' : 'Show'),
                      ),
                      child: !_showBot
                          ? Text(
                              d.bot.isEmpty
                                  ? 'No chatbot conversation was attached.'
                                  : '${d.bot.length} messages before the ticket was raised.',
                              style: const TextStyle(color: muted),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final m in d.bot)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text('${m['mine'] == true ? 'User' : 'Bot'}: ${m['text']}'),
                                  ),
                              ],
                            ),
                    ),
                    SectionCard(
                      title: 'History',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final h in d.history)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                '${fmtDate(DateTime.tryParse('${h['at']}')?.toLocal())} · ${statusLabel('${h['status']}')}${h['note'] == null ? '' : ' · ${h['note']}'}${h['actor'] == null ? '' : ' · ${h['actor']}'}',
                                style: const TextStyle(color: muted, fontSize: 13),
                              ),
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
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Drop(
                      'Status',
                      status,
                      _statuses,
                      statusLabel,
                      (v) => _do(() => widget.api.setTicketStatus(widget.ticketId, v), done: 'Status updated.'),
                    ),
                    _Drop(
                      'Priority',
                      priority,
                      _priorities,
                      (v) => '${v[0].toUpperCase()}${v.substring(1)} priority',
                      (v) => _do(() => widget.api.setTicketPriority(widget.ticketId, v), done: 'Priority updated.'),
                    ),
                    FutureBuilder<List<StaffPerson>>(
                      future: _staff,
                      builder: (context, s) {
                        final people = s.data ?? const <StaffPerson>[];
                        final current = t['assigned_to'] as String?;
                        return DropdownButton<String?>(
                          value: people.any((p) => p.userId == current) ? current : null,
                          hint: const Text('Assign to'),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
                            for (final p in people) DropdownMenuItem<String?>(value: p.userId, child: Text(p.email ?? p.userId)),
                          ],
                          onChanged: (v) => _do(
                            () => widget.api.assignTicket(widget.ticketId, v),
                            done: v == null ? 'Unassigned.' : 'Assigned.',
                          ),
                        );
                      },
                    ),
                    OutlinedButton(onPressed: status == 'escalated' ? null : _escalate, child: const Text('Escalate')),
                    OutlinedButton(
                      onPressed: status == 'resolved'
                          ? null
                          : () => _do(() => widget.api.setTicketStatus(widget.ticketId, 'resolved'), done: 'Resolved.'),
                      child: const Text('Resolve'),
                    ),
                    TextButton(
                      onPressed: status == 'closed'
                          ? null
                          : () => _do(() => widget.api.setTicketStatus(widget.ticketId, 'closed'), done: 'Closed.'),
                      child: const Text('Close'),
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

// ============================================================ auto-reply management

class AutoReplyPage extends StatefulWidget {
  const AutoReplyPage({super.key, required this.api});
  final AdminApi api;
  @override
  State<AutoReplyPage> createState() => _AutoReplyPageState();
}

class _AutoReplyPageState extends State<AutoReplyPage> {
  int _gen = 0;
  void _refresh() => setState(() => _gen++);

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Auto-replies',
    subtitle: 'What the Help chatbot says. Changes reach the app straight away.',
    actions: [
      OutlinedButton.icon(
        icon: const Icon(Icons.forum_outlined, size: 18),
        label: const Text('Chatbot conversations'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _ConversationsDialog(api: widget.api),
        ),
      ),
      FilledButton.icon(
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add reply'),
        onPressed: () async {
          if (await showDialog<bool>(
                context: context,
                builder: (_) => _ReplyDialog(api: widget.api),
              ) ==
              true) {
            _refresh();
          }
        },
      ),
    ],
    children: [
      Loader<BotOverview>(
        key: ValueKey(_gen),
        load: widget.api.botOverview,
        builder: (context, o, reload) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SettingsCard(api: widget.api, settings: o.settings, onSaved: _refresh),
            for (final cat in _categories.where((c) => o.replies.any((r) => r.category == c)))
              SectionCard(
                title: categoryLabel(cat),
                child: Column(
                  children: [
                    for (final r in o.replies.where((r) => r.category == cat))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(r.title, style: TextStyle(color: r.active ? null : muted)),
                        subtitle: Text(
                          '${r.answer}\nKeywords: ${r.keywords.isEmpty ? '—' : r.keywords.join(', ')}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        leading: Switch(
                          value: r.active,
                          onChanged: (v) async {
                            await widget.api.botSaveReply(
                              id: r.id,
                              category: r.category,
                              title: r.title,
                              keywords: r.keywords,
                              answer: r.answer,
                              active: v,
                              sort: r.sort,
                            );
                            _refresh();
                          },
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () async {
                                if (await showDialog<bool>(
                                      context: context,
                                      builder: (_) => _ReplyDialog(api: widget.api, reply: r),
                                    ) ==
                                    true) {
                                  _refresh();
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Delete this reply?'),
                                    content: Text(r.title),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
                                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await widget.api.botDeleteReply(r.id);
                                  _refresh();
                                }
                              },
                            ),
                          ],
                        ),
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

class _SettingsCard extends StatefulWidget {
  const _SettingsCard({required this.api, required this.settings, required this.onSaved});
  final AdminApi api;
  final BotSettings settings;
  final VoidCallback onSaved;
  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
  late bool _enabled = widget.settings.enabled;
  late final _welcome = TextEditingController(text: widget.settings.welcome);
  late final _fallback = TextEditingController(text: widget.settings.fallback);
  late final _resolved = TextEditingController(text: widget.settings.resolvedPrompt);
  late final _ticket = TextEditingController(text: widget.settings.ticketPrompt);
  late final _quick = TextEditingController(text: widget.settings.quickReplies.join(', '));

  @override
  void dispose() {
    for (final c in [_welcome, _fallback, _resolved, _ticket, _quick]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await widget.api.botSaveSettings(
        BotSettings(
          enabled: _enabled,
          welcome: _welcome.text.trim(),
          fallback: _fallback.text.trim(),
          resolvedPrompt: _resolved.text.trim(),
          ticketPrompt: _ticket.text.trim(),
          quickReplies: [
            for (final q in _quick.text.split(','))
              if (q.trim().isNotEmpty) q.trim(),
          ],
        ),
      );
      if (mounted) toast(context, 'Saved. The app uses it now.');
      widget.onSaved();
    } on AdminException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Widget _f(String label, TextEditingController c, {int lines = 2}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: c,
      minLines: 1,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Chatbot',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Automated replies on'),
          subtitle: const Text('When off, the Help chat only offers “Raise a Support Ticket”.'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        _f('Welcome message', _welcome),
        _f('Quick replies (comma separated; use the topic names)', _quick, lines: 3),
        _f('Fallback when it does not understand', _fallback),
        _f('“Did that solve it?” question', _resolved),
        _f('Message offering a support ticket', _ticket),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: _save, child: const Text('Save chatbot settings')),
        ),
      ],
    ),
  );
}

class _ReplyDialog extends StatefulWidget {
  const _ReplyDialog({required this.api, this.reply});
  final AdminApi api;
  final BotReply? reply;
  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  late String _category = widget.reply?.category ?? 'account';
  late bool _active = widget.reply?.active ?? true;
  late final _title = TextEditingController(text: widget.reply?.title);
  late final _keywords = TextEditingController(text: widget.reply?.keywords.join(', '));
  late final _answer = TextEditingController(text: widget.reply?.answer);
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _keywords.dispose();
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.reply == null ? 'Add a reply' : 'Edit reply'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              items: [
                for (final c in _categories.where((c) => c != 'privacy'))
                  DropdownMenuItem(value: c, child: Text(categoryLabel(c))),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Question (shown as a button)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _keywords,
              decoration: const InputDecoration(
                labelText: 'Keywords (comma separated)',
                helperText: 'Words people type that should bring this answer',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _answer,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(labelText: 'Answer', errorText: _error),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(
        onPressed: () async {
          try {
            await widget.api.botSaveReply(
              id: widget.reply?.id,
              category: _category,
              title: _title.text,
              keywords: [
                for (final k in _keywords.text.split(','))
                  if (k.trim().isNotEmpty) k.trim(),
              ],
              answer: _answer.text,
              active: _active,
              sort: widget.reply?.sort ?? 0,
            );
            if (context.mounted) Navigator.pop(context, true);
          } on AdminException catch (e) {
            setState(() => _error = e.message);
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class _ConversationsDialog extends StatelessWidget {
  const _ConversationsDialog({required this.api});
  final AdminApi api;
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: bg,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 10, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Chatbot conversations', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Expanded(
            child: Loader<List<BotConversationRow>>(
              load: api.botConversations,
              builder: (context, rows, _) => rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No conversations yet.', style: TextStyle(color: muted)),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final c in rows)
                          ExpansionTile(
                            title: Text('${c.userName ?? 'User'}${c.ticketNo == null ? '' : ' · ${c.ticketNo}'}'),
                            subtitle: Text('${fmtDate(c.updatedAt)} · ${c.messages.length} messages'),
                            children: [
                              for (final m in c.messages)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                                    child: Text('${m['mine'] == true ? 'User' : 'Bot'}: ${m['text']}'),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}
