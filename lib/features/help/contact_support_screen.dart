import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/feedback.dart';
import '../../core/image_optimizer.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/support.dart';
import '../../providers.dart';
import '../profile_builder/choice_sheet.dart' show TagChip;
import 'my_tickets_screen.dart';

final _supportEmailProvider = FutureProvider.autoDispose<String?>((ref) => ref.watch(backendProvider).supportEmail());

/// Contact support: category, subject, description and an optional
/// screenshot (compressed on the device). The signed-in account and its
/// registered email are attached by the server.
class ContactSupportScreen extends ConsumerStatefulWidget {
  const ContactSupportScreen({super.key, this.category});
  final SupportCategory? category;

  @override
  ConsumerState<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _ContactSupportScreenState extends ConsumerState<ContactSupportScreen> {
  late SupportCategory? _category = widget.category;
  final _subject = TextEditingController();
  final _description = TextEditingController();
  Uint8List? _shot;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickShot() async {
    try {
      final raw = await ref.read(mediaProvider).pickOriginalPhoto();
      if (raw == null) return;
      final img = await ImageOptimizer.optimize(raw);
      if (mounted) setState(() => _shot = img.bytes);
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn’t use that image: $e', icon: PhosphorIconsFill.warningCircle);
    }
  }

  Future<void> _submit() async {
    final cat = _category;
    final problem = cat == null ? 'Choose a category.' : validateTicket(subject: _subject.text, description: _description.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await ref
          .read(backendProvider)
          .submitSupportTicket(category: cat!, subject: _subject.text, description: _description.text, screenshotWebp: _shot);
      if (!mounted) return;
      Fx.instance.request();
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: Icon(PhosphorIconsFill.checkCircle, color: context.fc.ok, size: 36),
          title: const Text('Request received'),
          content: Text(
            'Your ticket number is ${t.ticketNo}. '
            '${t.email == null ? 'We’ll reply here' : 'We’ll reply to ${t.email}'} and you can follow the status in My tickets.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MyTicketsScreen()));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final email = ref.watch(_supportEmailProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Contact support')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            'Tell us what’s going on. A person from the Vouby team reads every request.',
            style: TextStyle(fontSize: 15, height: 1.45, color: c.ink3),
          ),
          const SectionLabel('Category', padding: EdgeInsets.fromLTRB(2, 20, 2, 10)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in SupportCategory.values)
                TagChip(label: s.label, selected: _category == s, onTap: () => setState(() => _category = s)),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _subject,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Subject'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _description,
            maxLength: 4000,
            minLines: 5,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Describe the issue',
              alignLabelWithHint: true,
              helperText: 'Don’t include passwords or one-time codes.',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pickShot,
                  icon: Icon(_shot == null ? PhosphorIconsRegular.image : PhosphorIconsFill.image, size: 18),
                  label: Text(_shot == null ? 'Attach a screenshot (optional)' : 'Screenshot attached'),
                ),
              ),
              if (_shot != null)
                IconButton(
                  tooltip: 'Remove screenshot',
                  onPressed: () => setState(() => _shot = null),
                  icon: Icon(PhosphorIconsRegular.x, size: 18, color: c.muted),
                ),
            ],
          ),
          if (_shot != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(_shot!, height: 160, fit: BoxFit.cover),
              ),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.hair),
            ),
            child: Row(
              children: [
                Icon(PhosphorIconsRegular.envelopeSimple, size: 18, color: c.ink2),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    email == null ? 'We’ll reply in the app (My tickets).' : 'We’ll reply to $email',
                    style: TextStyle(fontSize: 14, color: c.ink2),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: c.accent, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 20),
          PillButton(label: 'Send request', busy: _busy, onTap: _submit),
        ],
      ),
    );
  }
}
