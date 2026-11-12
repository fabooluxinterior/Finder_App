import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/image_optimizer.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/phosphor.dart';

import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/brand.dart';
import '../../core/feedback.dart';
import '../../core/sanitizer.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/media_service.dart';
import '../../models/message.dart';
import '../../models/profile.dart';
import '../../models/profile_catalog.dart';
import '../requests/requests_screen.dart' show IntroQuote;
import '../../providers.dart';
import '../paywall/paywall_sheet.dart';
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

  /// Messages picked (long-press) to report as evidence.
  final _selected = <String>{};

  /// Messages present when the thread opened don't animate; new ones do.
  Set<String>? _initialIds;

  @override
  void initState() {
    super.initState();
    // No alert for messages in the chat that is already open.
    _openChat = ref.read(openChatProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openChat.open(widget.peer.id);
    });
  }

  late final OpenChatNotifier _openChat;

  @override
  void dispose() {
    final open = _openChat;
    final id = widget.peer.id;
    Future.microtask(() => open.closeIf(id));
    _text.dispose();
    _scroll.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: Motion.of(context, Motion.medium), curve: Motion.easeOut);
  }

  /// Sending needs Fast-Track; the server enforces it, the app explains it.
  Future<bool> _handleError(Object e) async {
    if (!mounted) return false;
    if (e is AppException && e.code == AppErrorCode.subscriptionRequired) {
      return showPaywall(context, reason: PaywallReason.messaging);
    }
    showSnack(context, '$e', icon: PhosphorIconsFill.warningCircle);
    return false;
  }

  Future<void> _sendText(List<ChatMessage> thread) async {
    final me = ref.read(backendProvider).currentUserId;
    var text = _text.text.trim();
    if (text.isEmpty) return;

    // Opening messages are filtered for phone numbers, @handles and links.
    final sentByMe = thread.where((m) => m.senderId == me).length;
    if (sentByMe < AppConfig.sanitizedOpeningMessages && ContactSanitizer.containsContactInfo(text)) {
      text = ContactSanitizer.sanitize(text);
      showSnack(context, 'Contact details were removed. Get to know each other first.', icon: PhosphorIconsFill.shieldCheck);
      if (text.replaceAll('•', '').trim().isEmpty) return;
    }

    setState(() => _sending = true);
    try {
      await ref.read(backendProvider).sendText(widget.peer.id, text);
      Fx.instance.sent();
      _text.clear();
      _scrollToLatest();
    } catch (e) {
      await _handleError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startRecording() async {
    if (!isPremium(ref)) {
      await showPaywall(context, reason: PaywallReason.messaging);
      return;
    }
    if (!await _recorder.hasPermission()) {
      if (mounted) showSnack(context, 'Allow microphone access to send voice notes.', icon: PhosphorIconsFill.microphoneSlash);
      return;
    }
    try {
      await _recorder.start(onCapReached: () => _finishRecording(send: true));
      Fx.instance.tap();
      setState(() => _recording = true);
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn’t start recording.', icon: PhosphorIconsFill.microphoneSlash);
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
      if (mounted) showSnack(context, 'Hold a little longer to record a voice note.');
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(backendProvider).sendVoice(widget.peer.id, note.bytes, localPath: note.path, duration: note.duration);
      Fx.instance.sent();
      _scrollToLatest();
    } catch (e) {
      await _handleError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendPhoto() async {
    if (!isPremium(ref)) {
      await showPaywall(context, reason: PaywallReason.messaging);
      return;
    }
    try {
      final raw = await ref.read(mediaProvider).pickOriginalPhoto();
      if (raw == null) return;
      setState(() => _sending = true);
      // Any image type: resized and compressed on the device, then encrypted.
      final img = await ImageOptimizer.optimizeForChat(raw);
      await ref.read(backendProvider).sendImage(widget.peer.id, img.bytes, width: img.width, height: img.height);
      Fx.instance.sent();
      _scrollToLatest();
    } catch (e) {
      await _handleError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toggle(ChatMessage m) => setState(() => _selected.contains(m.id) ? _selected.remove(m.id) : _selected.add(m.id));

  Future<void> _reportSelected(List<ChatMessage> thread) async {
    final picked = thread.where((m) => _selected.contains(m.id)).toList();
    final sent = await showReportSheet(context, widget.peer, thread: thread, selected: picked);
    if (!mounted) return;
    setState(_selected.clear);
    if (sent) Navigator.pop(context);
  }

  void _openProfile() => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: widget.peer)));

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final backend = ref.watch(backendProvider);
    final me = backend.currentUserId;
    final messages = ref.watch(messagesProvider(widget.peer.id));

    ref.listen(messagesProvider(widget.peer.id), (prev, next) {
      final list = next.value ?? const <ChatMessage>[];
      if (list.any((m) => m.receiverId == me && !m.isRead)) backend.markThreadRead(widget.peer.id);
      final before = prev?.value ?? const <ChatMessage>[];
      if (before.isNotEmpty && list.length > before.length && list.last.senderId != me) Fx.instance.received();
      if (before.length < list.length) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
    });

    final thread = messages.value ?? const <ChatMessage>[];
    if (_initialIds == null && messages.hasValue) _initialIds = thread.map((m) => m.id).toSet();

    final conn = ref.watch(connectionsProvider).value?.where((x) => x.profile.id == widget.peer.id).firstOrNull;
    final intro = conn?.introText == null
        ? null
        : IntroQuote(
            question: promptById(conn!.introPromptId ?? '')?.question,
            text: conn.introText!,
            label: conn.introFromMe ? 'You replied to their prompt' : '${widget.peer.firstName} replied to your prompt',
            note: 'Sent with the request, before this chat was encrypted.',
          );
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: SafeArea(
          bottom: false,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: VIcon(VIcons.back, size: 24, color: c.ink),
                  tooltip: 'Back',
                ),
                Expanded(
                  child: Pressable(
                    scale: 0.98,
                    haptic: false,
                    onTap: _openProfile,
                    child: Row(
                      children: [
                        Avatar(url: widget.peer.primaryPhoto, name: widget.peer.fullName, size: 44),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      widget.peer.firstName,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600, color: c.ink),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  if (widget.peer.isVerified) const VerifiedBadge(size: 16),
                                ],
                              ),
                              Text(
                                widget.peer.city,
                                style: TextStyle(fontSize: 13, height: 18 / 13, color: c.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: VIcon(VIcons.more, size: 24, color: c.ink),
                  color: c.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  onSelected: (v) async {
                    switch (v) {
                      case 'verify':
                        Navigator.push(context, MaterialPageRoute(builder: (_) => SafetyNumberScreen(peer: widget.peer)));
                      case 'report':
                        if (await showReportSheet(context, widget.peer, thread: thread) && context.mounted) {
                          Navigator.pop(context);
                        }
                      case 'block':
                        if (await confirmBlock(context, ref, widget.peer) && context.mounted) Navigator.pop(context);
                      case 'unmatch':
                        if (await confirmUnmatch(context, ref, widget.peer) && context.mounted) Navigator.pop(context);
                    }
                  },
                  itemBuilder: (_) => [
                    if (backend.isEndToEndEncrypted) _menuItem('verify', PhosphorIconsRegular.shieldCheck, 'Verify encryption'),
                    _menuItem('report', PhosphorIconsRegular.flag, 'Report'),
                    _menuItem('block', PhosphorIconsRegular.prohibit, 'Block'),
                    _menuItem('unmatch', PhosphorIconsRegular.userMinus, 'Unmatch'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              skipLoadingOnReload: true,
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) => list.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _ThreadIntro(peer: widget.peer, encrypted: backend.isEndToEndEncrypted),
                        ?intro,
                      ],
                    )
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      itemCount: list.length + 1,
                      itemBuilder: (_, i) {
                        if (i == list.length) {
                          return Column(
                            children: [
                              _PrivacyPill(encrypted: backend.isEndToEndEncrypted),
                              if (intro != null) Padding(padding: const EdgeInsets.only(top: 8), child: intro),
                            ],
                          );
                        }
                        final m = list[list.length - 1 - i];
                        final older = i + 1 < list.length ? list[list.length - 2 - i] : null;
                        final newer = i > 0 ? list[list.length - i] : null;
                        final showDay = older == null || !DateUtils.isSameDay(older.createdAt, m.createdAt);
                        final mine = m.senderId == me;
                        // Group consecutive bubbles from the same sender.
                        final tail = newer == null || newer.senderId != m.senderId;
                        final picked = _selected.contains(m.id);
                        final bubble = GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onLongPress: () {
                            Fx.instance.tap();
                            _toggle(m);
                          },
                          onTap: _selected.isEmpty ? null : () => _toggle(m),
                          child: AnimatedContainer(
                            duration: Motion.of(context, Motion.fast),
                            decoration: BoxDecoration(
                              color: picked ? c.accent.withValues(alpha: 0.16) : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: _Bubble(message: m, mine: mine, tail: tail, selecting: _selected.isNotEmpty),
                          ),
                        );
                        return Column(
                          children: [
                            if (showDay) _DayChip(m.createdAt),
                            _initialIds?.contains(m.id) ?? true ? bubble : _Arrive(key: ValueKey(m.id), child: bubble),
                          ],
                        );
                      },
                    ),
            ),
          ),
          SafeArea(
            top: false,
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.fast),
              switchInCurve: Motion.easeOut,
              child: _selected.isNotEmpty
                  ? _SelectionBar(
                      key: const ValueKey('select'),
                      count: _selected.length,
                      onCancel: () => setState(_selected.clear),
                      onReport: () => _reportSelected(thread),
                    )
                  : _recording
                  ? VoiceRecorderBar(
                      key: const ValueKey('rec'),
                      recorder: _recorder,
                      onCancel: () => _finishRecording(send: false),
                      onSend: () => _finishRecording(send: true),
                    )
                  : _Composer(
                      key: const ValueKey('compose'),
                      controller: _text,
                      sending: _sending,
                      onSend: () => _sendText(thread),
                      onMic: _startRecording,
                      onPhoto: _sendPhoto,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18, color: context.fc.ink2),
        const SizedBox(width: 10),
        Text(label),
      ],
    ),
  );
}

/// New messages rise 8 px and fade in (180 ms, ease-out).
class _Arrive extends StatelessWidget {
  const _Arrive({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Motion.of(context, Motion.fast),
    curve: Motion.easeOut,
    builder: (_, v, child) => Opacity(
      opacity: v,
      child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child),
    ),
    child: child,
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onMic,
    required this.onPhoto,
  });
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onMic;
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, value, _) {
          final hasText = value.text.trim().isNotEmpty;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: IconButton(
                  onPressed: sending ? null : onPhoto,
                  tooltip: 'Send a photo',
                  icon: Icon(PhosphorIconsRegular.image, size: 26, color: c.ink2),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  style: t.bodyLarge?.copyWith(color: c.ink),
                  decoration: InputDecoration(
                    hintText: 'Message',
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
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              Pressable(
                onTap: sending ? null : (hasText ? onSend : onMic),
                semanticLabel: hasText ? 'Send' : 'Record voice note',
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                  // Mic ↔ send morph: scale + blur crossfade.
                  child: AnimatedSwitcher(
                    duration: Motion.of(context, Motion.fast),
                    switchInCurve: Motion.easeOut,
                    switchOutCurve: Motion.easeOut,
                    transitionBuilder: (child, a) => ScaleTransition(
                      scale: Tween(begin: 0.6, end: 1.0).animate(a),
                      child: FadeTransition(
                        opacity: a,
                        child: AnimatedBuilder(
                          animation: a,
                          builder: (_, child) => ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: (1 - a.value) * 3, sigmaY: (1 - a.value) * 3),
                            child: child,
                          ),
                          child: child,
                        ),
                      ),
                    ),
                    child: sending
                        ? SizedBox(
                            key: const ValueKey('s'),
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: c.paper),
                          )
                        : VIcon(hasText ? VIcons.send : VIcons.voice, key: ValueKey(hasText), size: 22, color: c.paper),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.tail, this.selecting = false});
  final ChatMessage message;
  final bool mine;
  final bool tail;

  /// While picking messages to report, a tap selects instead of opening.
  final bool selecting;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final time = DateFormat('h:mm a').format(message.createdAt);
    final fg = mine ? c.paper : c.ink;
    final meta = mine ? c.paper.withValues(alpha: 0.6) : c.muted;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
        child: Container(
          margin: EdgeInsets.only(top: 3, bottom: tail ? 7 : 2),
          padding: message.isImage ? const EdgeInsets.fromLTRB(4, 4, 10, 6) : const EdgeInsets.fromLTRB(15, 11, 13, 8),
          decoration: BoxDecoration(
            color: mine ? c.accent : c.surface,
            border: mine ? null : Border.all(color: c.hair),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(!mine && tail ? 6 : 22),
              bottomRight: Radius.circular(mine && tail ? 6 : 22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.isImage)
                _PhotoContent(message: message, openable: !selecting)
              else if (message.isVoice)
                VoiceBubble(message: message, color: fg)
              else
                Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: Text(
                    message.content ?? '',
                    style: TextStyle(fontFamily: 'Geist', color: fg, fontSize: 16, height: 22 / 16),
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: TextStyle(fontFamily: 'Geist', color: meta, fontSize: 11),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 3),
                    Icon(message.isRead ? PhosphorIconsBold.checks : PhosphorIconsBold.check, size: 13, color: meta),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// End-to-end encrypted photo: downloaded and decrypted on this device.
class _PhotoContent extends ConsumerStatefulWidget {
  const _PhotoContent({required this.message, this.openable = true});
  final ChatMessage message;
  final bool openable;

  @override
  ConsumerState<_PhotoContent> createState() => _PhotoContentState();
}

class _PhotoContentState extends ConsumerState<_PhotoContent> {
  // Fetched and decrypted once per bubble, so rebuilds never reload or flash the photo.
  late final Future<Uint8List> _future = ref.read(backendProvider).imageBytes(widget.message);

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final openable = widget.openable;
    final c = context.fc;
    final img = message.image;
    final ratio = img != null && img.width > 0 && img.height > 0 ? img.width / img.height : 4 / 5;
    return Semantics(
      image: true,
      label: 'Photo',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 220,
          child: AspectRatio(
            aspectRatio: ratio.clamp(0.6, 1.6),
            child: FutureBuilder(
              future: _future,
              builder: (context, s) {
                if (s.hasError) {
                  return ColoredBox(
                    color: c.hair,
                    child: Center(child: Icon(PhosphorIconsRegular.imageBroken, color: c.muted)),
                  );
                }
                if (!s.hasData) {
                  return ColoredBox(
                    color: c.hair,
                    child: const Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                  );
                }
                return GestureDetector(
                  onTap: !openable
                      ? null
                      : () => Navigator.push(
                          context,
                          PageRouteBuilder<void>(
                            opaque: false,
                            barrierColor: Colors.black,
                            pageBuilder: (_, _, _) => _PhotoViewer(bytes: s.data!),
                            transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
                          ),
                        ),
                  child: Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
    body: Center(child: InteractiveViewer(maxScale: 4, child: Image.memory(bytes))),
  );
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({super.key, required this.count, required this.onCancel, required this.onReport});
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onCancel,
            tooltip: 'Cancel',
            icon: Icon(PhosphorIconsRegular.x, color: c.ink2),
          ),
          Expanded(
            child: Text(
              '$count selected',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: onReport,
            icon: const Icon(PhosphorIconsRegular.flag, size: 18),
            label: const Text('Report'),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, height: 16 / 12, color: context.fc.muted),
      ),
    );
  }
}

/// "End-to-end encrypted. Screenshots are off." — only claimed when the
/// backend really encrypts (never in the demo).
class _PrivacyPill extends StatelessWidget {
  const _PrivacyPill({required this.encrypted});
  final bool encrypted;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(encrypted ? PhosphorIconsFill.lockSimple : PhosphorIconsFill.lockSimpleOpen, size: 13, color: c.ink3),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                encrypted ? 'End-to-end encrypted. Screenshots are off.' : 'Demo chat, not encrypted. Screenshots are off.',
                style: TextStyle(fontSize: 13, height: 18 / 13, color: c.ink3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadIntro extends StatelessWidget {
  const _ThreadIntro({required this.peer, required this.encrypted});
  final PublicProfile peer;
  final bool encrypted;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Avatar(url: peer.primaryPhoto, name: peer.fullName, size: 88),
            const SizedBox(height: 14),
            Text('You and ${peer.firstName} are connected', style: t.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              encrypted
                  ? 'Messages and voice notes are end-to-end encrypted. Only you and ${peer.firstName} can read them.'
                  : 'Say hi. Screenshots are blocked in this chat.',
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
