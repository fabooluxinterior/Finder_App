import 'dart:async';
import 'dart:math' as math;

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

/// Contact support, laid out as a chat. Vouby Help asks what the problem is, you answer, and the
/// request goes to the team. Nothing here answers for the team: a person reads every request and
/// replies afterwards (by email, or in My tickets), the same as before. No attachments.
class ContactSupportScreen extends ConsumerStatefulWidget {
  const ContactSupportScreen({super.key, this.category, this.ticket});
  final SupportCategory? category;

  /// Open an existing request to read the team's replies and add to it.
  final SupportTicket? ticket;

  @override
  ConsumerState<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _Line {
  const _Line({required this.mine, required this.text, this.team = false});
  final bool mine;
  final String text;

  /// A reply written by a person on the Vouby team (not the assistant).
  final bool team;
}

enum _Step { category, describe, sending, followUp }

/// How long the assistant "types" before each reply, so it reads like a person.
const _typingDelay = Duration(seconds: 2);

class _ContactSupportScreenState extends ConsumerState<ContactSupportScreen> {
  final _lines = <_Line>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  _Step _step = _Step.category;
  SupportCategory? _category;
  SupportTicket? _ticket;
  bool _typing = false;
  bool _acked = false;
  Timer? _poll;
  final _seen = <int>{};

  @override
  void initState() {
    super.initState();
    final existing = widget.ticket;
    if (existing != null) {
      _ticket = existing;
      _category = existing.category;
      _step = _Step.followUp;
      _lines.add(_Line(mine: false, text: 'Your request ${existing.ticketNo}. Add anything here and the team will reply.'));
      _refreshThread(initial: true);
      _startPolling();
      return;
    }
    _lines.add(const _Line(mine: false, text: 'Hi, this is Vouby Help. What do you need help with?'));
    final preset = widget.category;
    if (preset != null) _pick(preset);
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refreshThread());
  }

  /// Shows the team's new replies. Your own messages are already on screen.
  Future<void> _refreshThread({bool initial = false}) async {
    final t = _ticket;
    if (t == null) return;
    try {
      final thread = await ref.read(backendProvider).ticketThread(t.id);
      if (!mounted) return;
      var added = false;
      for (final m in thread) {
        if (!_seen.add(m.id) && m.id != 0) continue;
        if (m.id == 0 && !initial) continue;
        if (initial || m.fromStaff) {
          if (!initial && !m.fromStaff) continue;
          _lines.add(_Line(mine: !m.fromStaff, text: m.body, team: m.fromStaff));
          added = true;
        }
      }
      if (added) {
        setState(() {});
        if (!initial) Fx.instance.received();
        _scrollSoon();
      }
    } catch (_) {
      /* offline: try again on the next tick */
    }
  }

  void _scrollSoon() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: Motion.of(context, Motion.medium),
        curve: Motion.easeOut,
      );
    }
  });

  /// The assistant types for two seconds, then answers.
  Future<void> _botSay(String text) async {
    setState(() => _typing = true);
    _scrollSoon();
    await Future<void>.delayed(_typingDelay);
    if (!mounted) return;
    setState(() => _typing = false);
    _add(_Line(mine: false, text: text));
  }

  @override
  void dispose() {
    _poll?.cancel();
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

  Future<void> _pick(SupportCategory cat) async {
    Fx.instance.tap();
    _category = cat;
    _add(_Line(mine: true, text: cat.label));
    setState(() => _step = _Step.describe);
    await _botSay('Thanks. Tell us what happened, in your own words. Please don’t include passwords or one-time codes.');
    if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  static String _subject(SupportCategory cat, String text) {
    final first = text.trim().split(RegExp(r'[\n.!?]')).first.trim();
    final s = first.length >= 3 ? first : cat.label;
    return s.length > 100 ? '${s.substring(0, 97)}...' : s;
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (_step == _Step.followUp) return _sendFollowUp(text);
    final cat = _category;
    if (cat == null || _step != _Step.describe) return;
    // A very short message is still shared as written; the category is added so the request has enough to read.
    final description = text.length >= 10 ? text : '$text (${cat.label})';
    final subject = _subject(cat, text);
    final problem = validateTicket(subject: subject, description: description);
    if (problem != null) {
      _add(_Line(mine: false, text: problem));
      return;
    }
    _input.clear();
    _add(_Line(mine: true, text: text));
    setState(() {
      _step = _Step.sending;
      _typing = true;
    });
    _scrollSoon();
    try {
      // The request goes to the team while the assistant "types".
      final results = await Future.wait<Object?>([
        ref.read(backendProvider).submitSupportTicket(category: cat, subject: subject, description: description),
        Future<void>.delayed(_typingDelay),
      ]);
      if (!mounted) return;
      final t = results[0]! as SupportTicket;
      Fx.instance.request();
      _ticket = t;
      _seen.add(0);
      final email = t.email;
      setState(() {
        _typing = false;
        _step = _Step.followUp;
      });
      _add(
        _Line(
          mine: false,
          text:
              'Thanks, I’ve shared this with our team. Your ticket number is ${t.ticketNo}. A person reads every request and '
              'replies right here${email == null ? '' : ' and to $email'}. It isn’t instant, usually within a day or two. '
              'You can add more below.',
        ),
      );
      _startPolling();
    } on AppException catch (e) {
      if (!mounted) return;
      _input.text = text;
      setState(() {
        _typing = false;
        _step = _Step.describe;
      });
      _add(_Line(mine: false, text: '${e.message} Your message is still in the box. Tap send to try again.'));
    }
  }

  Future<void> _sendFollowUp(String text) async {
    final t = _ticket;
    if (t == null) return;
    _input.clear();
    _add(_Line(mine: true, text: text));
    try {
      await ref.read(backendProvider).replyToTicket(t.id, text);
      if (!_acked) {
        _acked = true;
        await _botSay('Got it, I’ve added that to your request. The team will reply here.');
      }
    } on AppException catch (e) {
      if (!mounted) return;
      _input.text = text;
      _add(_Line(mine: false, text: '${e.message} Your message is still in the box. Tap send to try again.'));
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
                  _typing ? 'typing…' : 'Replies here and by email',
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
                if (_typing) const _TypingBubble(),
                if (_step == _Step.followUp)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MyTicketsScreen())),
                        child: const Text('View my tickets'),
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
                      enabled: _step == _Step.describe || _step == _Step.followUp,
                      minLines: 1,
                      maxLines: 6,
                      maxLength: 4000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: switch (_step) {
                          _Step.category => 'Choose a topic above',
                          _Step.describe => 'Describe what happened',
                          _Step.sending => 'Sending…',
                          _Step.followUp => 'Write a message',
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
                    onPressed: _step == _Step.describe || _step == _Step.followUp ? _send : null,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (line.team)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      'Vouby team',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.accent),
                    ),
                  ),
                Text(line.text, style: TextStyle(fontSize: 15.5, height: 1.4, color: mine ? c.paper : c.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Three dots that rise and fall one after another, like a person typing.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: 'Vouby Help is typing',
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.hair),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(6),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
                    child: Transform.translate(
                      offset: Offset(0, -4 * (0.5 + 0.5 * math.sin((_c.value * 2 * math.pi) - i * 0.9))),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: c.muted.withValues(alpha: 0.55 + 0.35 * (i / 2)),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
