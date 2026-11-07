import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../core/sanitizer.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/media_service.dart';
import '../../models/message.dart';
import '../../models/profile.dart';
import '../../providers.dart';
import '../profile/profile_detail_screen.dart';
import '../safety/safety_actions.dart';
import '../security/safety_number_screen.dart';
import 'voice_bubble.dart';
import 'voice_recorder_bar.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.peer});
  final PublicProfile peer;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = VoiceRecorder();
  bool _recording = false;
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _sendText(List<ChatMessage> thread) async {
    final me = ref.read(backendProvider).currentUserId;
    var text = _text.text.trim();
    if (text.isEmpty) return;

    // Opening messages are filtered for phone numbers, @handles and links.
    final sentByMe = thread.where((m) => m.senderId == me).length;
    if (sentByMe < AppConfig.sanitizedOpeningMessages && ContactSanitizer.containsContactInfo(text)) {
      text = ContactSanitizer.sanitize(text);
      showSnack(context, 'Contact details were removed. Get to know each other first 🙂', icon: Icons.shield_outlined);
      if (text.replaceAll('•', '').trim().isEmpty) return;
    }

    setState(() => _sending = true);
    try {
      await ref.read(backendProvider).sendText(widget.peer.id, text);
      _text.clear();
      _scrollToLatest();
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) showSnack(context, 'Microphone permission is needed for voice notes.', icon: Icons.mic_off);
      return;
    }
    try {
      await _recorder.start(onCapReached: () => _finishRecording(send: true));
      setState(() => _recording = true);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not start recording: $e', icon: Icons.mic_off);
    }
  }

  Future<void> _finishRecording({required bool send}) async {
    if (!_recording) return;
    setState(() => _recording = false);
    if (!send) {
      await _recorder.cancel();
      return;
    }
    final note = await _recorder.stop();
    if (note == null || note.duration < const Duration(milliseconds: 800)) {
      if (mounted) showSnack(context, 'Hold on a little longer to record a voice note.');
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(backendProvider).sendVoice(widget.peer.id, note.bytes, localPath: note.path, duration: note.duration);
      _scrollToLatest();
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(backendProvider);
    final me = backend.currentUserId;
    final messages = ref.watch(messagesProvider(widget.peer.id));

    ref.listen(messagesProvider(widget.peer.id), (prev, next) {
      final list = next.value ?? const <ChatMessage>[];
      if (list.any((m) => m.receiverId == me && !m.isRead)) {
        backend.markThreadRead(widget.peer.id);
      }
      if ((prev?.value?.length ?? 0) < list.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
      }
    });

    final thread = messages.value ?? const <ChatMessage>[];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: widget.peer)),
          ),
          child: Row(children: [
            Avatar(url: widget.peer.primaryPhoto, name: widget.peer.fullName, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.peer.firstName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Row(children: [
                  Icon(backend.isEndToEndEncrypted ? Icons.lock_rounded : Icons.lock_open_rounded,
                      size: 12, color: backend.isEndToEndEncrypted ? Colors.green.shade600 : Colors.orange.shade700),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      backend.isEndToEndEncrypted ? 'End-to-end encrypted · screenshots blocked' : 'Demo · not encrypted',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: backend.isEndToEndEncrypted ? Colors.green.shade700 : Colors.orange.shade800,
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'verify':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SafetyNumberScreen(peer: widget.peer)));
                case 'report':
                  if (await showReportSheet(context, widget.peer, thread: thread) && context.mounted) Navigator.pop(context);
                case 'block':
                  if (await confirmBlock(context, ref, widget.peer) && context.mounted) Navigator.pop(context);
                case 'unmatch':
                  if (await confirmUnmatch(context, ref, widget.peer) && context.mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (_) => [
              if (backend.isEndToEndEncrypted) const PopupMenuItem(value: 'verify', child: Text('Verify encryption')),
              const PopupMenuItem(value: 'report', child: Text('Report')),
              const PopupMenuItem(value: 'block', child: Text('Block')),
              const PopupMenuItem(value: 'unmatch', child: Text('Unmatch')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) => list.isEmpty
                  ? _ThreadIntro(peer: widget.peer)
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final m = list[list.length - 1 - i];
                        final older = i + 1 < list.length ? list[list.length - 2 - i] : null;
                        final showDay = older == null || !DateUtils.isSameDay(older.createdAt, m.createdAt);
                        return Column(children: [
                          if (showDay) _DayChip(m.createdAt),
                          _Bubble(message: m, mine: m.senderId == me),
                        ]);
                      },
                    ),
            ),
          ),
          SafeArea(
            top: false,
            child: _recording
                ? VoiceRecorderBar(
                    recorder: _recorder,
                    onCancel: () => _finishRecording(send: false),
                    onSend: () => _finishRecording(send: true),
                  )
                : _Composer(
                    controller: _text,
                    sending: _sending,
                    onSend: () => _sendText(thread),
                    onMic: _startRecording,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.sending, required this.onSend, required this.onMic});
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, value, _) {
          final hasText = value.text.trim().isNotEmpty;
          return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                maxLength: 2000,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Message',
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  enabledBorder:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox.square(
              dimension: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 48),
                  shape: const CircleBorder(),
                ),
                onPressed: sending ? null : (hasText ? onSend : onMic),
                child: sending
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(hasText ? Icons.send_rounded : Icons.mic_rounded),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});
  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('h:mm a').format(message.createdAt);
    final fg = mine ? Colors.white : AppColors.ink;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
          decoration: BoxDecoration(
            gradient: mine ? AppColors.brandGradient : null,
            color: mine ? null : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.isVoice)
                VoiceBubble(message: message, color: fg)
              else
                Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: Text(message.content ?? '', style: TextStyle(color: fg, fontSize: 15.5, height: 1.3)),
                ),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(time, style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11)),
                if (mine) ...[
                  const SizedBox(width: 4),
                  Icon(message.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 14, color: fg.withValues(alpha: 0.8)),
                ],
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip(this.date);
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = DateUtils.isSameDay(date, now)
        ? 'Today'
        : DateUtils.isSameDay(date, now.subtract(const Duration(days: 1)))
            ? 'Yesterday'
            : DateFormat('d MMM yyyy').format(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _ThreadIntro extends StatelessWidget {
  const _ThreadIntro({required this.peer});
  final PublicProfile peer;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Avatar(url: peer.primaryPhoto, name: peer.fullName, size: 96),
            const SizedBox(height: 14),
            Text('You and ${peer.firstName} are connected',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Consumer(
              builder: (context, ref, _) => Text(
                ref.watch(backendProvider).isEndToEndEncrypted
                    ? 'Messages and voice notes are end-to-end encrypted: only you and ${peer.firstName} can read them. Screenshots are blocked.'
                    : 'Text and voice notes are free. Screenshots are blocked.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ]),
        ),
      );
}
