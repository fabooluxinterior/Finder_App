import 'package:flutter/material.dart';

import '../api.dart';
import '../models_mod.dart';
import '../ui.dart';

/// Admin → Fun lines & calling: the Malayalam lines shown in the app, and how many days before calling opens.
class FunLinesPage extends StatefulWidget {
  const FunLinesPage({super.key, required this.api});
  final AdminApi api;

  @override
  State<FunLinesPage> createState() => _FunLinesPageState();
}

class _FunLinesPageState extends State<FunLinesPage> {
  int _gen = 0;
  void _refresh() => setState(() => _gen++);

  Future<void> _edit([FunLine? line]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _LineDialog(api: widget.api, line: line),
    );
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Fun lines & calling',
    subtitle: 'Malayalam / Manglish lines shown to users, and the waiting time before calling opens. Changes reach the app straight away.',
    actions: [FilledButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('Add line'), onPressed: _edit)],
    children: [
      SectionCard(
        title: 'Calling opens after',
        child: Loader<int>(
          key: ValueKey('days$_gen'),
          load: widget.api.callDays,
          builder: (context, days, reload) => _DaysField(api: widget.api, days: days, onSaved: _refresh),
        ),
      ),
      Loader<List<FunLine>>(
        key: ValueKey(_gen),
        load: widget.api.funLines,
        builder: (context, lines, reload) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final slot in funSlots.keys.where((s) => lines.any((l) => l.slot == s)))
              SectionCard(
                title: funSlots[slot]!,
                child: Column(
                  children: [
                    for (final l in lines.where((l) => l.slot == slot))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l.text, style: TextStyle(color: l.enabled ? null : muted)),
                        leading: Switch(
                          value: l.enabled,
                          onChanged: (v) async {
                            await widget.api.saveFunLine(id: l.id, slot: l.slot, text: l.text, enabled: v, sort: l.sort);
                            _refresh();
                          },
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(l)),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await widget.api.deleteFunLine(l.id);
                                _refresh();
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

class _DaysField extends StatefulWidget {
  const _DaysField({required this.api, required this.days, required this.onSaved});
  final AdminApi api;
  final int days;
  final VoidCallback onSaved;

  @override
  State<_DaysField> createState() => _DaysFieldState();
}

class _DaysFieldState extends State<_DaysField> {
  late final _ctl = TextEditingController(text: '${widget.days}');
  String? _msg;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final d = int.tryParse(_ctl.text.trim());
    if (d == null || d < 0 || d > 60) {
      setState(() => _msg = 'Enter a whole number from 0 to 60.');
      return;
    }
    try {
      await widget.api.setCallDays(d);
      setState(() => _msg = 'Saved. Calling now opens $d days after two people connect.');
      widget.onSaved();
    } on AdminException catch (e) {
      setState(() => _msg = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          SizedBox(
            width: 120,
            child: TextField(
              controller: _ctl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Days', isDense: true),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        _msg ?? '0 opens calling at once. Users get a notification when it opens.',
        style: const TextStyle(color: muted, fontSize: 13),
      ),
    ],
  );
}

class _LineDialog extends StatefulWidget {
  const _LineDialog({required this.api, this.line});
  final AdminApi api;
  final FunLine? line;

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  late final _text = TextEditingController(text: widget.line?.text ?? '');
  late String _slot = widget.line?.slot ?? 'tip';
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.line == null ? 'Add a line' : 'Edit line'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _slot,
            decoration: const InputDecoration(labelText: 'Where it appears'),
            items: [for (final e in funSlots.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _slot = v ?? 'tip'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            maxLength: 220,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: 'Line (Malayalam or Manglish)', errorText: _error),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(
        onPressed: () async {
          if (_text.text.trim().isEmpty) {
            setState(() => _error = 'Write the line first.');
            return;
          }
          await widget.api.saveFunLine(
            id: widget.line?.id,
            slot: _slot,
            text: _text.text.trim(),
            enabled: widget.line?.enabled ?? true,
            sort: widget.line?.sort ?? 0,
          );
          if (context.mounted) Navigator.pop(context, true);
        },
        child: const Text('Save'),
      ),
    ],
  );
}
