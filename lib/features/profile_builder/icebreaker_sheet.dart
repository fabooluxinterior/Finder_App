import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/feedback.dart';
import '../../core/phosphor.dart';
import '../../core/sanitizer.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/follow_request.dart';
import '../../models/profile.dart';
import '../../models/profile_catalog.dart';
import '../../providers.dart';

/// Reply to one prompt answer. The reply is sent with a follow request and
/// opens the conversation if they accept. Returns the outcome, or null.
Future<SwipeOutcome?> showIcebreakerSheet(BuildContext context, PublicProfile profile, ProfilePrompt prompt) {
  return showModalBottomSheet<SwipeOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _IcebreakerSheet(profile: profile, prompt: prompt),
  );
}

class _IcebreakerSheet extends ConsumerStatefulWidget {
  const _IcebreakerSheet({required this.profile, required this.prompt});
  final PublicProfile profile;
  final ProfilePrompt prompt;

  @override
  ConsumerState<_IcebreakerSheet> createState() => _IcebreakerSheetState();
}

class _IcebreakerSheetState extends ConsumerState<_IcebreakerSheet> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final outcome = await ref.read(backendProvider).replyToPrompt(widget.profile.id, widget.prompt.promptId, t);
      Fx.instance.request();
      if (mounted) Navigator.pop(context, outcome);
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final p = widget.profile;
    final contact = ContactSanitizer.containsContactInfo(_text.text);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Reply to ${p.firstName}',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.ink),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.paper,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.hair),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.prompt.question,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.muted),
                    ),
                    const SizedBox(height: 4),
                    Text(widget.prompt.answer, style: TextStyle(fontSize: 17, height: 1.35, color: c.ink)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                maxLength: promptAnswerMax,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Say something specific about their answer',
                  errorText: contact ? 'Remove phone numbers, handles or links.' : null,
                ),
              ),
              Text(
                'Sent with your request. If ${p.firstName} accepts, it opens your chat. '
                'Until then it isn’t end-to-end encrypted.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: c.muted),
              ),
              const SizedBox(height: 12),
              PillButton(
                label: 'Send request with reply',
                busy: _busy,
                onTap: _text.text.trim().isEmpty || contact ? null : _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
