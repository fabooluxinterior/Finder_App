import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../ui.dart';

/// Messaging → Notifications. Custom popup notifications to users' phones.
/// Each send is also added to the user's in-app notification list and logged.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.api});
  final AdminApi api;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _phone = TextEditingController();
  String _audience = 'all';
  bool _busy = false;
  late Future<List<PushCampaign>> _log = widget.api.pushCampaigns();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _valid =>
      _title.text.trim().isNotEmpty &&
      _title.text.trim().length <= 65 &&
      _body.text.trim().isNotEmpty &&
      _body.text.trim().length <= 240 &&
      (_audience != 'user' || _phone.text.trim().isNotEmpty);

  Future<void> _send() async {
    final who = pushAudiences[_audience]!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Send this notification?'),
        content: Text('"${_title.text.trim()}"\n${_body.text.trim()}\n\nTo: $who. This can\'t be recalled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await widget.api.sendPush(
        title: _title.text.trim(),
        body: _body.text.trim(),
        audience: _audience,
        phone: _audience == 'user' ? _phone.text.trim() : null,
      );
      if (!mounted) return;
      toast(
        context,
        r.pushConfigured
            ? 'Sent to ${r.recipients} people: ${r.delivered} phones reached, ${r.failed} failed.'
            : 'Saved in ${r.recipients} in-app lists. Phone popups need Firebase set up (Integrations).',
      );
      _title.clear();
      _body.clear();
      setState(() => _log = widget.api.pushCampaigns());
    } on AdminException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Notifications',
    subtitle: 'Send a popup to users\' phones. It also appears in their in-app notification list.',
    children: [
      SectionCard(
        title: 'New notification',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _audience,
              decoration: const InputDecoration(labelText: 'Send to'),
              items: [for (final e in pushAudiences.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _audience = v ?? 'all'),
            ),
            if (_audience == 'user') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile number', hintText: '98765 43210'),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              maxLength: 65,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _body,
              maxLength: 240,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Message'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _valid && !_busy ? _send : null,
                icon: const Icon(Icons.send_outlined, size: 18),
                label: Text(_busy ? 'Sending…' : 'Send notification'),
              ),
            ),
          ],
        ),
      ),
      SectionCard(
        title: 'Recent sends',
        child: FutureBuilder<List<PushCampaign>>(
          future: _log,
          builder: (context, s) {
            final items = s.data ?? const <PushCampaign>[];
            if (s.hasError) return const Text('Couldn\'t load the log.', style: TextStyle(color: muted));
            if (items.isEmpty) return const Text('Nothing sent yet.', style: TextStyle(color: muted));
            return Column(
              children: [
                for (final c in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.title),
                    subtitle: Text(
                      '${c.body}\n${pushAudiences[c.audience] ?? c.audience} · ${c.createdAt.toLocal().toString().substring(0, 16)}',
                    ),
                    isThreeLine: true,
                    trailing: Text('${c.delivered}/${c.recipients} phones', style: const TextStyle(color: muted)),
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );
}
