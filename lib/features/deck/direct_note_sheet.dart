import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/sanitizer.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/profile.dart';

/// Returns the sanitized icebreaker, or null if dismissed.
Future<String?> showDirectNoteSheet(BuildContext context, PublicProfile to) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DirectNoteSheet(to: to),
    );

class _DirectNoteSheet extends StatefulWidget {
  const _DirectNoteSheet({required this.to});
  final PublicProfile to;

  @override
  State<_DirectNoteSheet> createState() => _DirectNoteSheetState();
}

class _DirectNoteSheetState extends State<_DirectNoteSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raw = _text.text;
    final flagged = ContactSanitizer.containsContactInfo(raw);
    final clean = ContactSanitizer.sanitize(raw);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Avatar(url: widget.to.primaryPhoto, name: widget.to.fullName, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Direct DM Invite to ${widget.to.firstName}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                Text('Shown with your request, before they accept',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ]),
            ),
            const Icon(Icons.star_rounded, color: AppColors.gold),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: AppConfig.directNoteMaxLength,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Say something about their bio…',
              errorText: flagged ? 'Contact details will be removed' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: clean.isEmpty ? null : () => Navigator.pop(context, clean),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Send request with note'),
          ),
        ],
      ),
    );
  }
}
