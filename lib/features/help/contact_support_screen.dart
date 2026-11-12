import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/feedback.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../models/support.dart';
import '../../providers.dart';
import '../profile_builder/choice_sheet.dart' show TagChip;
import 'my_tickets_screen.dart';

final _supportEmailProvider = FutureProvider.autoDispose<String?>((ref) => ref.watch(backendProvider).supportEmail());

/// Contact support, laid out as a chat. Vouby Help asks what the problem is, you answer, and the
/// request goes to the team. Nothing here answers for the team: a person reads every request and
/// replies afterwards (by email, or in My tickets), the same as before. No attachments.
class ContactSupportScreen extends ConsumerStatefulWidget {
  const ContactSupportScreen({super.key, this.category});
  final SupportCategory? category;

  @override
  ConsumerState<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _Line {
  const _Line({required this.mine, required this.text});
  final bool mine;
  final String text;
}

enum _Step { category, describe, sending, done }

class _ContactSupportScreenState extends ConsumerState<ContactSupportScreen> {
  final _lines = <_Line>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  _Step _step = _Step.category;
  SupportCategory? _category;
  SupportTicket? _ticket;

  @override
  void initState() {
    super.initState();
    _lines.add(const _Line(mine: false, text: 'Hi, this is Vouby Help. What do you need help with?'));
    final preset = widget.category;
    if (preset != null) _pick(preset);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(_Line l) {
    setState(() => _lines.add(l));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Motion.of(context, Motion.medium), curve: Motion.easeOut);
      }
    });
  }

  void _pick(SupportCategory cat) {
    Fx.instance.tap();
    _category = cat;
    _add(_Line(mine: true, text: cat.label));
    _add(
      const _Line(
        mine: false,
        text: 'Thanks. Tell us what happened, in your own words. Please don’t include passwords or one-time codes.',
      ),
    );
    setState(() => _step = _Step.describe);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  static String _subject(SupportCategory cat, String text) {
    final first = text.trim().split(RegExp(r'[\n.!?]')).first.trim();
    final s = first.length >= 3 ? first : cat.label;
    return s.length > 100 ? '${s.substring(0, 97)}...' : s;
  }

  Future<void> _send() async {
    final cat = _category;
    final text = _input.text.trim();
    if (cat == null || _step != _Step.describe) return;
    final subject = _subject(cat, text);
    final problem = validateTicket(subject: subject, description: text);
    if (problem != null) {
      _add(_Line(mine: false, text: problem));
      return;
    }
    _input.clear();
    _add(_Line(mine: true, text: text));
    setState(() => _step = _Step.sending);
    try {
      final t = await ref.read(backendProvider).submitSupportTicket(category: cat, subject: subject, description: text);
      if (!mounted) return;
      Fx.instance.request();
      _ticket = t;
      final email = t.email;
      _add(
        _Line(
          mine: false,
          text:
              'Your request is with our team. Ticket number: ${t.ticketNo}. A person reads every request and replies '
              '${email == null ? 'in My tickets' : 'to $email'}. It isn’t instant, usually within a day or two.',
        ),
      );
      setState(() => _step = _Step.done);
    } on AppException catch (e) {
      if (!mounted) return;
      _input.text = text;
      _add(_Line(mine: false, text: '${e.message} Your message is still in the box. Tap send to try again.'));
      setState(() => _step = _Step.describe);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
              child: Icon(PhosphorIconsFill.lifebuoy, size: 20, color: c.paper),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Vouby Help', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                Text(
                  ref.watch(_supportEmailProvider).value == null ? 'Replies in My tickets' : 'Replies by email',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: c.muted),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                for (final l in _lines) _Bubble(line: l),
                if (_step == _Step.category)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in SupportCategory.values) TagChip(label: s.label, selected: false, onTap: () => _pick(s)),
                      ],
                    ),
                  ),
                if (_step == _Step.sending)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.muted)),
                    ),
                  ),
                if (_step == _Step.done)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MyTicketsScreen())),
                        child: Text(_ticket == null ? 'My tickets' : 'View my tickets'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      enabled: _step == _Step.describe,
                      minLines: 1,
                      maxLines: 6,
                      maxLength: 4000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: switch (_step) {
                          _Step.category => 'Choose a topic above',
                          _Step.describe => 'Describe what happened',
                          _Step.sending => 'Sending…',
                          _Step.done => 'Request sent',
                        },
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(26),
                          borderSide: BorderSide(color: c.hair),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(26),
                          borderSide: BorderSide(color: c.hair),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(26),
                          borderSide: BorderSide(color: c.hair),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(26),
                          borderSide: BorderSide(color: c.ink3),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _step == _Step.describe ? _send : null,
                    tooltip: 'Send',
                    style: IconButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.paper,
                      fixedSize: const Size(52, 52),
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.line});
  final _Line line;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final mine = line.mine;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, const Duration(milliseconds: 200)),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 6 * (1 - v)), child: child),
      ),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              color: mine ? c.accent : c.surface,
              border: mine ? null : Border.all(color: c.hair),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(mine ? 20 : 6),
                bottomRight: Radius.circular(mine ? 6 : 20),
              ),
            ),
            child: Text(line.text, style: TextStyle(fontSize: 15.5, height: 1.4, color: mine ? c.paper : c.ink)),
          ),
        ),
      ),
    );
  }
}
