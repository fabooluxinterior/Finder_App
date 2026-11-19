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
import 'raise_ticket_screen.dart';

/// How long the assistant "types" before each reply, so it reads like a person.
const _typingDelay = Duration(seconds: 2);

enum _Stage { menu, questions, answered, resolved, ticket }

class _Line {
  const _Line({required this.mine, required this.text});
  final bool mine;
  final String text;
  Map<String, dynamic> toJson() => {'mine': mine, 'text': text};
}

/// The 24/7 help assistant. Answers common questions from the answers the Vouby team manages; when it can't help,
/// the only way forward is to raise a support ticket. Conversations are kept.
class SupportChatScreen extends ConsumerStatefulWidget {
  const SupportChatScreen({super.key});

  @override
  ConsumerState<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends ConsumerState<SupportChatScreen> {
  final _lines = <_Line>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  BotConfig? _config;
  _Stage _stage = _Stage.menu;
  SupportCategory? _category;
  List<FaqEntry> _questions = const [];
  List<({String id, String title})> _related = const [];
  FaqEntry? _lastAnswer;
  bool _typing = false;
  bool _loading = true;
  bool _failed = false;
  String? _session;
  String _lastUserText = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final b = ref.read(backendProvider);
      final cfg = await b.supportBotConfig();
      final last = await b.lastBotConversation();
      if (!mounted) return;
      setState(() {
        _config = cfg;
        _loading = false;
        if (last != null && last.messages.isNotEmpty) {
          _session = last.id;
          _lines.addAll([for (final m in last.messages) _Line(mine: m['mine'] == true, text: '${m['text']}')]);
          _lines.add(const _Line(mine: false, text: 'Welcome back. What else can I help with?'));
        } else {
          _lines.add(_Line(mine: false, text: cfg.welcome));
        }
        _stage = _Stage.menu;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _scrollSoon() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: Motion.of(context, Motion.medium),
        curve: Motion.easeOut,
      );
    }
  });

  void _setStage(_Stage s) {
    setState(() => _stage = s);
    _scrollSoon(); // the new buttons are at the bottom
  }

  void _add(_Line l) {
    setState(() => _lines.add(l));
    _scrollSoon();
  }

  Future<void> _save() async {
    try {
      _session = await ref.read(backendProvider).saveBotConversation(_session, [for (final l in _lines) l.toJson()]);
    } catch (_) {
      /* the conversation is still on screen; saving is retried after the next message */
    }
  }

  /// The assistant types for two seconds, then answers.
  Future<void> _botSay(String text) async {
    setState(() => _typing = true);
    _scrollSoon();
    await Future<void>.delayed(_typingDelay);
    if (!mounted) return;
    setState(() => _typing = false);
    _add(_Line(mine: false, text: text));
  }

  Future<void> _say(String text) async {
    _add(_Line(mine: true, text: text));
    _lastUserText = text;
  }

  Future<void> _pickCategory(SupportCategory cat) async {
    Fx.instance.tap();
    await _say(cat.label);
    setState(() {
      _category = cat;
      _stage = _Stage.questions;
      _questions = const [];
    });
    try {
      final qs = await ref.read(backendProvider).supportFaqs(category: cat);
      if (!mounted) return;
      _questions = qs;
      await _botSay(
        qs.isEmpty
            ? 'I don’t have ready answers for that yet. You can describe it below, or raise a ticket.'
            : 'Here are common questions about ${cat.label.toLowerCase()}. Tap one, or type your own.',
      );
    } catch (_) {
      await _botSay('I couldn’t load that just now. You can type your question, or raise a ticket.');
    }
    await _save();
  }

  Future<void> _showAnswer(FaqEntry e, {required String asked}) async {
    _lastAnswer = e;
    await _botSay(e.answer);
    if (!mounted) return;
    _related = const [];
    await _botSay(_config?.resolvedPrompt ?? 'Did that solve your issue?');
    if (mounted) _setStage(_Stage.answered);
    await _save();
  }

  Future<void> _pickQuestion(FaqEntry e) async {
    Fx.instance.tap();
    await _say(e.title);
    await _showAnswer(e, asked: e.title);
  }

  Future<void> _askRelated(({String id, String title}) r) async {
    Fx.instance.tap();
    await _say(r.title);
    try {
      final faqs = await ref.read(backendProvider).supportFaqs(query: r.title);
      final hit = faqs.where((f) => f.title == r.title).firstOrNull ?? faqs.firstOrNull;
      if (hit != null) {
        await _showAnswer(hit, asked: r.title);
        return;
      }
    } catch (_) {}
    await _noAnswer();
  }

  Future<void> _noAnswer() async {
    await _botSay(_config?.fallback ?? 'Sorry, I didn’t quite get that. Could you rephrase it, or raise a support ticket?');
    if (mounted) _setStage(_Stage.ticket);
    await _save();
  }

  Future<void> _typed() async {
    final text = _input.text.trim();
    if (text.isEmpty || _typing) return;
    _input.clear();
    await _say(text);
    setState(() => _typing = true);
    _scrollSoon();
    try {
      final results = await Future.wait<Object?>([
        ref.read(backendProvider).supportBotAnswer(text, category: _category),
        Future<void>.delayed(_typingDelay),
      ]);
      if (!mounted) return;
      final a = results[0] as BotAnswer?;
      setState(() => _typing = false);
      if (a == null) {
        await _noAnswer();
        return;
      }
      _lastAnswer = a.entry;
      _add(_Line(mine: false, text: a.entry.answer));
      _related = a.related;
      await _botSay(_config?.resolvedPrompt ?? 'Did that solve your issue?');
      if (mounted) _setStage(_Stage.answered);
      await _save();
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _typing = false);
      _add(_Line(mine: false, text: '${e.message} You can try again, or raise a ticket.'));
      _setStage(_Stage.ticket);
    }
  }

  Future<void> _solved(bool yes) async {
    Fx.instance.tap();
    await _say(yes ? 'Yes, thanks' : 'No, I still need help');
    if (yes) {
      await _botSay('Great, glad I could help! Ask me anything else any time.');
      if (mounted) _setStage(_Stage.resolved);
    } else {
      await _botSay(_config?.ticketPrompt ?? 'You can raise a support ticket and our team will help.');
      if (mounted) _setStage(_Stage.ticket);
    }
    await _save();
  }

  Future<void> _raiseTicket() async {
    await _save();
    if (!mounted) return;
    final mine = _lines.where((l) => l.mine).map((l) => l.text).toList();
    final title = _lastUserText.length > 100 ? '${_lastUserText.substring(0, 97)}...' : _lastUserText;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RaiseTicketScreen(
          category: _lastAnswer?.category ?? _category,
          title: title,
          details: mine.isEmpty ? null : mine.join('\n'),
          botConversationId: _session,
        ),
      ),
    );
  }

  void _restart() {
    setState(() {
      _stage = _Stage.menu;
      _category = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final cfg = _config;
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
                const Text('Vouby Support', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                Text(
                  _typing ? 'typing…' : 'Here 24/7',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: c.muted),
                ),
              ],
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? _Offline(
              onRetry: () {
                setState(() {
                  _loading = true;
                  _failed = false;
                });
                _start();
              },
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    children: [
                      for (final l in _lines) _Bubble(line: l),
                      if (_typing) const _TypingBubble(),
                      if (!_typing && cfg != null && cfg.enabled) _choices(c, cfg),
                      if (!_typing && cfg != null && !cfg.enabled)
                        Padding(padding: const EdgeInsets.only(top: 8), child: _ticketButton()),
                    ],
                  ),
                ),
                if (cfg != null && cfg.enabled)
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
                              minLines: 1,
                              maxLines: 4,
                              maxLength: 500,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _typed(),
                              decoration: InputDecoration(
                                hintText: 'Type your question',
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
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: BorderSide(color: c.ink3),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _typing ? null : _typed,
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

  Widget _ticketButton() => Align(
    alignment: Alignment.centerLeft,
    child: FilledButton.icon(
      onPressed: _raiseTicket,
      icon: const Icon(Icons.confirmation_number_outlined, size: 18),
      label: const Text('Raise a Support Ticket'),
    ),
  );

  Widget _choices(FinderColors c, BotConfig cfg) {
    Widget wrap(List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Wrap(spacing: 8, runSpacing: 8, children: children),
    );
    switch (_stage) {
      case _Stage.menu:
        final cats = [for (final q in cfg.quickReplies) (SupportCategoryX.helpTopics.where((t) => t.label == q).firstOrNull, q)];
        return wrap([
          for (final (cat, q) in cats)
            TagChip(
              label: q,
              selected: false,
              onTap: cat == null
                  ? () {
                      _input.text = q;
                      _typed();
                    }
                  : () => _pickCategory(cat),
            ),
        ]);
      case _Stage.questions:
        return wrap([
          for (final f in _questions.take(8)) TagChip(label: f.title, selected: false, onTap: () => _pickQuestion(f)),
          TagChip(label: 'Back to topics', selected: false, onTap: _restart),
        ]);
      case _Stage.answered:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            wrap([
              TagChip(label: 'Yes, thanks', selected: false, onTap: () => _solved(true)),
              TagChip(label: 'No, I still need help', selected: false, onTap: () => _solved(false)),
            ]),
            if (_related.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Related questions', style: TextStyle(fontSize: 12.5, color: c.muted)),
              ),
              wrap([for (final r in _related) TagChip(label: r.title, selected: false, onTap: () => _askRelated(r))]),
            ],
          ],
        );
      case _Stage.resolved:
        return wrap([TagChip(label: 'Ask something else', selected: false, onTap: _restart)]);
      case _Stage.ticket:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 6, bottom: 8), child: _ticketButton()),
            wrap([TagChip(label: 'Back to topics', selected: false, onTap: _restart)]),
          ],
        );
    }
  }
}

class _Offline extends StatelessWidget {
  const _Offline({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Couldn’t reach support. Check your connection.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.fc.muted),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.line});
  final _Line line;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final mine = line.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: mine ? c.sentBubble : c.surface,
            border: mine ? null : Border.all(color: c.hair),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(mine ? 20 : 6),
              bottomRight: Radius.circular(mine ? 6 : 20),
            ),
          ),
          child: Text(line.text, style: TextStyle(fontSize: 15.5, height: 1.4, color: mine ? c.onSent : c.ink)),
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
